
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
    flags = {"only-in-cursor"},
    subgroup = "tool",
    order = "a[zone-planner]-" .. name,
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
  }
end

local tools = {
  selection_tool(
    "zone-planner-rectangle-tool",
    "__base__/graphics/icons/blueprint.png",
    64,
    {r = 0.8, g = 0.8, b = 0.8},
    {r = 0.5, g = 0.5, b = 0.5}
  ),
}

data:extend(tools)
