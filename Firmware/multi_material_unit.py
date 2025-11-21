import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from klippy.configfile import ConfigWrapper
    from klippy.klippy import Printer
    from klippy.pins import PrinterPins
    from klippy.gcode import GCodeDispatch
    from klippy.toolhead import ToolHead
    from klippy.extras.servo import PrinterServo
    from klippy.mcu import MCU_endstop
    from bldc import BldcMotor
else:
    # fallbacks for runtime type checking
    ConfigWrapper = object
    Printer = object
    PrinterPins = object
    GCodeDispatch = object
    ToolHead = object
    PrinterServo = object
    MCU_endstop = object
    BldcMotor = object


MMU_TOOL_NUM_START  = 0
MMU_UNLOADING_SPEED = -1.0
MMU_LOADING_SPEED   = 1.0

TIMEOUT_LOADING = 10.0
TIMEOUT_1H      = 3600.0 # 1 hour

BELAY_REPORT_TIME = 0.300
BELAY_SAMPLE_TIME = 0.001
BELAY_SAMPLE_COUNT = 6
BELAY_SETPOINT = 0.5
BELAY_DEADZONE = 0.1

ENDSTOP_SAMPLE_TIME = .1

SERVO_SIGNAL_PERIOD = 0.020

class MMUServo(PrinterServo):
    def __init__(self, name:str, servo:PrinterServo) -> None:
        self.name = name
        self._servo = servo
    def set_angle(self, angle:float, print_time:float|None = None) -> None:
        value = self._servo._get_pwm_from_angle(angle)
        if print_time is None:
            self._servo.gcrq.queue_gcode_request(value)
        else:
            self._servo.gcrq.send_async_request(value, print_time)

