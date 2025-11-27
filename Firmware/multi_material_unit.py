import logging  # noqa: F401
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bldc import BldcMotor
    from klippy.configfile import ConfigWrapper
    from klippy.extras.servo import PrinterServo
    from klippy.gcode import GCodeDispatch
    from klippy.klippy import Printer
    from klippy.mcu import MCU_endstop
    from klippy.pins import PrinterPins
    from klippy.toolhead import ToolHead
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


MMU_TOOL_NUM_START = 0
MMU_LOADING_SPEED = 1.0
MMU_HOMEING_SPEED = 0.7
MMU_RETRACT_SPEED = 0.5
MMU_RETRACT_TIME = 0.2
MMU_EJECT_TIME = 2.0

TIMEOUT_LOADING = 10.0
TIMEOUT_HOMEING = 10.0
TIMEOUT_1H = 3600.0  # 1 hour

BELAY_REPORT_TIME = 0.010
BELAY_SAMPLE_TIME = 0.001
BELAY_SAMPLE_COUNT = 6
BELAY_SETPOINT = 0.5
BELAY_MAX_DELTA = 0.2
BELAY_MOTOR_SPEED = 1.0
PID_PARAM_BASE = 255.

ENDSTOP_SAMPLE_TIME = 0.1

SERVO_SIGNAL_PERIOD = 0.020


class MMUServo(PrinterServo):
    def __init__(self, name: str, servo: PrinterServo) -> None:
        self.name = name
        self._servo = servo

    def set_angle(self, angle: float, print_time: float | None = None) -> None:
        value = self._servo._get_pwm_from_angle(angle)
        if print_time is None:
            self._servo.gcrq.queue_gcode_request(value)
        else:
            self._servo.gcrq.send_async_request(value, print_time)

class MMUControlBase:
    def __init__(self, mmu, config:ConfigWrapper):
        self.mmu = mmu
    def get_status(self, eventtime):
        return {}
    def update(self, read_time: float, value: float):
        pass

