import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from klippy.configfile import ConfigWrapper
    from klippy.klippy import Printer
    from klippy.pins import PrinterPins
    from klippy.gcode import GCodeDispatch
    from klippy.toolhead import ToolHead
    from klippy.extras.servo import PrinterServo
    from bldc import BldcMotor
else:
    # fallbacks for runtime type checking
    ConfigWrapper = object
    Printer = object
    PrinterPins = object
    GCodeDispatch = object
    ToolHead = object
    BldcMotor = object
    PrinterServo = object


MMU_TOOL_NUM_START = 0

BELAY_REPORT_TIME = 0.300
BELAY_SAMPLE_TIME = 0.001
BELAY_SAMPLE_COUNT = 6
BELAY_SETPOINT = 0.5
BELAY_DEADZONE = 0.1

SERVO_SIGNAL_PERIOD = 0.020

class MMUServo(PrinterServo):
    def __init__(self, name:str, servo:PrinterServo) -> None:
        self.name = name
        self._servo = servo
    def set_angle(self, angle:float) -> None:
        pwm = self._servo._get_pwm_from_angle(angle)
        self._servo.gcrq.queue_gcode_request(pwm)

class MultiMaterialUnit:
    debug = True
    def __init__(self, config:ConfigWrapper) -> None:
        self.printer: Printer = config.get_printer()
        self.gcode: GCodeDispatch = self.printer.lookup_object('gcode')
        self.printer.register_event_handler("klippy:connect",
                                    self.handle_connect)

        tool_start:int = config.getint('tool_numbering_start', MMU_TOOL_NUM_START)
        if tool_start < 0:
            raise config.error("tool_numbering_start must be at least 0")
        for tool in range(tool_start, tool_start + 8):
            self.gcode.register_command(f'T{tool}', self.cmd_TOOLCHANGE, desc=f"Change to tool {tool}")

        ppins:PrinterPins = self.printer.lookup_object('pins')

        # # Belay Sensor Setup
        # self.be_inverted = config.getboolean('belay_inverted', False)
        # self.be_pin = ppins.setup_pin('adc', config.get('belay_pin'))
        # self.be_pin.setup_adc_sample(BELAY_SAMPLE_TIME, BELAY_SAMPLE_COUNT)
        # # self.be_pin.setup_adc_callback(BELAY_REPORT_TIME, self.belay_callback)
        # self.be_value = 0
        # self.belay_setpoint = config.getfloat('belay_setpoint', BELAY_SETPOINT, minval=0., maxval=1.)
        # self.be_deadzone = config.getfloat('belay_deadzone', BELAY_DEADZONE, minval=0., maxval=.5)

        # Bldc Motor Setup
        self.bldc_motors: list[BldcMotor] = [x for x in config.getlist('bldc_motors', sep=',')]

        # Servo Setup
        self.servos: list[MMUServo] = [x for x in config.getlist('servos', sep=',')]
        self.servo_initial_angles: list[float] = []
        for servo_name in self.servos:
            servo_config = config.getsection(f'servo {servo_name}')
            initial_angle = servo_config.getfloat('initial_angle')
            self.servo_initial_angles.append(initial_angle)
        self.servo_angles: list[float] = [x for x in config.getlist('servo_angles', sep=',')]

        if len(self.servos)*2 != len(self.servo_angles):
            raise config.error("Each servo must have two angles defined in servo_angles")
        if len(self.bldc_motors)*4 != len(self.servos)*2:
            raise config.error("For each BLDC motor, there must be two servos defined (one servo per two tools)")

        # Gcode Command Registrations
        self.gcode.register_command('MMU_SET_MOTOR_SPEED', self.cmd_SET_MOTOR_SPEED, desc=self.cmd_SET_MOTOR_SPEED_help)
        self.gcode.register_command('MMU_ENGAGE', self.cmd_ENGAGE, desc=self.cmd_ENGAGE_help)
        self.gcode.register_command('MMU_DISENGAGE', self.cmd_DISENGAGE, desc=self.cmd_DISENGAGE_help)

    def _debug_msg(self, msg: str) -> None:
        if self.debug:
            self.gcode.respond_info(f"[MMU DEBUG] {msg}")

    def get_status(self, eventtime):
        return {
        }

     ######     ###    ##       ##       ########     ###     ######  ##     ##  ######
    ##    ##   ## ##   ##       ##       ##     ##   ## ##   ##    ## ##    ##  ##    ##
    ##        ##   ##  ##       ##       ##     ##  ##   ##  ##       ##   ##   ##
    ##       ##     ## ##       ##       ########  ##     ## ##       #####      ######
    ##       ######### ##       ##       ##     ## ######### ##       ##   ##         ##
    ##    ## ##     ## ##       ##       ##     ## ##     ## ##    ## ##    ##  ##    ##
     ######  ##     ## ######## ######## ########  ##     ##  ######  ##     ##  ######
    def handle_connect(self) -> None:
        self.toolhead:ToolHead = self.printer.lookup_object('toolhead')
        self.bldc_motors = [self.printer.lookup_object(f'bldc {x}') for x in self.bldc_motors]
        self.servos = [MMUServo(x, self.printer.lookup_object(f'servo {x}')) for x in self.servos]

    def belay_callback(self, read_time, read_value) -> None:
        self.be_value = max(.00001, min(.99999, read_value))

        if self.be_inverted:
            self.be_value = 1.0 - self.be_value

        self.be_value = self.be_value
        distance = self.be_value - self.belay_setpoint
        if abs(distance) < self.be_deadzone / 2:
            self.be_value = self.belay_setpoint
            self._debug_msg(f"BELAY within deadzone: {self.be_value:.3f}")
        elif distance > 0:
            self._debug_msg(f"BELAY above setpoint: {self.be_value:.3f}")
        else:
            self._debug_msg(f"BELAY below setpoint: {self.be_value:.3f}")

     ######    ######   #######  ########  ########
    ##    ##  ##    ## ##     ## ##     ## ##
    ##        ##       ##     ## ##     ## ##
    ##   #### ##       ##     ## ##     ## ######
    ##    ##  ##       ##     ## ##     ## ##
    ##    ##  ##    ## ##     ## ##     ## ##
     ######    ######   #######  ########  ########
    def _select_tool(self, tool:int) -> None:
        servo_index = (tool - MMU_TOOL_NUM_START) // 2

        for i, servo in [x for x in enumerate(self.servos) if x[0] != servo_index]:
            angle = self.servo_initial_angles[i]
            self._debug_msg(f"SET_SERVO SERVO={servo.name} ANGLE={angle}")
            servo.set_angle(angle)

        servo = self.servos[servo_index]
        angle = float(self.servo_angles[tool])
        self._debug_msg(f"SET_SERVO SERVO={servo.name} ANGLE={angle}")
        servo.set_angle(angle)

        self.gcode.respond_info(f"Tool {tool} selected")

    def cmd_TOOLCHANGE(self, gcmd:GCodeDispatch) -> None:
        tool = int(gcmd.get_command()[1:])
        #TODO: unload current tool filament
        self._select_tool(tool)
        #TODO: load new tool filament

    cmd_ENGAGE_help = "Engages selected MMU servos to their tool angles."
    def cmd_ENGAGE(self, gcmd:GCodeDispatch) -> None:
        tool = gcmd.get_int('TOOL', None, minval=MMU_TOOL_NUM_START, maxval=MMU_TOOL_NUM_START + len(self.servos)*2 - 1)
        if tool is None:
            raise gcmd.error("ENGAGE command requires a TOOL parameter")
        self._select_tool(tool)

    cmd_DISENGAGE_help = "Disengages all MMU servos to their initial angles."
    def cmd_DISENGAGE(self, gcmd:GCodeDispatch) -> None:
        for i, servo in enumerate(self.servos):
            angle = self.servo_initial_angles[i]
            gcmd.respond_info(f"SET_SERVO SERVO={servo.name} ANGLE={angle}")
            servo.set_angle(angle)

    cmd_SET_MOTOR_SPEED_help = "Sets the speed of the MMU BLDC motors. Usage: MMU_SET_MOTOR_SPEED MOTOR=<motor> SPEED=<speed>"
    def cmd_SET_MOTOR_SPEED(self, gcmd:GCodeDispatch) -> None:
        index:int = gcmd.get_int('MOTOR', None, minval=0, maxval=len(self.bldc_motors)-1)
        speed:float = gcmd.get_float('SPEED', None, minval=0.0, maxval=1.0)
        if (index is None) or (speed is None):
            raise gcmd.error("MMU_SET_MOTOR_SPEED command must specify both MOTOR and SPEED parameters")
        self.bldc_motors[index].set_speed(speed)
        gcmd.respond_info(f"Set MMU BLDC motor {index} speed to {speed}")

def load_config(config):
    return MultiMaterialUnit(config)

def load_config_prefix(config):
    return MultiMaterialUnit(config)
