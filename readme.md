
# Grid Planner

Plan out base geometry and reserve space by assigning chunks to regions. Basically a pixel art editor on a large grid overlaid on the factorio map, intended for planning factory layouts.

Inspired by [GridLocked](https://mods.factorio.com/mod/gridlocked), Bigfoot's [Base Engineering Video](https://www.youtube.com/watch?v=Lpdd9iz7awU) and [Pyanodon Mods](https://mods.factorio.com/mod/pymodpack). Uses [Flib](https://mods.factorio.com/mod/flib).

## Features

__General__: Undo, Redo, Configure Visibility, Configure Grid Size and Offset.

__Drawing Tools__: Rect Draw, Pipette

__Region Config__: Create, Delete, Configure, Regions. Change Region Order in Display

### Hotkey Defaults
* __Rect Draw Tool__:  Control + Shift + R
* __Pipette__:  Control + Shift + Q
* __Undo__:  Control + Shift + Z
* __Redo__:  Control + Shift + Y
* __More Visible__: Control + Shift + W
* __Less Visible__: Control + Shift + S

__Multiplayer Notes__: Players have separate undo/redo queues, which is fine if the edits don't overlap but might be confusing if they do. 

## Future

There is always more that one can do but right now the mod works well for me and my personal requirements. If enough people are interested I might put some more time into it. 

Performance is good but there is potential for optimization. On my device drawing ~1k grid cells makes the game stutter noticably, deletion and changing color is faster. It takes a long time to reach this point in natural gameplay due to two reasons: It makes sense to increase grid size when your build size increases, for example due to construction bots or simply batching more. It also makes sense to delete areas where no more planning is needed because the area is settled.

Features I might add enough people poke me and I find the time: 

* Some way to draw at specific distances. Not sure on the UI yet. 

* Layers, e.g. to allow different grid sizes on the same surface.

* Select, Copy, Paste, Rotate, Mirror, for symmetry enjoyers

* A way to differentiate regions beyond color, to increase visual clarity. Not sure what to do exactly yet. 

* Performance optimization or batch long operations over multiple ticks. 

* Better UI Styling