class MultiMaterialUnit:
    def __init__(self, config: ConfigWrapper) -> None:
        self.debug = {}
        self.printer: Printer = config.get_printer()
        self.gcode: GCodeDispatch = self.printer.lookup_object("gcode")
        self.printer.register_event_handler("klippy:connect",
                                            self.handle_connect)

        self.tool_start: int = config.getint("tool_numbering_start",
                                             MMU_TOOL_NUM_START, minval=0)
        if self.tool_start < 0:
            raise config.error("tool_numbering_start must be at least 0")
        self.current_tool: int = None

        ppins: PrinterPins = self.printer.lookup_object("pins")

        # Filament Sensor
        self.motion_queuing = self.printer.load_object(config, "motion_queuing")
        self.endstop: MCU_endstop = ppins.setup_pin(
            "endstop", config.get("endstop_pin")
        )

        # Belay Sensor Setup
        self.be_inverted = config.getboolean("belay_inverted", False)
        self.be_pin = ppins.setup_pin("adc", config.get("belay_pin"))
        self.be_pin.setup_adc_sample(BELAY_SAMPLE_TIME, BELAY_SAMPLE_COUNT)
        self.be_pin.setup_adc_callback(BELAY_REPORT_TIME, self.handle_belay)
        self.be_setpoint = config.getfloat(
            "belay_setpoint", BELAY_SETPOINT, minval=0.0, maxval=1.0
        )
        # Setup control algorithm sub-class
        algos = {
            'watermark': MMUControlBangBang,
            'pid': MMUControlPID,
            }
        algo:MMUControlBase = config.getchoice('belay_control', algos)
        self.be_control = algo(self, config)
        self.be_active = False

        # Bldc Motor Setup
        self.bldc_motors: list[BldcMotor] = [
            x for x in config.getlist("bldc_motors", sep=",")
        ]

        # Servo Setup
        self.servos: list[MMUServo] = [
            x for x in config.getlist("servos", sep=",")]
        self.servo_initial_angles: list[float] = []
        for servo_name in self.servos:
            servo_config = config.getsection(f"servo {servo_name}")
            initial_angle = servo_config.getfloat("initial_angle")
            self.servo_initial_angles.append(initial_angle)
        self.servo_angles: list[float] = [
            x for x in config.getlist("servo_angles", sep=",")
        ]

        # Configuration Validations
        if len(self.servos) * 2 != len(self.servo_angles):
            raise config.error(
                "Each servo must have two angles defined in servo_angles"
            )
        if len(self.bldc_motors) * 4 != len(self.servos) * 2:
            raise config.error(
                "For each BLDC motor, there must be two servos defined "
                + "(one servo per two tools)"
            )

        # Gcode Command Registrations
        for command in [
            x for x in dir(self) \
                if x.startswith("cmd_") and callable(getattr(self, x))
        ]:
            if command == self.cmd_TOOLCHANGE.__name__:
                for tool in range(self.tool_start, self.tool_start + 8):
                    self.gcode.register_command(
                        f"T{tool}",
                        self.cmd_TOOLCHANGE,
                        desc=self.cmd_TOOLCHANGE_help.format(tool),
                    )
            else:
                cmd = "MMU_" + command[4:].upper()
                fun = getattr(self, command)
                desc = getattr(self, command + "_help")
                self.gcode.register_command(cmd, fun, desc=desc)

    @property
    def current_motor(self) -> BldcMotor | None:
        if self.current_tool is None:
            return None
        motor_index = (self.current_tool - self.tool_start) // 4
        return self.bldc_motors[motor_index]

    @property
    def current_servo(self) -> MMUServo | None:
        if self.current_tool is None:
            return None
        servo_index = (self.current_tool - self.tool_start) // 2
        return self.servos[servo_index]

    @property
    def current_motor_direction(self) -> int | None:
        if self.current_tool is None:
            return None
        tool_offset = (self.current_tool - self.tool_start) % 2
        return -1 if tool_offset == 0 else 1

    @property
    def print_time(self) -> float:
        return self.toolhead.get_last_move_time()

    def set_motor_speed(self, speed: float) -> None:
        if self.current_motor is not None:
            self.current_motor.set_speed(
                speed * self.current_motor_direction, self.print_time
            )

    def get_status(self, eventtime):
        return {
            "belay_active": self.be_active,
            "belay_setpoint": self.be_setpoint,
            "belay_control": {
                "name": type(self.be_control).__name__,
                **self.be_control.get_status(eventtime)
            },
            "current_tool": self.current_tool,
            "current_motor": self.current_motor.name if self.current_motor \
                else None,
            "current_motor_direction": self.current_motor_direction,
            "current_motor_speed": (self.current_motor_direction
                * self.current_motor.speed) if self.current_motor else None,
            "debug": self.debug,
        }

    ######     ###    ##       ##       ########     ###     ######  ##     ##  ######
    ##    ##   ## ##   ##       ##       ##     ##   ## ##   ##    ## ##    ##  ##    ##
    ##        ##   ##  ##       ##       ##     ##  ##   ##  ##       ##   ##   ##
    ##       ##     ## ##       ##       ########  ##     ## ##       #####      ######
    ##       ######### ##       ##       ##     ## ######### ##       ##   ##         ##
    ##    ## ##     ## ##       ##       ##     ## ##     ## ##    ## ##    ##  ##    ##
    ######  ##     ## ######## ######## ########  ##     ##  ######  ##     ##  ######
    def handle_connect(self) -> None:
        self.toolhead: ToolHead = self.printer.lookup_object("toolhead")
        self.bldc_motors = [
            self.printer.lookup_object(f"bldc {x}") for x in self.bldc_motors
        ]
        self.servos = [
            MMUServo(x, self.printer.lookup_object(f"servo {x}")) \
                for x in self.servos
        ]

    def handle_belay(self, read_time, read_value) -> None:
        if self.current_motor is None:
            return
        if not self.be_active:
            return

        # invert and clamp the read value
        value = max(0.00001, min(0.99999, read_value))
        if self.be_inverted:
            value = 1.0 - value

        self.be_control.update(read_time, value)

    ######    ######   #######  ########  ########
    ##    ##  ##    ## ##     ## ##     ## ##
    ##        ##       ##     ## ##     ## ##
    ##   #### ##       ##     ## ##     ## ######
    ##    ##  ##       ##     ## ##     ## ##
    ##    ##  ##    ## ##     ## ##     ## ##
    ######    ######   #######  ########  ########
    def select_tool(self, tool: int | None,
                    print_time: float | None = None) -> None:
        servo_index = None if tool is None else (tool - MMU_TOOL_NUM_START) // 2

        for i, servo in [x for x in enumerate(self.servos) \
            if x[0] != servo_index]:
            angle = self.servo_initial_angles[i]
            servo.set_angle(angle, print_time)

        if servo_index is not None:
            servo = self.servos[servo_index]
            angle = float(self.servo_angles[tool])
            servo.set_angle(angle, print_time)

        if tool is None:
            self.set_motor_speed(0.0)

        self.current_tool = tool

    def unload_tool(self, gcmd: GCodeDispatch, tool: int | None = None) -> None:
        if self.endstop.query_endstop(self.print_time) == 1:
            if self.current_tool is None:
                gcmd.respond_info(
                    "Unknown filament loaded, please unload MANUALLY..")
                self.move(0.0, False, TIMEOUT_1H)
            elif tool is None or self.current_tool != tool:
                gcmd.respond_info(f"Unloading tool {self.current_tool}..")
                self.move(-MMU_LOADING_SPEED, False, TIMEOUT_LOADING)

    def move(self, speed: float, trigger: bool, timeout: float) -> None:
        endstop_value = 1 if trigger else 0
        move_start_time = self.print_time

        self.set_motor_speed(speed)

        print_time = self.print_time
        while self.endstop.query_endstop(print_time) != endstop_value:
            self.toolhead.dwell(ENDSTOP_SAMPLE_TIME)
            if (print_time - move_start_time) > timeout:
                self.set_motor_speed(0.0)
                raise self.gcode.error(
                    "MMU move timeout: endstop not triggered")
            print_time = self.print_time

        self.set_motor_speed(0.0)

    cmd_TOOLCHANGE_help = "Change to tool {0}"
    def cmd_TOOLCHANGE(self, gcmd: GCodeDispatch) -> None:
        tool = int(gcmd.get_command()[1:])
        if tool < self.tool_start:
            raise gcmd.error(f"Tool number must be at least {self.tool_start}")
        elif tool >= self.tool_start + len(self.servos) * 2:
            raise gcmd.error(
                "Tool number must be at most "
                + f"{self.tool_start + len(self.servos) * 2 - 1}"
            )
        self.be_active = False

        self.unload_tool(gcmd, tool)

        if self.current_tool is None or self.current_tool != tool:
            gcmd.respond_info(f"Loading tool {tool}..")
            self.select_tool(tool, self.print_time)
            self.move(MMU_LOADING_SPEED, True, TIMEOUT_LOADING)
            gcmd.respond_info(f"Tool {tool} loaded.")
        else:
            gcmd.respond_info(f"Tool {tool} already load.")

        self.be_active = True

    cmd_HOME_help = "Homes the specified tool."
    def cmd_HOME(self, gcmd: GCodeDispatch) -> None:
        tool = gcmd.get_int(
            "TOOL",
            None,
            minval=self.tool_start,
            maxval=self.tool_start + len(self.servos) * 2 - 1,
        )
        if tool is None:
            raise gcmd.error("HOME command requires a TOOL parameter")
        self.be_active = False

        # Unload any loaded tool first
        self.unload_tool(gcmd)

        # Select tool to home
        self.select_tool(tool, self.print_time)

        # Move tool in front of endstop
        timeout = TIMEOUT_HOMEING / 2
        gcmd.respond_info(f"Homeing tool {tool}..")
        self.move(MMU_HOMEING_SPEED, True, timeout)
        self.move(-MMU_HOMEING_SPEED, False, timeout)

        # Retract tool extra
        self.set_motor_speed(-MMU_RETRACT_SPEED)
        self.toolhead.dwell(MMU_RETRACT_TIME)
        self.set_motor_speed(0.0)

        self.select_tool(None, self.print_time)
        gcmd.respond_info(f"Tool {tool} homed.")

        self.be_active = True

    cmd_EJECT_help = "Ejects filament from the MMU."
    def cmd_EJECT(self, gcmd: GCodeDispatch) -> None:
        tool = gcmd.get_int(
            "TOOL",
            None,
            minval=self.tool_start,
            maxval=self.tool_start + len(self.servos) * 2 - 1,
        )
        self.be_active = False

        last_tool = self.current_tool
        if last_tool is not None and last_tool == tool:
            self.unload_tool(gcmd)

        self.select_tool(tool, self.print_time)
        self.set_motor_speed(-MMU_LOADING_SPEED)
        self.toolhead.dwell(MMU_EJECT_TIME)
        self.set_motor_speed(0.0)

        if last_tool is not None and last_tool == tool:
            self.select_tool(None, self.print_time)
            gcmd.respond_info(f"Tool {tool} ejected, no tool loaded.")
        else:
            self.select_tool(last_tool, self.print_time)
            gcmd.respond_info(
                f"Tool {tool} ejected, tool {self.current_tool} still loaded."
            )

        self.be_active = True

    cmd_ENGAGE_help = "Engages selected MMU servos to their tool angles."
    def cmd_ENGAGE(self, gcmd: GCodeDispatch) -> None:
        tool = gcmd.get_int(
            "TOOL",
            None,
            minval=self.tool_start,
            maxval=self.tool_start + len(self.servos) * 2 - 1,
        )
        if tool is None:
            raise gcmd.error("ENGAGE command requires a TOOL parameter")
        self.select_tool(tool)
        self.be_active = True

    cmd_DISENGAGE_help = "Disengages all MMU servos to their initial angles."
    def cmd_DISENGAGE(self, gcmd: GCodeDispatch) -> None:
        self.be_active = False
        self.select_tool(None)


