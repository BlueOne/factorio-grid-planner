-- Renderer for Zone Planner
-- Draws per-cell overlays using Factorio rendering API, tinted by zone color.

local render = {}

local backend = require("scripts/backend")

---@class ZP.RenderStorageRoot
---@field forces table<uint, ZP.RenderForceState>  -- by force_index

---@class ZP.RenderCell
---@field edges table<uint, {game: LuaRenderObject|nil, chart: LuaRenderObject|nil}>|nil
---@field corners table<uint, {game: LuaRenderObject|nil, chart: LuaRenderObject|nil}>|nil
---@field borders table<uint, LuaRenderObject|nil>|nil
---@field zone_id uint|nil

---@class ZP.RenderPlayerSurfaceState
---@field cells table<string, ZP.RenderCell>

---@class ZP.RenderForceState
---@field surfaces table<uint, table<uint, ZP.RenderPlayerSurfaceState>>  -- surface_index -> player_index -> state

local function ensure_state()
  storage.zp_render = storage.zp_render or { forces = {} }
  return storage.zp_render
end

local function ensure_force_state(force_index)
  local s = ensure_state()
  local f = s.forces[force_index]
  if not f then
    f = { surfaces = {} }
    s.forces[force_index] = f
  end
  return f
end

local function ensure_surface_state(force_index, surface_index)
  local f = ensure_force_state(force_index)
  local surf = f.surfaces[surface_index]
  if not surf then
    surf = {}
    f.surfaces[surface_index] = surf
  end
  return surf
end

local function ensure_player_surface_state(force_index, surface_index, player_index)
  local surf = ensure_surface_state(force_index, surface_index)
  local ps = surf[player_index]
  if not ps then
    ps = { cells = {} }
    surf[player_index] = ps
  end
  return ps
end

local function parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

local function cell_bounds(g, cx, cy)
  local left = cx * g.width + g.x_offset
  local top = cy * g.height + g.y_offset
  local right = left + g.width
  local bottom = top + g.height
  return {x = left, y = top}, {x = right, y = bottom}
end

-- Note: zone_color_with_alpha was unused; removed for clarity.


local function destroy_cell_render(cell)
  if not cell then return end
  if cell.center then
    if cell.center.game and cell.center.game.valid then cell.center.game.destroy() end
    if cell.center.chart and cell.center.chart.valid then cell.center.chart.destroy() end
  end
  if cell.edges then
    for _, e in pairs(cell.edges) do
      if e.game and e.game.valid then e.game.destroy() end
      if e.chart and e.chart.valid then e.chart.destroy() end
    end
  end
  if cell.corners then
    for _, c in pairs(cell.corners) do
      if c.game and c.game.valid then c.game.destroy() end
      if c.chart and c.chart.valid then c.chart.destroy() end
    end
  end
  if cell.borders then
    for _, b in pairs(cell.borders) do
      if b and b.valid then b.destroy() end
    end
  end
end

