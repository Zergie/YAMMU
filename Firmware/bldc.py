import logging  # noqa: F401
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from klippy.extras import pulse_counter, output_pin
    from klippy.configfile import ConfigWrapper
    from klippy.klippy import Printer
    from klippy.pins import PrinterPins
    from klippy.gcode import GCodeDispatch
    from klippy.mcu import MCU_digital_out, MCU_pwm, MCU
    from klippy.reactor import SelectReactor as Reactor
else:
    from . import pulse_counter, output_pin

    # fallbacks for runtime type checking
    ConfigWrapper = object
    Printer = object
    PrinterPins = object
    GCodeDispatch = object
    MCU_digital_out = object
    MCU_pwm = object
    Reactor = object

CYCLE_TIME = 0.00005  # 20 kHz
OFF_BELOW = 0.5
TACHOMETER_STARTUP_DELAY = 2.0
TACHOMETER_WATCH_INTERVAL = 0.5
TACHOMETER_MIN_RPM = 5.0
TACHOMETER_POLL_INTERVAL = 0.0002
TACHOMETER_SAMPLE_TIME = TACHOMETER_WATCH_INTERVAL / 2
TACHOMETER_PPR = 9

FORWARD = True
REVERSE = False


class BldcMotor:
    debug = True

    def __init__(self, config: ConfigWrapper):
        self.name = config.get_name().split()[1]
        self.printer: Printer = config.get_printer()
        self.gcode: GCodeDispatch = self.printer.lookup_object("gcode")
        self.reactor: Reactor = self.printer.get_reactor()
        ppins: PrinterPins = self.printer.lookup_object("pins")

        self.off_below = config.getfloat(
            "off_below", default=OFF_BELOW, minval=0.0, maxval=1.0
        )
        cycle_time = config.getfloat("cycle_time", CYCLE_TIME)

        self.pwm_pin: MCU_pwm = ppins.setup_pin("pwm", config.get("pin"))
        self.mcu: MCU = self.pwm_pin.get_mcu()
        hardware_pwm = config.getboolean("hardware_pwm", True)
        self.pwm_pin.setup_cycle_time(cycle_time, hardware_pwm)
        self.pwm_pin.setup_max_duration(0.0)
        self.pwm_pin.setup_start_value(0.0, 0.0)

        self.dir_pin: MCU_digital_out = ppins.setup_pin(
            "digital_out", config.get("direction_pin")
        )
        self.dir_pin.setup_start_value(0.0, 0.0)
        self.dir_pin.setup_max_duration(0.0)
        self.direction = FORWARD

        tachometer_pin = config.get("tachometer_pin")
        self.ppr = config.getint("tachometer_ppr", TACHOMETER_PPR, minval=1)
        poll_interval = config.getfloat(
            "tachometer_poll_interval", TACHOMETER_POLL_INTERVAL, above=0.0
        )
        self._freq_counter = pulse_counter.FrequencyCounter(
            self.printer, tachometer_pin, TACHOMETER_SAMPLE_TIME, poll_interval
        )
        self.rpm = 0.0

        self.gcrq = output_pin.GCodeRequestQueue(config, self.mcu,
                                                 self._set_value)
        self.sample_timer = self.reactor.register_timer(self._watch_rpm)
        self.last_value = 0.0

        # Register commands
        gcode: GCodeDispatch = self.printer.lookup_object("gcode")
        gcode.register_mux_command(
            "SET_BLDC",
            "MOTOR",
            self.name,
            self.cmd_SET_BLDC,
            desc=self.cmd_SET_BLDC_help,
        )

    def _debug_msg(self, msg: str) -> None:
        if self.debug:
            gcode = self.printer.lookup_object("gcode")
            gcode.respond_info(f"[BLDC DEBUG] {msg}")

    def _watch_rpm(self, eventtime: float):
        self.rpm = self._freq_counter.get_frequency() * 30.0 / self.ppr
        speed = self.last_value if self.last_value is not None else 0.0

        print_time = self.mcu.estimated_print_time(eventtime)
        self._debug_msg(
            f"{print_time:.1f} [watchdog] BLDC Motor '{self.name}': "
            + f"speed={speed:.3f}, rpm={self.rpm:.1f}"
        )
        if abs(speed) < self.off_below and self.rpm > TACHOMETER_MIN_RPM:
            self._set_value(print_time, 0.0)
            raise self.gcode.error(
                f"BLDC Motor '{self.name}' is OFF but reports non-zero RPM"
            )
        elif abs(speed) >= self.off_below and self.rpm < TACHOMETER_MIN_RPM:
            raise self.gcode.error(
                f"BLDC Motor '{self.name}' is ON but reports zero RPM"
            )
        elif abs(speed) < self.off_below:
            return self.reactor.NEVER

        return self.reactor.monotonic() + TACHOMETER_WATCH_INTERVAL

    def _set_value(self, print_time: float, value: float):
        if abs(value) < self.off_below:
            value = 0.0
        if value != self.last_value:
            if (self.last_value == 0 or self.last_value > 0) and value < 0:
                self._debug_msg(
                    f"{print_time:.2f}, Changing direction to reverse")
                self.dir_pin.set_digital(print_time, 1)
                self.direction = REVERSE
                print_time += self.mcu.min_schedule_time()
            elif (self.last_value == 0 or self.last_value < 0) and value > 0:
                self._debug_msg(
                    f"{print_time:.2f}, Changing direction to forward")
                self.dir_pin.set_digital(print_time, 0)
                self.direction = FORWARD
                print_time += self.mcu.min_schedule_time()

            self._debug_msg(f"{print_time:.2f}, Setting speed to {value:.3f}")
            self.last_value = value
            self.pwm_pin.set_pwm(print_time, abs(value))

            self._debug_msg(f"{print_time:.2f}, Scheduling RPM watch")
            waketime = self.reactor.monotonic() + TACHOMETER_STARTUP_DELAY
            self.reactor.update_timer(self.sample_timer, waketime)

        return "discard", 0.0

    @property
    def speed(self) -> float:
        return self.last_value

    def set_speed(self, value: float, print_time: float | None = None):
        if print_time is None:
            min_sched_time = self.mcu.min_schedule_time()
            systime = self.printer.get_reactor().monotonic()
            print_time = self.mcu.estimated_print_time(systime + min_sched_time)
        self._set_value(print_time, value)

    def set_speed_from_command(self, value: float):
        self.gcrq.queue_gcode_request(value)

    def get_status(self, eventtime):
        return {
            "direction": "forward" if self.direction == FORWARD else "reverse",
            "speed": self.last_value,
            "rpm": self.rpm,
        }

    cmd_SET_BLDC_help = "Set BLDC motor speed (-1.0 to 1.0)"

    def cmd_SET_BLDC(self, gcmd: GCodeDispatch):
        speed = gcmd.get_float("SPEED", None, minval=-1.0, maxval=1.0)
        self.set_speed_from_command(speed)


def load_config_prefix(config):
    return BldcMotor(config)