class MMUControlBangBang(MMUControlBase):
    def __init__(self, mmu:MultiMaterialUnit, config:ConfigWrapper):
        MMUControlBase.__init__(self, mmu, config)
        self.max_delta = config.getfloat(
            "belay_max_delta", BELAY_MAX_DELTA, minval=0.0, maxval=1.0
        )
        self.motor_speed = config.getfloat(
            "belay_motor_speed", BELAY_MOTOR_SPEED, minval=0.0, maxval=1.0
        )
        self.debug = {}
    def get_status(self, eventtime):
        return {
            **MMUControlBase.get_status(self, eventtime),
        }
    def update(self, read_time: float, value: float):
        distance = abs(value - self.mmu.be_setpoint)

        if distance > self.max_delta:
            target_value = self.mmu.be_setpoint

            if value >= target_value+self.max_delta:
                self.mmu.set_motor_speed(-self.motor_speed)
            elif value <= target_value-self.max_delta:
                self.mmu.set_motor_speed(self.motor_speed)
        else:
            self.mmu.set_motor_speed(0.0)

class MMUControlPID(MMUControlBase):
    def __init__(self, mmu: MultiMaterialUnit, config):
        self.mmu = mmu
        self.Kp = config.getfloat('belay_Kp') / PID_PARAM_BASE
        self.Ki = config.getfloat('belay_Ki') / PID_PARAM_BASE
        self.Kd = config.getfloat('belay_Kd') / PID_PARAM_BASE
        self.min_deriv_time = mmu.get_smooth_time()
        self.value_integ_max = 0.
        if self.Ki:
            self.value_integ_max = 1.0 / self.Ki
        self.prev_value = .5
        self.prev_value_time = 0.
        self.prev_value_deriv = 0.
        self.prev_value_integ = 0.
    def get_status(self, eventtime):
        return {
            **MMUControlBase.get_status(self, eventtime),
        }
    def update(self, read_time: float, value: float):
        target_value = self.mmu.be_setpoint
        time_diff = read_time - self.prev_value_time
        # Calculate change of value
        value_diff = value - self.prev_value
        if time_diff >= self.min_deriv_time:
            value_deriv = value_diff / time_diff
        else:
            value_deriv = (
                self.prev_value_deriv * (self.min_deriv_time-time_diff)
                + value_diff) / self.min_deriv_time
        # Calculate accumulated value "error"
        value_err = target_value - value
        value_integ = self.prev_value_integ + value_err * time_diff
        value_integ = max(0., min(self.value_integ_max, value_integ))
        # Calculate output
        co = self.Kp*value_err + self.Ki*value_integ - self.Kd*value_deriv
        bounded_co = max(-1., min(1., co))
        self.mmu.set_motor_speed(bounded_co)
        # Store state for next measurement
        self.prev_value = value
        self.prev_value_time = read_time
        self.prev_value_deriv = value_deriv
        if co == bounded_co:
            self.prev_value_integ = value_integ

def load_config(config):
    return MultiMaterialUnit(config)

def load_config_prefix(config):
    return MultiMaterialUnit(config)