local function draw_cell_for_player(force_index, surface_index, player_index, key, zone_id, opacity_index)
  -- Draw a richer set of overlays (center, edges, corners, borders) plus a base tint rectangle
  local ps = ensure_player_surface_state(force_index, surface_index, player_index)
  local cell = ps.cells[key]
  if cell then
    destroy_cell_render(cell)
  end

  local surface = game.get_surface(surface_index) --[[@as LuaSurface]]
  local g = backend.get_grid(force_index)
  local zones = storage.zp.forces[force_index].zones
  local zone = zone_id and zones[zone_id] or nil
  local cx, cy = parse_cell_key(key)
  local lt, rb = cell_bounds(g, cx, cy)
  local center_pos = { x = (lt.x + rb.x) / 2, y = (lt.y + rb.y) / 2 }

  if not zone then
    ps.cells[key] = nil
    return
  end

  local player = game.get_player(player_index)
  local color = zone.color

  -- Determine boundary variant index 0..3 (0=invisible)
  local idx = math.max(0, math.min(3, opacity_index or 0))
  local TAGS = { [1] = "a40_15", [2] = "a20_075", [3] = "a10_25" }
  local tag = TAGS[idx]

  -- Variant based on parity to reduce repetition
  local variant = ((cx + cy) % 2 == 0) and 0 or 1

  local function draw_floor(player, sprite, target_pos, tint, orientation, x_scale, y_scale)
    return rendering.draw_sprite{
      sprite = sprite,
      surface = surface,
      tint = tint,
      target = target_pos,
      orientation = orientation,
      players = { player },
      render_layer = "floor",
      only_in_alt_mode = true,
      visible = true,
      x_scale = x_scale or 1.0,
      y_scale = y_scale or 1.0,
    }
  end

  local function draw_chart(player, sprite, target_pos, tint, orientation, x_scale, y_scale)
    return rendering.draw_sprite{
      sprite = sprite,
      surface = surface,
      tint = tint,
      target = target_pos,
      orientation = orientation,
      players = { player },
      only_in_alt_mode = true,
      render_mode = "chart",
      x_scale = x_scale or 1.0,
      y_scale = y_scale or 1.0,
    }
  end

  -- local center_sprite = (idx > 0 and ("gl-center-" .. tag .. "-" .. tostring(variant))) or ("gl-center-" .. tostring(variant))
  -- local center = {
  --   game = draw_floor(player, center_sprite, center_pos, color, 0),
  --   chart = draw_chart(player, center_sprite, center_pos, color, 0),
  -- }

  -- Helper to fetch neighbor zone_id
  local images = storage.zp.forces[force_index].images
  local img = images[surface_index]
  local function neighbor_zone(dx, dy)
    local nk = tostring(cx + dx) .. ":" .. tostring(cy + dy)
    return img and img.cells and img.cells[nk] or nil
  end

  -- Edge positions and orientations: top, right, bottom, left (1..4)
  local edges = {}
  local borders = {}
  do
    local inner_x = g.width / 2 - 3
    local inner_y = g.height / 2 - 3
    local function draw_edge(side_index, nz, n_same, orient_floor)
      local sprite
      if idx == 0 then
        sprite = nil
      else
        -- For edges between two cells of the same zone, draw a full 20x12 rect using the corner/1.png sprite.
        -- For edges between different zones, keep the existing edge behavior.
        sprite = n_same and ("gl-corner-" .. tag .. "-1") or ("gl-edge-" .. tag .. "-2")
      end
      local dx_floor, dy_floor
      if side_index == 1 then -- top
        dx_floor, dy_floor = 0, -inner_y
      elseif side_index == 2 then -- right
        dx_floor, dy_floor = inner_x, 0
      elseif side_index == 3 then -- bottom
        dx_floor, dy_floor = 0, inner_y
      else -- left
        dx_floor, dy_floor = -inner_x, 0
      end
      local pos_floor = { x = center_pos.x + dx_floor, y = center_pos.y + dy_floor }
      local pos_chart = pos_floor
      local orient_chart = orient_floor
      local x_scale = 1.0
      local y_scale = 1.0
      if n_same then x_scale = 40 / 12 end
      if sprite then
        edges[side_index] = {
          game = draw_floor(player, sprite, pos_floor, color, orient_floor, x_scale, y_scale),
          chart = draw_chart(player, sprite, pos_chart, color, orient_chart, x_scale, y_scale),
        }
      end
    end
    -- top edge
    local nz = neighbor_zone(0, -1)
    local n_same = nz == zone_id
    draw_edge(1, nz, n_same, 0.0)
    -- right edge
    nz = neighbor_zone(1, 0)
    n_same = nz == zone_id
    draw_edge(2, nz, n_same, 0.25)
    -- bottom edge
    nz = neighbor_zone(0, 1)
    n_same = nz == zone_id
    draw_edge(3, nz, n_same, 0.5)
    -- left edge
    nz = neighbor_zone(-1, 0)
    n_same = nz == zone_id
    draw_edge(4, nz, n_same, 0.75)
  end

  -- Corners based on adjacency: TL, TR, BR, BL as indices 1..4
  local corners = {}
  do
    local function corner_sprite(idx, left_neighbor, right_neighbor, diagonal_neighbor)
      -- If all four adjacent cells (the 2x2 block around this corner) are in the same zone,
      -- draw a 12x12 full rect using corner/1.png; otherwise keep current mapping.
      if left_neighbor and right_neighbor and diagonal_neighbor then
        return "gl-corner-1"
      end
      if left_neighbor then
        if right_neighbor then
          return "gl-corner-2" -- inside corner (one or more different among the 2x2)
        else
          return "gl-corner-3" -- straight right
        end
      else
        if right_neighbor then
          return "gl-corner-4" -- straight left
        else
          return "gl-corner-5" -- outside corner
        end
      end
    end

    -- Top-left (1)
    local inner_x = g.width / 2 - 3
    local inner_y = g.height / 2 - 3
  local pos_floor = { x = center_pos.x - inner_x, y = center_pos.y - inner_y }
  local pos_chart = pos_floor
    local left = neighbor_zone(-1, 0) == zone_id
    local right = neighbor_zone(0, -1) == zone_id
    local diag = neighbor_zone(-1, -1) == zone_id
    local sprite = corner_sprite(1, left, right, diag)
    if idx ~= 0 then
      local base_corner = sprite:match("gl%-corner%-(.+)") or sprite
      corners[1] = {
        game = draw_floor(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_floor, color, 1.0),
        chart = draw_chart(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_chart, color, 1.0),
      }
    end
    -- Top-right (2)
    pos_floor = { x = center_pos.x + inner_x, y = center_pos.y - inner_y }
    pos_chart = pos_floor
    left = neighbor_zone(0, -1) == zone_id
    right = neighbor_zone(1, 0) == zone_id
    diag = neighbor_zone(1, -1) == zone_id
    sprite = corner_sprite(2, left, right, diag)
    if idx ~= 0 then
      local base_corner = sprite:match("gl%-corner%-(.+)") or sprite
      corners[2] = {
        game = draw_floor(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_floor, color, 0.25),
        chart = draw_chart(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_chart, color, 0.25),
      }
    end
    -- Bottom-right (3)
    pos_floor = { x = center_pos.x + inner_x, y = center_pos.y + inner_y }
    pos_chart = pos_floor
    left = neighbor_zone(1, 0) == zone_id
    right = neighbor_zone(0, 1) == zone_id
    diag = neighbor_zone(1, 1) == zone_id
    sprite = corner_sprite(3, left, right, diag)
    if idx ~= 0 then
      local base_corner = sprite:match("gl%-corner%-(.+)") or sprite
      corners[3] = {
        game = draw_floor(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_floor, color, 0.5),
        chart = draw_chart(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_chart, color, 0.5),
      }
    end
    -- Bottom-left (4)
    pos_floor = { x = center_pos.x - inner_x, y = center_pos.y + inner_y }
    pos_chart = pos_floor
    left = neighbor_zone(0, 1) == zone_id
    right = neighbor_zone(-1, 0) == zone_id
    diag = neighbor_zone(-1, 1) == zone_id
    sprite = corner_sprite(4, left, right, diag)
    if idx ~= 0 then
      local base_corner = sprite:match("gl%-corner%-(.+)") or sprite
      corners[4] = {
        game = draw_floor(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_floor, color, 0.75),
        chart = draw_chart(player, "gl-corner-" .. tag .. "-" .. base_corner, pos_chart, color, 0.75),
      }
    end
  end

  ps.cells[key] = {
    zone_id = zone_id,
    edges = edges,
    corners = corners,
    borders = borders,
  }
