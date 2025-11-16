import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from klippy.extras import pulse_counter, output_pin
    from klippy.configfile import ConfigWrapper
    from klippy.klippy import Printer
    from klippy.pins import PrinterPins
    from klippy.gcode import GCodeDispatch
    from klippy.mcu import MCU_digital_out, MCU_pwm
else:
    from . import pulse_counter, output_pin
    # fallbacks for runtime type checking
    ConfigWrapper = object
    Printer = object
    PrinterPins = object
    GCodeDispatch = object
    MCU_digital_out = object
    MCU_pwm = object

CYCLE_TIME = 0.00005  # 20 kHz
OFF_BELOW = 0.5
TACHOMETER_WATCH_INTERVAL = 0.5
TACHOMETER_ERROR_TIMEOUT = TACHOMETER_WATCH_INTERVAL * 3
TACHOMETER_POLL_INTERVAL = 0.0002
TACHOMETER_SAMPLE_TIME = TACHOMETER_WATCH_INTERVAL / 2
TACHOMETER_PPR = 9

class BldcMotor:
    def __init__(self, config:ConfigWrapper):
        self.name = config.get_name().split()[1]
        self.printer: Printer = config.get_printer()
        ppins: PrinterPins = self.printer.lookup_object('pins')

        self.off_below = config.getfloat(f'off_below', default=OFF_BELOW, minval=0., maxval=1.)
        cycle_time = config.getfloat(f'cycle_time', CYCLE_TIME)

        self.pwm_pin:MCU_pwm = ppins.setup_pin('pwm', config.get('pin'))
        self.mcu = self.pwm_pin.get_mcu()
        hardware_pwm = config.getboolean('hardware_pwm', True)
        self.pwm_pin.setup_cycle_time(cycle_time, hardware_pwm)
        self.pwm_pin.setup_max_duration(0.)
        self.pwm_pin.setup_start_value(0., 0.)

        self.dir_pin:MCU_digital_out = ppins.setup_pin('digital_out', config.get('direction_pin'))
        self.dir_pin.setup_start_value(0., .0)

        tachometer_pin = config.get('tachometer_pin')
        self.ppr = config.getint('tachometer_ppr', TACHOMETER_PPR, minval=1)
        poll_interval = config.getfloat('tachometer_poll_interval', TACHOMETER_POLL_INTERVAL, above=0.)
        self._freq_counter = pulse_counter.FrequencyCounter(self.printer, tachometer_pin, TACHOMETER_SAMPLE_TIME, poll_interval)
        self.tachometer_error = None
        self.rpm = 0.0

        self.speed_rq = output_pin.GCodeRequestQueue(config, self.mcu, self._set_value)
        self.tacho_rq = output_pin.GCodeRequestQueue(config, self.mcu, self._watch_rpm)
        self.last_value = 0.0

        # Register commands
        gcode: GCodeDispatch = self.printer.lookup_object('gcode')
        gcode.register_mux_command("SET_BLDC", "MOTOR", self.name,
                            self.cmd_SET_BLDC,
                            desc=self.cmd_SET_BLDC_help)

    def _watch_rpm(self, print_time:float, value:float):
        self.rpm = self._freq_counter.get_frequency() * 30. / self.ppr
        speed = self.last_value if self.last_value is not None else 0.0

        logging.info(f"{print_time:.1f} [watchdog] BLDC Motor '{self.name}': speed={speed:.3f}, rpm={self.rpm:.1f}")
        error = None
        if abs(speed) < self.off_below and self.rpm > 5.:
            error = f"BLDC Motor '{self.name}' should be off but reports non-zero RPM"
        elif abs(speed) >= self.off_below and self.rpm < 5.:
            error = f"BLDC Motor '{self.name}' should be on but reports zero RPM"

        if error and self.tachometer_error == None:
            self.tachometer_error = print_time
        elif not error:
            self.tachometer_error = None

        # shutdown if error persists too long
        if self.tachometer_error:
            if (print_time - self.tachometer_error) > TACHOMETER_ERROR_TIMEOUT:
                logging.error(error)
                raise self.printer.invoke_shutdown(error)
            else:
                return "delay", TACHOMETER_WATCH_INTERVAL
        elif speed >= self.off_below:
            return "delay", TACHOMETER_WATCH_INTERVAL
        else:
            return "discard", 0.

    def _set_value(self, print_time:float, value:float):
        if abs(value) < self.off_below:
            value = 0.
        if value != self.last_value:
            if (self.last_value == 0 or self.last_value > 0) and value < 0:
                logging.info(f"{print_time:.1f} BLDC Motor '{self.name}': Changing direction to reverse")
                self.dir_pin.set_digital(print_time, 1)
                self.last_value = -.001
                return "delay", 0.1  # allow time for direction change
            elif (self.last_value == 0 or self.last_value < 0) and value > 0:
                logging.info(f"{print_time:.1f} BLDC Motor '{self.name}': Changing direction to forward")
                self.dir_pin.set_digital(print_time, 0)
                self.last_value = .001
                return "delay", 0.1  # allow time for direction change
            self.last_value = value
            logging.info(f"{print_time:.1f} BLDC Motor '{self.name}': Setting speed to {value:.3f}")
            self.pwm_pin.set_pwm(print_time, abs(value))
        return "discard", 0.

    def set_speed(self, value:float, print_time:float=None):
        if print_time is None:
            min_sched_time = self.mcu.min_schedule_time()
            systime = self.printer.get_reactor().monotonic()
            print_time = self.mcu.estimated_print_time(systime + min_sched_time)
        self.speed_rq.send_async_request(value, print_time)
        self.tacho_rq.send_async_request(value, print_time)

    def set_speed_from_command(self, value:float):
        self.speed_rq.queue_gcode_request(value)
        self.tacho_rq.queue_gcode_request(value)

    def get_status(self, eventtime):
        return {
            'direction': 'forward' if self.dir_pin.get_digital() == 0 else 'reverse',
            'speed': self.last_value,
            'rpm': self.rpm,
        }

    cmd_SET_BLDC_help = "Set BLDC motor speed (-1.0 to 1.0)"
    def cmd_SET_BLDC(self, gcmd:GCodeDispatch):
        speed = gcmd.get_float('SPEED', None, minval=-1.0, maxval=1.0)
        self.set_speed_from_command(speed)

def load_config_prefix(config):
    return BldcMotor(config)
