import logging

ADC_REPORT_TIME = 0.300
ADC_SAMPLE_TIME = 0.001
ADC_SAMPLE_COUNT = 6

class MultiMaterialUnit:
    def __init__(self, config) -> None:
        self.config = config
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')

        tool_start = config.getint('tool_numbering_start', 0)
        if tool_start < 0:
            raise config.error("tool_numbering_start must be at least 0")
        tool_carriges = config.getint('tool_carriges', 2)
        if tool_carriges < 1:
            raise config.error("tool_count must be at least 1")
        for tool in range(tool_start, tool_start + tool_carriges * 4):
            self.gcode.register_command(f'T{tool}', self.cmd_TOOLCHANGE, desc=f"Change to tool {tool}")

        ppins = self.printer.lookup_object('pins')

        self.belay_inverted = config.getboolean('belay_inverted', False)
        self.be_pin = ppins.setup_pin('adc', config.get('belay_pin'))
        self.be_pin.setup_adc_sample(ADC_SAMPLE_TIME, ADC_SAMPLE_COUNT)
        self.be_pin.setup_adc_callback(ADC_REPORT_TIME, self.belay_callback)
        self.be_value = 0
        self.gcode.register_command('QUERY_BE', self.cmd_QUERY_BE, desc=self.cmd_QUERY_BE_help)

     ######     ###    ##       ##       ########     ###     ######  ##     ##  ######
    ##    ##   ## ##   ##       ##       ##     ##   ## ##   ##    ## ##    ##  ##    ##
    ##        ##   ##  ##       ##       ##     ##  ##   ##  ##       ##   ##   ##
    ##       ##     ## ##       ##       ########  ##     ## ##       #####      ######
    ##       ######### ##       ##       ##     ## ######### ##       ##   ##         ##
    ##    ## ##     ## ##       ##       ##     ## ##     ## ##    ## ##    ##  ##    ##
     ######  ##     ## ######## ######## ########  ##     ##  ######  ##     ##  ######
    def belay_callback(self, read_time, read_value) -> None:
        old_value = self.be_value
        new_value = max(.00001, min(.99999, read_value))

        if self.belay_inverted:
            new_value = 1.0 - new_value

        if abs(old_value - new_value) > 0.05:
            self.gcode.run_script("RESPOND MSG=\"YAMMU Belay Sensor ADC Value %.4f\"" % (new_value)) # TODO: remove debug message later
            self.be_value = new_value

     ######    ######   #######  ########  ########
    ##    ##  ##    ## ##     ## ##     ## ##
    ##        ##       ##     ## ##     ## ##
    ##   #### ##       ##     ## ##     ## ######
    ##    ##  ##       ##     ## ##     ## ##
    ##    ##  ##    ## ##     ## ##     ## ##
     ######    ######   #######  ########  ########
    def cmd_TOOLCHANGE(self, gcmd) -> None:
        tool = int(gcmd.get_command()[1:])
        gcmd.respond_info(f"tool {tool} selected") # TODO: implement tool change logic

    # TODO: remove this debug command later
    cmd_QUERY_BE_help = "Queries the YAMMU Belay Sensor"
    def cmd_QUERY_BE(self, gcmd) -> None:
        gcmd.respond_info("== YAMMU Belay Sensor ==")
        gcmd.respond_info("Belay Sensor ADC Value: %.4f" % (self.be_value,))
        gcmd.respond_info("Thermistor Sensor ADC Value: %.4f" % (self.th_value,))

def load_config(config):
    return MultiMaterialUnit(config)

def load_config_prefix(config):
    return MultiMaterialUnit(config)
