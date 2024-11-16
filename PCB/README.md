# Features

- 4 Servo Ports with 6V Power
- 3x Fan Ports
- 2x Thermister Ports
- 1x Heater Port
- I2C Pin Header
- Neopixel RGB Header (with one Neopixel on board)
- 12 V Power Input
- 2x 12 V Power Output Ports

## USB
The board can be connected using either the STM32 USB port or a CH340 USB serial IC. If you're opting for the STM32 USB port, do not popolate these SMD pads:
![image](https://github.com/user-attachments/assets/38513605-c38f-48f0-9bbe-68923505209e)

If you choose to use the CH340 USB Serial, connect it by linking pins PA11 and PA12 with the pin headers. Just bridge the solder pads at this spot:
![image](https://github.com/user-attachments/assets/35ac5567-3317-4076-a89c-7117c5c36658)

## I2C
The board features an I2C booster circuit that makes it easier to connect I2C sensors, such as humidity sensors like the AHT20, even with long cables. This setup lets you monitor humidity. To cut costs, you can choose not to populate these SMD pads:

![image](https://github.com/user-attachments/assets/1506159f-0504-4d30-831f-f1ef7b11003c)

## Soldering Assistant Tool
In EasyEda Pro, you can use the Soldering Assistant Tool. To find it, open your main PCB file, "PCB_1." Then, click on "Tools" and select "Soldering Assistant Tool."

![image](https://github.com/user-attachments/assets/db1e9562-be85-4fbc-bc90-c9f83cec9a41)


[EasyEda Pro](https://pro.easyeda.com/editor#id=5c5aed2dd44f48b9a0c28280d7f15482)