class MultiMaterialUnit:
    debug = True

    def __init__(self, config:ConfigWrapper) -> None:
        self.printer: Printer = config.get_printer()
        self.gcode: GCodeDispatch = self.printer.lookup_object('gcode')
        self.printer.register_event_handler("klippy:connect",
                                    self.handle_connect)

        self.tool_start:int = config.getint('tool_numbering_start',
                                            MMU_TOOL_NUM_START)
        if self.tool_start < 0:
            raise config.error("tool_numbering_start must be at least 0")
        for tool in range(self.tool_start, self.tool_start + 8):
            self.gcode.register_command(f'T{tool}', self.cmd_TOOLCHANGE, desc=\
                                        self.cmd_TOOLCHANGE_help.format(tool))
        self.current_tool:int = None

        ppins:PrinterPins = self.printer.lookup_object('pins')

        # Filament Sensor
        self.motion_queuing = self.printer.load_object(config, 'motion_queuing')
        self.endstop:MCU_endstop = ppins.setup_pin('endstop', config.get('endstop_pin'))
        self.endstop_value = None

        # Belay Sensor Setup
        # self.be_inverted = config.getboolean('belay_inverted', False)
        # self.be_pin = ppins.setup_pin('adc', config.get('belay_pin'))
        # self.be_pin.setup_adc_sample(BELAY_SAMPLE_TIME, BELAY_SAMPLE_COUNT)
        # self.be_pin.setup_adc_callback(BELAY_REPORT_TIME, self.belay_callback)
        self.be_value = 0
        # self.belay_setpoint = config.getfloat('belay_setpoint', BELAY_SETPOINT,
        #                                       minval=0., maxval=1.)
        # self.be_deadzone = config.getfloat('belay_deadzone', BELAY_DEADZONE,
        #                                    minval=0., maxval=.5)
        self.be_active = False

        # Bldc Motor Setup
        self.bldc_motors: list[BldcMotor] = [
            x for x in config.getlist('bldc_motors', sep=',')]

        # Servo Setup
        self.servos: list[MMUServo] = [
            x for x in config.getlist('servos', sep=',')]
        self.servo_initial_angles: list[float] = []
        for servo_name in self.servos:
            servo_config = config.getsection(f'servo {servo_name}')
            initial_angle = servo_config.getfloat('initial_angle')
            self.servo_initial_angles.append(initial_angle)
        self.servo_angles: list[float] = [
            x for x in config.getlist('servo_angles', sep=',')]

        # Configuration Validations
        if len(self.servos)*2 != len(self.servo_angles):
            raise config.error(
                "Each servo must have two angles defined in servo_angles")
        if len(self.bldc_motors)*4 != len(self.servos)*2:
            raise config.error(
                "For each BLDC motor, there must be two servos defined " +
                "(one servo per two tools)")

        # Gcode Command Registrations
        self.gcode.register_command('MMU_SET_MOTOR_SPEED',
                                    self.cmd_SET_MOTOR_SPEED,
                                    desc=self.cmd_SET_MOTOR_SPEED_help)
        self.gcode.register_command('MMU_ENGAGE',
                                    self.cmd_ENGAGE,
                                    desc=self.cmd_ENGAGE_help)
        self.gcode.register_command('MMU_DISENGAGE',
                                    self.cmd_DISENGAGE,
                                    desc=self.cmd_DISENGAGE_help)

    def _debug_msg(self, msg: str) -> None:
        if self.debug:
            self.gcode.respond_info(f"[MMU DEBUG] {msg}")

    @property
    def current_motor(self) -> BldcMotor|None:
        if self.current_tool is None:
            return None
        motor_index = (self.current_tool - self.tool_start) // 4
        return self.bldc_motors[motor_index]

    @property
    def current_servo(self) -> MMUServo|None:
        if self.current_tool is None:
            return None
        servo_index = (self.current_tool - self.tool_start) // 2
        return self.servos[servo_index]

    @property
    def current_motor_direction(self) -> int|None:
        if self.current_tool is None:
            return None
        tool_offset = (self.current_tool - self.tool_start) % 2
        return 1 if tool_offset == 0 else -1

    def get_status(self, eventtime):
        return {
            "belay_active": self.be_active,
            "belay_value": self.be_value,
            "endstop_state": self.endstop_value,
            "current_tool": self.current_tool,
            "current_motor": self.current_motor.name if self.current_motor
                                else None,
            "current_motor_direction": self.current_motor_direction,
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
        self.bldc_motors = [
            self.printer.lookup_object(f'bldc {x}') for x in self.bldc_motors]
        self.servos = [
            MMUServo(x, self.printer.lookup_object(f'servo {x}'))
            for x in self.servos]

        mcu = self.endstop.get_mcu()
        min_sched_time = mcu.min_schedule_time()
        systime = self.printer.get_reactor().monotonic()
        print_time = mcu.estimated_print_time(systime + min_sched_time)
        self.endstop_value = self.endstop.query_endstop(print_time)

    def belay_callback(self, read_time, read_value) -> None:
        if self.current_motor is None:
            return

        self.be_value = max(.00001, min(.99999, read_value))
        if self.be_inverted:
            self.be_value = 1.0 - self.be_value

        self.be_value = self.be_value
        distance = self.be_value - self.belay_setpoint
        min_schedule_time = self.current_motor.mcu.min_schedule_time()

        if abs(distance) < self.be_deadzone / 2:
            self.be_value = self.belay_setpoint
            self.current_motor.set_speed(0, read_time + min_schedule_time)
            self._debug_msg(
                f"BELAY within deadzone: {self.be_value:.3f} -> motor stopped")
        else:
            motor_speed = 1.0 * self.current_motor_direction

            if distance > 0:
                motor_speed *= -1

            self.current_motor.set_speed(motor_speed,
                                         read_time + min_schedule_time)
            if distance > 0:
                self._debug_msg(
                    f"BELAY above setpoint: {self.be_value:.3f}" +
                    f" -> motor speed: {self.current_motor.speed:.3f}")
            else:
                self._debug_msg(
                    f"BELAY below setpoint: {self.be_value:.3f}" +
                    f" -> motor speed: {self.current_motor.speed:.3f}")


     ######    ######   #######  ########  ########
    ##    ##  ##    ## ##     ## ##     ## ##
    ##        ##       ##     ## ##     ## ##
    ##   #### ##       ##     ## ##     ## ######
    ##    ##  ##       ##     ## ##     ## ##
    ##    ##  ##    ## ##     ## ##     ## ##
     ######    ######   #######  ########  ########
    def _select_tool(self, tool:int|None, print_time:float|None = None) -> None:
        servo_index = None if tool is None \
                           else (tool - MMU_TOOL_NUM_START) // 2

        for i, servo in [
            x for x in enumerate(self.servos) if x[0] != servo_index]:
            angle = self.servo_initial_angles[i]
            self._debug_msg(f"SET_SERVO SERVO={servo.name} ANGLE={angle}")
            servo.set_angle(angle, print_time)

        if servo_index is not None:
            servo = self.servos[servo_index]
            angle = float(self.servo_angles[tool])
            self._debug_msg(f"SET_SERVO SERVO={servo.name} ANGLE={angle}")
            servo.set_angle(angle, print_time)

        self.current_tool = tool

    def _move(self, speed:float, trigger:bool, timeout:float) -> None:
        endstop_value = 1 if trigger else 0
        move_start_time = self.print_time

        if self.current_motor is not None:
            self.current_motor._set_value(self.print_time, speed)

        print_time = self.print_time
        while self.endstop.query_endstop(print_time) != endstop_value:
            self.toolhead.dwell(ENDSTOP_SAMPLE_TIME)
            if (print_time - move_start_time) > TIMEOUT_LOADING:
                raise self.gcode.error("MMU move timeout: endstop not triggered")
            print_time = self.print_time

        if self.current_motor is not None:
            self.current_motor._set_value(self.print_time, 0.0)

    @property
    def print_time(self) -> float:
        return self.toolhead.get_last_move_time()

    cmd_TOOLCHANGE_help = "Change to tool {0}"
    def cmd_TOOLCHANGE(self, gcmd:GCodeDispatch) -> None:
        tool = int(gcmd.get_command()[1:])
        self.be_active = False

        if self.endstop.query_endstop(self.print_time) == 1:
            if self.current_tool is None:
                gcmd.respond_info("Unknown filament loaded, please unload MANUALLY..")
                self._move(0.0, False, TIMEOUT_1H)
            elif self.current_tool != tool:
                gcmd.respond_info(f"Unloading tool {self.current_tool}..")
                self._move(MMU_LOADING_SPEED, False, TIMEOUT_LOADING)

        if self.current_tool is None or self.current_tool != tool:
            gcmd.respond_info(f"Loading tool {tool}..")
            self._select_tool(tool, self.print_time)
            self._move(MMU_LOADING_SPEED, True, TIMEOUT_LOADING)
            gcmd.respond_info(f"Tool {tool} loaded.")
        else:
            gcmd.respond_info(f"Tool {tool} already load.")

        self.be_active = True

    cmd_ENGAGE_help = "Engages selected MMU servos to their tool angles."
    def cmd_ENGAGE(self, gcmd:GCodeDispatch) -> None:
        tool = gcmd.get_int('TOOL', None, minval=self.tool_start,
                            maxval=self.tool_start + len(self.servos)*2 - 1)
        if tool is None:
            raise gcmd.error("ENGAGE command requires a TOOL parameter")
        self._select_tool(tool)
        self.be_active = True

    cmd_DISENGAGE_help = "Disengages all MMU servos to their initial angles."
    def cmd_DISENGAGE(self, gcmd:GCodeDispatch) -> None:
        self.be_active = False
        self._select_tool(None)

    cmd_SET_MOTOR_SPEED_help =  "Sets the speed of the MMU BLDC motors." + \
        " Usage: MMU_SET_MOTOR_SPEED MOTOR=<motor> SPEED=<speed>"
    def cmd_SET_MOTOR_SPEED(self, gcmd:GCodeDispatch) -> None:
        index:int = gcmd.get_int('MOTOR', None, minval=0,
                                 maxval=len(self.bldc_motors)-1)
        speed:float = gcmd.get_float('SPEED', None, minval=0.0, maxval=1.0)
        if (index is None) or (speed is None):
            raise gcmd.error(
                "Both MOTOR and SPEED parameters are required.")
        self.bldc_motors[index].set_speed(speed)
        gcmd.respond_info(f"Set MMU BLDC motor {index} speed to {speed}")

def load_config(config):
    return MultiMaterialUnit(config)

def load_config_prefix(config):
    return MultiMaterialUnit(config)
