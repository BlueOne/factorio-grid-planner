
local shared = {}

function shared.parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

---Bounds of a cell in a grid
---@param g Any
---@param cx number, in tiles
---@param cy number, in tiles
---@return table {left: number, top: number}, 
---@return {right: number, bottom: number}
function shared.cell_bounds(g, cx, cy)
  local left = cx * g.width + g.x_offset
  local top = cy * g.height + g.y_offset
  local right = left + g.width
  local bottom = top + g.height
  return {x = left, y = top}, {x = right, y = bottom}
end
