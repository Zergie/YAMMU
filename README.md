 <!--![GitHub Release](https://img.shields.io/github/v/release/Zergie/YAMMU)-->
 ![GitHub commit activity](https://img.shields.io/github/commit-activity/w/Zergie/YAMMU)

# Yet Another MMU
"Eight Materials, Twin Drawers, One Enclosure."

A Multi-Material Unit (MMU) for eight filaments that can also function as a filament dryer, keeping them dry while printing. The design is heavily inspired by Voron and their printers.

<img src="Images/render_1_processed.png" width="400px"></img>

# Introduction
Currently, this project aims to support loading and unloading filament before a print begins. While it is technically possible to use this version for multi-color or multi-material prints, this is not our focus at the moment. We plan to support both options in the future, once we have a reliable working prototype.

# Features
- Multi-Material Unit for FFF
- Filament loading and unloading via powerful BLDC motors
- Enclosed Heated Filament Storage Built with 2020 Extrusion
- Separate electronics bay, similar to the one in the Voron 2.4
- Strongly inspired by the Voron 2.4 and Trident, this design seamlessly blends in when placed next to a Voron printer. Additionally, it supports the use of Voron user modifications.

# Current state
We are currently gearing up to release the first teaser, version 0.1. At this stage, not everything is running smoothly just yet, so we could really use your help! If you have skills in CAD, electronics, coding, or if you simply have a few hours to spare for testing the current iteration, we'd love to hear from you.

Your input and feedback can make a huge difference, and we’re excited to have the community involved in this journey. Feel free to reach out to me directly if you're interested in contributing. And if you're comfortable with GitHub, pull requests are also more than welcome!

## v1.0
![GitHub issue custom search](https://img.shields.io/github/issues-search?query=repo%3AZergie%2FYAMMU%20state%3Aclosed%20milestone%3Av1.0&label=done&color=green)
![GitHub issue custom search](https://img.shields.io/github/issues-search?query=repo%3AZergie%2FYAMMU%20state%3Aopen%20milestone%3Av1.0&label=todo&color=red)
- Manual Loading, e.g. Loading and Unloading filament before a print is started
- Automatic Loading, e.g. Loading and Unloading filament at the start of a print, for example as a "Filament Start Gcode" in OrcaSlicer
- Heating the Chamber for Drying Filament
- Electronics on Custom PCB

## v2.0
![GitHub issue custom search](https://img.shields.io/github/issues-search?query=repo%3AZergie%2FYAMMU%20state%3Aclosed%20milestone%3Av2.0&label=done&color=green)
![GitHub issue custom search](https://img.shields.io/github/issues-search?query=repo%3AZergie%2FYAMMU%20state%3Aopen%20milestone%3Av2.0&label=todo&color=red)
- All of the above
- Supporting the Extruder via the BLDC motor. When the extruder pulls the filament, the BLDC motor pushes it, and vice versa.

# Used Open Source Parts
- Parts from [Voron Trident](https://github.com/VoronDesign/Voron-Trident/blob/main/LICENSE)
by Voron Design is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
- Parts from [Integrated Auto-Rewind Spool Holder](https://www.thingiverse.com/thing:3781815)
by VincentGroenhuis is licensed under the Creative Commons - Attribution - Share Alike license.
- Parts from [Voron 2.4 Front Panel Handle, Hinge & Magnet Latch](https://www.printables.com/model/371692-voron-24-front-panel-handle-hinge-magnet-latch/files)
by Jason_116929 is licensed under the Creative Commons - Attribution - Share Alike license.
- Parts from [Kit for Removable Panels/Doors for Voron V2/Trident using Strong Snap Latch](https://www.printables.com/model/702768-kit-for-removable-panelsdoors-for-voron-v2trident-/files)
by Victor Mateus Oliveira is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
- Parts from [WAGO 221-415 extrusion mount](https://www.printables.com/model/869020-wago-221-415-extrusion-mount-1by5-and-2by5)
by Artxime is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
- Parts from []()
by #### is licensed under the ####.
