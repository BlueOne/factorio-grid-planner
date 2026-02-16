
require("prototypes.sprites")
require("prototypes.styles")

local function selection_tool(
  name,
  icon,
  icon_size,
  select_color,
  alt_select_color
)
  return {
    type = "selection-tool",
    name = name,
    icon = icon or "__base__/graphics/icons/blueprint.png",
    icon_size = icon_size or 64,
    dark_background_icon = icon or "__base__/graphics/icons/blueprint.png",
    dark_background_icon_size = icon_size or 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    subgroup = "tool",
    order = "a[grid-planner]-" .. name,
    stack_size = 1,
    select = {
      border_color = select_color or {r = 0.8, g = 0.8, b = 0.8},
      cursor_box_type = "entity",
      mode = "nothing"
    },
    alt_select = {
      border_color = alt_select_color or {r = 0.5, g = 0.5, b = 0.5},
      cursor_box_type = "entity",
      mode = "nothing"
    },
    mouse_cursor = "selection-tool-cursor",
  }
end

local tools = {
  selection_tool(
    "grid-planner-rectangle-tool",
    "__base__/graphics/icons/blueprint.png",
    64,
    {r = 0.8, g = 0.8, b = 0.8},
    {r = 0.5, g = 0.5, b = 0.5}
  ),
}

data:extend(tools)

local hotkeys = {
  {
    type = "custom-input",
    name = "gp-select-rect-tool",
    key_sequence = "CONTROL + SHIFT + R",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = "gp-visibility-increase",
    key_sequence = "CONTROL + SHIFT + W",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = "gp-visibility-decrease",
    key_sequence = "CONTROL + SHIFT + S",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = "gp-undo",
    key_sequence = "CONTROL + SHIFT + Z",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = "gp-redo",
    key_sequence = "CONTROL + SHIFT + Y",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = "gp-pipette",
    key_sequence = "CONTROL + SHIFT + Q",
    consuming = "game-only"
  },
}

data:extend(hotkeys)
