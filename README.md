# Yet Another MMU
"Eight Materials, Twin Drawers, One Enclosure."

A Multi Material Unit (MMU) for eight filaments that can also function as a filament dryer and can keep it dry while printing. The design is heavily inspired by voron and their printers. 

# Introduction
todo

At the moment this project aims not support loading and unloading filament before a print is started. While techniclly possible to use this version for example multicolor prints, this is not our focus at the moment. Future versions will support multicolor prints.

## Features
- Multi Material Unit for FFF
- Filament loading/unloading via strong BLDC motors
- Enclosed Heated Filament Storage build with 2020 extrusion
- Separate Electronics Bay like seen in Voron 2.4


# BOM
| Part Description   | Standard           | Qty |
|--------------------|--------------------|-----|
| KHFS5-2020-420     |                    |   6 |
| KHFS5-2020-500     |                    |   4 |
| KHFS5-2020-200     |                    |   4 |
| M5x16 BHCS         | ISO 7380-1         |   ? |
| M3x8 SHCS          | ISO 4762 / DIN 912 |   ? |
| M3 T-Nut           |                    |   ? |
| M4 T-Nut           |                    |   ? |
| M5 T-Nut           |                    |   ? |
| M5x?? Threaded Rod | DIN 975 / DIN 976  |   4 |
| M5 Hex Nut         | ISO 4033 / DIN 934 |   8 |
| 608 Ball Bearing   |                    |  16 |
| Rubber Feet 38x19  |                    |   4 |


# Where to get aluminium extrusions?
In europe misumi does not ship to individuals, so it is quite hard to get them. But there are some options:

## KHFS5-2020
| Slot Width | Hole Diameter |
|------------|---------------|
|        6mm |         4.2mm |

These are the original voron extrusions. This means if you can get them you can also use parts that
are designed for a voron, like voron mods.

## 20x20 Slot 5 I-Type
| Slot Width | Hole Diameter |
|------------|---------------|
|        5mm |         4.2mm |

This extrusion shares the same hole Diameter like the original extrusions, but has a narrower slot.
Like KHFS5-2020 the holes can be tapped M5 directly without any drilling. But original voron parts
will not fit without modification. If you choose these for your build, use the STLs from the
**Nut5** folder.

## 20x20 Slot 6 I-Type
| Slot Width | Hole Diameter |
|------------|---------------|
|        6mm |         5.1mm |

Like the original KHFS5-2020, these share the same slot width. So original voron parts and voron
mods will fit. For the blind joints you can use M6x16 bolts instead of the M5x16. For tapping M6 a
5mm hole is needed, but 5.1mm is close enough.


You also can get an M5 Helicoli set and bore the hole out to 5.2mm with the included drill bit.
After installing the Helicoli, use M5x16 like with the original extrusions.

## 20x20 Slot 6 B-Type
| Slot Width | Hole Diameter |
|------------|---------------|
|        6mm |     5.5-6.6mm |

The most common 20x20 extrusion in europe. It shares the same slot width, so original voron
parts and voron mods are an alternative. For blind joints use M6x16 bolts and a M6 Helicoli set.
Bore the hole out to 6.3mm with the included drill bit and install the M6 Helicoli.

# Used Open Source Parts
- Parts from [Voron Trident](https://github.com/VoronDesign/Voron-Trident/blob/main/LICENSE)
by Voron Design is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
- Parts from [Integrated Auto-Rewind Spool Holder](https://www.thingiverse.com/thing:3781815)
by VincentGroenhuis is licensed under the Creative Commons - Attribution - Share Alike license.
- Parts from [Voron 2.4 Front Panel Handle, Hinge & Magnet Latch](https://www.printables.com/model/371692-voron-24-front-panel-handle-hinge-magnet-latch/files)
by Jason_116929 is licensed under the Creative Commons - Attribution - Share Alike license.
- Parts from [Kit for Removable Panels/Doors for Voron V2/Trident using Strong Snap Latch](https://www.printables.com/model/702768-kit-for-removable-panelsdoors-for-voron-v2trident-/files)
by Victor Mateus Oliveira is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
- Parts from []()
by #### is licensed under the ####.
