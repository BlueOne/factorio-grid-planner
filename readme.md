
# Grid Planner

Plan out base geometry and reserve space by assigning chunks to regions. Basically a pixel art editor on a large grid overlaid on the factorio map, intended for planning factory layouts.

Inspired by [GridLocked](https://mods.factorio.com/mod/gridlocked), Bigfoot's [Base Engineering Video](https://www.youtube.com/watch?v=Lpdd9iz7awU) and [Pyanodon Mods](https://mods.factorio.com/mod/pymodpack). Uses [Flib](https://mods.factorio.com/mod/flib).

## Features

__General__: Undo, Redo, Configure Visibility, Configure Grid Size and Offset.

__Drawing Tools__: Rect Draw, Pipette

__Region Config__: Create, Delete, Configure, Regions. Change Region Order in Display

__Layers__: Multiple layers per surface, each with its own grid size and offset. Layers can be reordered, hidden, or deleted independently.

### Hotkey Defaults
* __Rect Draw Tool__:  Control + Shift + R
* __Pipette__:  Control + Shift + Q
* __Undo__:  Control + Shift + Z
* __Redo__:  Control + Shift + Y
* __More Visible__: Control + Shift + W
* __Less Visible__: Control + Shift + S

__Multiplayer Notes__: Players have separate undo/redo queues, which is fine if the edits don't overlap but might be confusing if they do. 

## Future

There is always more that one can do but right now the mod works well for me and my personal requirements. If enough people are interested I might put some more time into it. Or you can make a pull request. 

Features I might add if people poke me and I find the time: 

* Some way to draw at specific distances. Not sure on the UI yet. 

* Select, Copy, Paste, Rotate, Mirror, for symmetry enjoyers

* A way to differentiate regions beyond color, to increase visual clarity. Not sure what to do exactly yet. 

* Performance optimization (see below). 

* Better UI Styling

Performance is good but there is potential for optimization. On my device drawing ~1k grid cells makes the game stutter noticably, deletion and changing color is faster. It takes a long time to reach this point in natural gameplay: 1) I increase grid size when build size increases, for example due to construction bots or simply batching more and 2) I delete areas where no more planning is needed because the area is settled. There are a few ways to deal with this: pool and reuse render objects, reduce features e.g. less visibility levels or no boundaries, ask factorio devs for an api to create more render objects simultaneously, or work over multiple ticks. 