end

local function rebuild_surface(force_index, surface_index)
  local surf = ensure_surface_state(force_index, surface_index)
  for player_index, ps in pairs(surf) do
    for key, cell in pairs(ps.cells) do
      destroy_cell_render(cell)
      ps.cells[key] = nil
    end
  end

  local f = storage.zp.forces[force_index]
  if not f then return end
  local img = f.images[surface_index]
  
  for key, zone_id in pairs(img.cells or {}) do
    if zone_id then
      local force = game.forces[force_index]
      if not force then return end
      for _, player in pairs(force.players) do
        local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player.index) or 0
        if (idx or 0) > 0 then
          draw_cell_for_player(force_index, surface_index, player.index, key, zone_id, idx)
        end
      end
    end
  end
end

---Notify renderer that a set of cells changed for a surface.
---@param force_index uint
---@param surface_index uint
---@param changed table<string, boolean>|nil  -- set of cell keys affected; nil implies unknown/many
---@param new_zone_id uint|nil               -- new zone id if uniform, or nil for eraser/mixed
function render.on_cells_changed(force_index, surface_index, changed, new_zone_id)
  if not storage or not storage.zp then return end
  if not changed then
    -- Full refresh (e.g., zone delete remap or reproject)
    rebuild_surface(force_index, surface_index)
    return
  end
  local f = storage.zp.forces[force_index]
  local img = f and f.images and f.images[surface_index]

  for key, _ in pairs(changed) do
    local zone_id = img.cells[key]
    local force = game.forces[force_index]
    if not force then return end
    for _, player in pairs(force.players) do
      local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player.index) or 0
      if (idx or 0) > 0 then
        draw_cell_for_player(force_index, surface_index, player.index, key, zone_id, idx)
        -- Also redraw neighbors to update edge/corner transitions
        local cx, cy = parse_cell_key(key)
        local function redraw_neighbor(dx, dy)
          local nk = tostring(cx + dx) .. ":" .. tostring(cy + dy)
          local nz = img.cells[nk]
          if nz ~= nil then
            draw_cell_for_player(force_index, surface_index, player.index, nk, nz, idx)
          else
            -- ensure removal if previously drawn
            local ps = ensure_player_surface_state(force_index, surface_index, player.index)
            local existing = ps.cells[nk]
            if existing then
              destroy_cell_render(existing)
              ps.cells[nk] = nil
            end
          end
        end
        redraw_neighbor(0, -1)
        redraw_neighbor(1, 0)
        redraw_neighbor(0, 1)
        redraw_neighbor(-1, 0)
        redraw_neighbor(-1, -1)
        redraw_neighbor(1, -1)
        redraw_neighbor(1, 1)
        redraw_neighbor(-1, 1)
      else
        -- ensure removal if previously drawn
        local ps = ensure_player_surface_state(force_index, surface_index, player.index)
        local existing = ps.cells[key]
        if existing then
          destroy_cell_render(existing)
          ps.cells[key] = nil
        end
      end
    end
  end
