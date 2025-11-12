import logging

ADC_REPORT_TIME = 0.300
ADC_SAMPLE_TIME = 0.001
ADC_SAMPLE_COUNT = 6

class MultiMaterialUnit:
    def __init__(self, config) -> None:
        self.config = config
        self.printer = config.get_printer()
        self.name = config.get_name()

        ppins = self.printer.lookup_object('pins')
        gcode = self.printer.lookup_object('gcode')

        self.be_pin = ppins.setup_pin('adc', config.get('belay_sensor_pin'))
        self.be_pin.setup_adc_sample(ADC_SAMPLE_TIME, ADC_SAMPLE_COUNT)
        self.be_pin.setup_adc_callback(ADC_REPORT_TIME, self.be_callback)
        self.be_time = 0
        self.be_value = 0
        gcode.register_command('QUERY_BE', self.cmd_QUERY_BE, desc=self.cmd_QUERY_BE_help)

        self.th_pin = ppins.setup_pin('adc', config.get('thermistor_sensor_pin'))
        self.th_pin.setup_adc_sample(ADC_SAMPLE_TIME, ADC_SAMPLE_COUNT)
        self.th_pin.setup_adc_callback(ADC_REPORT_TIME, self.th_callback)
        self.th_time = 0
        self.th_value = 0

    def be_callback(self, read_time, read_value) -> None:
        self.be_time = read_time
        adc = max(.00001, min(.99999, read_value))
        self.be_value = 10000.0 * (adc / (1.0 - adc))

    def th_callback(self, read_time, read_value) -> None:
        self.th_time = read_time
        self.th_value = read_value

    cmd_QUERY_BE_help = "Queries the YAMMU Belay Sensor"
    def cmd_QUERY_BE(self, gcmd) -> None:
        gcmd.respond_info("== YAMMU Belay Sensor ==")
        gcmd.respond_info("Belay Sensor Time: %.3f s" % (self.be_time,))
        gcmd.respond_info("Belay Sensor ADC Value: %.4f" % (self.be_value,))
        gcmd.respond_info("Thermistor Sensor Time: %.3f s" % (self.th_time,))
        gcmd.respond_info("Thermistor Sensor ADC Value: %.4f" % (self.th_value,))

def load_config(config):
    return MultiMaterialUnit(config)