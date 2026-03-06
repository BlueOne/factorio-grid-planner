# Design Document: Grid Planner

## 1. Overview

### 1.1 Product Name
Grid Planner

### 1.2 Problem Statement
Bad geometric planning is a well-known pain point in Factorio: it leads to tearing down or redoing parts of the base, long belt routing tasks, or decision paralysis. Players spend up to ??% more gameplay time than needed due to poor planning (this is a hobby project so we didn't do a study but it is a well established fact). 

Existing alternatives for base planning are concrete and ghosts, which are insufficient:
- **Concrete**: Too slow and tedious for broad-strokes planning
- **Ghosts**: Too specific and detailed; not suitable for high-level spatial organization

### 1.3 Solution
Grid Planner is a Factorio mod that provides a pixel art editor overlaid on the game map, enabling players to plan base geometry and reserve space by assigning chunks to regions. The tool helps players visualize and organize factory layouts before construction, bridging the gap between high-level planning and detailed implementation.

### 1.4 Inspiration
- **[GridLocked](https://mods.factorio.com/mod/gridlocked)**: Also draws a grid on the map but is not a planning tool.
- Bigfoot's [Base Engineering Video](https://www.youtube.com/watch?v=Lpdd9iz7awU)
- [Pyanodon Mods](https://mods.factorio.com/mod/pymodpack)

### 1.5 Dependencies
- [Flib](https://mods.factorio.com/mod/flib) library: Provides GUI helpers and event management utilities

## 2. Goals and Objectives

### 2.1 Primary Goals
- Allow players to assign map chunks to different regions
- Enable visualization of planned base geometry
- Provide space reservation for different factory components (belts, assembly areas, trains, stations)
- Support base planning without affecting gameplay mechanics

### 2.2 Success Criteria
- Can plan a base in a 50x50 chunk grid without noticeable lag
- Can plan a mega base, with possible performance issues
- Undo/redo works reliably for the last 50 operations
- Multiplayer support enables collaborative planning without data corruption

## 3. Target Users

### 3.1 Why I Built This
I enjoy getting lost in details but enjoy the safety that comes from building out broad strokes plans first. I made this tool to ensure that while building I don't accidentally use space that was reserved for another build and that I have enough space to get belts to each corner of the base. In multiplayer, I like to communicate to other players that certain space is reserved, but the available options (concrete/ghosts) aren't good enough.

### 3.2 User Personas
- **Chaotic Engineers**: People who like chaos but want the safety net of reserved space
- **Meticulous Planners**: Players who prefer to plan their entire base before construction
- **Large-Scale Builders**: Players managing megabases requiring careful spatial organization

### 3.3 Use Cases
- Planning belt routing and main bus layouts
- Reserving space for assembly areas before construction
- Organizing train networks and station positions
- Dividing base into logical production zones

## 4. Current Features (MVP)

### 4.1 General Features
- **Undo/Redo**: Full undo and redo capability for all drawing operations
- **Visibility Configuration**: Adjustable visibility levels for grid overlay
- **Grid Customization**: Configurable grid size and offset

### 4.2 Drawing Tools
- **Rectangle Draw Tool**: Draw rectangular regions on the map
  - Hotkey: Control + Shift + R
- **Pipette Tool**: Sample existing region colors/properties
  - Hotkey: Control + Shift + Q

### 4.3 Region Management
- **Create Regions**: Define new regions with custom properties
- **Delete Regions**: Remove existing regions
- **Configure Regions**: Modify region properties (color, name, etc.)
- **Region Ordering**: Change display order of regions

### 4.4 Visibility Controls
- **More Visible**: Increase grid opacity
  - Hotkey: Control + Shift + W
- **Less Visible**: Decrease grid opacity
  - Hotkey: Control + Shift + S

### 4.5 Layer Management
- **Multiple Layers**: Each surface supports multiple independent layers
- **Per-Layer Grid**: Each layer has its own configurable grid size and offset
- **Layer Ordering**: Change layer display order
- **Layer Visibility**: Show or hide individual layers
- **Layer CRUD**: Create, rename, and delete layers

### 4.6 Hotkeys Summary
| Action | Default Hotkey |
|--------|---------------|
| Rect Draw Tool | Control + Shift + R |
| Pipette | Control + Shift + Q |
| Undo | Control + Shift + Z |
| Redo | Control + Shift + Y |
| More Visible | Control + Shift + W |
| Less Visible | Control + Shift + S |

## 5. Future Features (Roadmap)

### 5.1 High Priority
- **Distance Measurement**: Tool for drawing at specific distances
  - Status: UI design needed
  - Rationale: Specific distances are useful for more detailed planning (e.g., train spacing, belt routing)
  
### 5.2 Medium Priority
- **Selection Tools**: Select, Copy, Paste operations
- **Transformation Tools**: Rotate and Mirror for symmetry operations
- **Visual Differentiation**: Additional ways to differentiate regions beyond color

### 5.3 Low Priority
- **Performance Optimization**: Render object pooling and reuse
- **UI Styling**: Enhanced visual design and styling
- **Color Blind Support**: Pattern-based differentiation for accessibility

## 6. Technical Requirements

### 6.1 Architecture
The implementation is structured into three main modules:
- **backend.lua**: Core business logic
    - **backend_data.lua** Core data representation
    - **commands.lua** Commands acting on backend data e.g. rect draw tool or region crud
- **ui.lua**: User interface construction and management
- **render.lua**: Rendering of grid overlay on game map

Supporting modules:
- **tests.lua**: Backend testing functionality
- **shared.lua**: Shared utilities
- **migrations.lua**: Data layout migrations for version changes

### 6.2 UI Architecture
- UI follows a reconstruction pattern: when data changes, entire UI is recreated
- Little direct UI modification after construction to maintain simplicity
- Store state of open dialogs in tags
- Event registration for user interactions

### 6.3 Data Management
- Custom data types must be documented for linter support
- Public module functions require documentation
- Data stored in Factorio's `storage` (formerly `global`)
- Data migrations required when storage layout changes

### 6.4 Rendering Requirements
- Minimize render object creation
- Reuse existing render objects when possible
- Notify renderer when image data changes

### 6.5 Testing
- Test functions should be separate and focused
- Tests accessible via remote interface
- No crashes on test exceptions

### 6.6 Factorio API Compatibility
- Target version: Factorio 2.0
- Key API changes:
  - `global` renamed to `storage`
  - Functions moved from `game` to `rendering`, `helpers`, etc.
- Reference: https://lua-api.factorio.com/latest

## 7. Performance Considerations

### 7.1 Current State
- Drawing ~1,000 grid cells causes noticeable stutter
- Deletion and color changes are faster than creation
- Performance adequate for normal gameplay patterns

### 7.2 Mitigating Factors
- Players naturally increase grid size as builds scale
- Players delete settled areas that no longer need planning
- Performance issues only emerge at scale

### 7.3 Optimization Strategies
- Render object pooling: Maintain pool of unused objects, make invisible instead of destroying
- Reduce features: Simplify visibility levels or boundaries
- Multi-tick operations: Spread long operations across multiple game ticks
- API requests: Request Factorio devs to support simultaneous render object creation

## 8. Multiplayer Support

### 8.1 Current Implementation
- Each player maintains separate undo/redo queue
- Works well for non-overlapping edits
- Potential confusion with overlapping edits

### 8.2 Known Limitations
- No conflict resolution for simultaneous edits
- No shared undo/redo state

## 9. Constraints and Limitations

### 9.1 Technical Constraints
- Render object creation performance (Factorio API limitation)
- Single-tick operations may cause lag at scale

### 9.2 Design Constraints
- Regions are visual only and don't affect gameplay
- No direct enforcement of planned areas

### 9.3 Future Considerations
- Long operations need handling: forbid, warn, or distribute across ticks

## 10. Development Guidelines

### 10.1 Code Standards
- Document all custom data types
- Document all public module functions
- Maintain test coverage for backend logic
- Use pcall for exception safety in tests

### 10.2 Data Migration
- Required when changing storage layout
- Must maintain backward compatibility
- Implementation: See [migrations.lua](scripts/migrations.lua) for versioned migration functions
- Migration approach:
  - Each mod version can have a migration function
  - Migrations run on mod update, transforming old data structures to new format
  - Example migrations: converting single grid to per-surface grids (v0.1.1→0.1.2), clearing incompatible undo queues (v0.1.2→0.1.3)
  - After structural changes, UI is rebuilt for all players to reflect new data layout

### 10.3 UI Development
- Use constructor-only pattern
- Recreate UI on state changes
- Persist dialog states

### 10.4 Rendering Development
- Minimize object creation
- Maximize object reuse
- Maintain visibility state efficiently

## 11. Release Strategy

### 11.1 Current State
- Mod is feature-complete for creator's personal needs
- Currently functional and stable

### 11.2 Future Development
- Additional features dependent on community interest
- Open to pull requests from community
- Further development requires user engagement and feedback

## 12. Success Metrics

### 12.1 User Adoption
- Download count
- Active user retention
- Community engagement (forum posts, issues, pull requests)

### 12.2 Performance Metrics
- Grid cell count before noticeable lag
- Operation response times (draw, delete, color change)

### 12.3 Quality Metrics
- Bug reports
- Multiplayer stability

## 13. Open Questions

1. **Distance Drawing UI**: What interface pattern works best for precise distance-based drawing? 
    Ask mod creator discussion on discord. 
    Ideas: Measuring tape, highlighted grid render

2. **Visual Differentiation**: What additional visual cues beyond color would improve region clarity? 
    Fine for me personally, address only if needed. 

3. **Performance Threshold**: At what grid cell count should optimization become mandatory?

4. **Community Priority**: Which future features are most valuable to users?