end

---Notify renderer that zone definitions changed for a force.
---@param force_index uint
function render.on_zones_changed(force_index)
  -- Update colors for all existing cells for all players
  local fstate = ensure_force_state(force_index)
  local zones = storage.zp.forces[force_index] and storage.zp.forces[force_index].zones or {}
  for surface_index, surf in pairs(fstate.surfaces) do
    for player_index, ps in pairs(surf) do
      for key, cell in pairs(ps.cells) do
        local zone = cell.zone_id and zones[cell.zone_id]
        if zone then
      local color = zone.color
          if cell.center then
            if cell.center.game and cell.center.game.valid then cell.center.game.color = color end
            if cell.center.chart and cell.center.chart.valid then cell.center.chart.color = color end
          end
          if cell.edges then
            for _, e in pairs(cell.edges) do
              if e.game and e.game.valid then e.game.color = color end
              if e.chart and e.chart.valid then e.chart.color = color end
            end
          end
          if cell.corners then
            for _, c in pairs(cell.corners) do
              if c.game and c.game.valid then c.game.color = color end
              if c.chart and c.chart.valid then c.chart.color = color end
            end
          end
          if cell.borders then
            for _, b in pairs(cell.borders) do
              if b and b.valid then b.color = color end
            end
          end
        end
      end
    end
  end
end

---Notify renderer that grid properties changed (may imply reprojection/full redraw).
---@param force_index uint
function render.on_grid_changed(force_index)
  -- Grid size/offset or visibility/opacity changes: rebuild all surfaces
  local f = storage.zp.forces[force_index]
  if not f then return end
  for surface_index in pairs(f.images) do
    rebuild_surface(force_index, surface_index)
  end
end

---Per-player visibility flags changed.
---@param player_index uint
function render.on_player_visibility_changed(player_index)
  if not storage or not storage.zp then return end
  local player = game.get_player(player_index)
  if not player then return end
  local force_index = player.force.index
  -- Iterate all backend image cells; draw/remove per current alpha
  local force_state = storage.zp.forces[force_index]
  if not force_state then return end
  for surface_index, image in pairs(force_state.images) do
    local ps = ensure_player_surface_state(force_index, surface_index, player_index)
    local cells = image and image.cells or {}
  local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player_index) or 0
    -- Debug: removed unused counter block
    if (idx or 0) > 0 then
      for key, zone_id in pairs(cells) do
        if zone_id then
          draw_cell_for_player(force_index, surface_index, player_index, key, zone_id, idx)
        end
      end
    else
      -- alpha is zero: remove any existing renders for this player
      for key, cell in pairs(ps.cells) do
        destroy_cell_render(cell)
        ps.cells[key] = nil
      end
    end
  end
end

return render
