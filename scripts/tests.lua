
local ui_ok, ui = pcall(require, "ui"); if not ui_ok then ui = nil end
local r_ok, renderer = pcall(require, "render"); if not r_ok then renderer = nil end

local M = {}

local function now()
  return (game and game.tick) or 0
end

local function log_reset()
  helpers.write_file("grid_planner_tests.log", ("[START %d]%s"):format(now(), "\n"), false)
end

local function log(msg)
  helpers.write_file("grid_planner_tests.log", msg .. "\n", true)
end

local function any_player()
  for _, p in pairs(game.players) do return p end
  return nil
end

local function ctx()
  local p = any_player()
  local force_index = p and p.force.index or game.forces["player"].index
  local surface_index = p and p.surface.index or game.surfaces[1].index
  ---@class ZP.TestCtx
  ---@field player_index uint
  ---@field force_index uint
  ---@field surface_index uint
  local c = { player_index = p and p.index or 1, force_index = force_index, surface_index = surface_index }
  return c
end

local function reset_backend()
  backend.reset_all()
end

-- Return the active layer for a test context.
local function active_layer(c)
  return backend.get_active_layer(c.player_index, c.force_index, c.surface_index)
end

-- Capture and stub notifications --------------------------------------------
local function with_captured_notifications(fn)
  local calls = { cells = {}, regions = {}, grid = {}, ui = {} }
  local ui_orig, rc_orig = {}, {}
  if ui then ui_orig.on_backend_changed = ui.on_backend_changed end
  if renderer then
    rc_orig.cells = renderer.on_cells_changed
    rc_orig.regions = renderer.on_regions_changed
    rc_orig.grid = renderer.on_grid_changed
  end

  if ui then
    ui.on_backend_changed = function(change) ---@diagnostic disable-line: duplicate-set-field
      table.insert(calls.ui, change)
    end
  end
  if renderer then
    renderer.on_cells_changed = function(force_index, surface_index, layer_id, changed_set) ---@diagnostic disable-line: duplicate-set-field
      table.insert(calls.cells, { force_index = force_index, surface_index = surface_index, layer_id = layer_id, changed = changed_set })
    end
    renderer.on_regions_changed = function(force_index) ---@diagnostic disable-line: duplicate-set-field
      table.insert(calls.regions, { force_index = force_index })
    end
    renderer.on_grid_changed = function(force_index) ---@diagnostic disable-line: duplicate-set-field
      table.insert(calls.grid, { force_index = force_index })
    end
  end

  local ok, err = pcall(fn, calls)

  -- restore
  if ui then ui.on_backend_changed = ui_orig.on_backend_changed end ---@diagnostic disable-line: duplicate-set-field
  if renderer then
    renderer.on_cells_changed = rc_orig.cells
    renderer.on_regions_changed = rc_orig.regions
    renderer.on_grid_changed = rc_orig.grid
  end

  if not ok then error(err) end
  return calls
end

-- Assertions -----------------------------------------------------------------
local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. (": expected %s, got %s"):format(tostring(b), tostring(a))) end
end

local function assert_true(cond, msg)
  if not cond then error(msg or "assert_true failed") end
end

-- Helpers --------------------------------------------------------------------
local function cell_key(cx, cy)
  return tostring(cx) .. ":" .. tostring(cy)
end

-- Access layer cells via backend's stored storage state.
local function get_cells(force_index, surface_index, layer_id)
  if not storage or not storage.gp or not storage.gp.forces then return {} end
  local f = storage.gp.forces[force_index]
  if not f or not f.surfaces then return {} end
  local surf = f.surfaces[surface_index]
  if not surf or not surf.layers then return {} end
  local layer = surf.layers[layer_id or 1]
  return (layer and layer.cells) or {}
end

-- Tests ----------------------------------------------------------------------

local function test_tile_to_cell()
  reset_backend()
  local c = ctx()
  -- default grid 8x8, 0 offset
  local layer = active_layer(c)
  assert(layer)
  local x1, y1 = backend.tile_to_cell_layer(layer, 0.0, 0.0)
  assert_eq(x1, 0, "tile_to_cell(0,0) x")
  assert_eq(y1, 0, "tile_to_cell(0,0) y")

  local x2, y2 = backend.tile_to_cell_layer(layer, 7.9, 7.9)
  assert_eq(x2, 0)
  assert_eq(y2, 0)

  local x3, y3 = backend.tile_to_cell_layer(layer, 8.0, 0.0)
  assert_eq(x3, 1)
  assert_eq(y3, 0)

  log("test_tile_to_cell PASS")
end

local function test_rectangle_fill_undo_redo()
  reset_backend()
  local c = ctx()
  local region = backend.add_region(c.force_index, c.player_index, "Z1", {r=1,g=0,b=0,a=1})
  local layer_id = active_layer(c).id

  local lt = {x=0,y=0}; local rb = {x=15,y=7} -- 2x1 cells: (0,0) and (1,0) with 8x8 grid
  local calls = with_captured_notifications(function(_)
    backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, region.id, lt, rb)
  end)

  local cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(0,0)], region.id)
  assert_eq(cells[cell_key(1,0)], region.id)

  assert_true(#calls.cells >= 1, "renderer.on_cells_changed not called")
  local changed = calls.cells[#calls.cells].changed or {}
  assert_true(changed[cell_key(0,0)] and changed[cell_key(1,0)], "changed_set missing keys")

  -- undo
  local calls2 = with_captured_notifications(function()
    backend.undo(c.player_index)
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_true(cells[cell_key(0,0)] == nil and cells[cell_key(1,0)] == nil, "undo didn't clear cells")
  assert_true(#calls2.cells >= 1, "undo didn't notify cells")

  -- redo
  local calls3 = with_captured_notifications(function()
    backend.redo(c.player_index)
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(0,0)], region.id)
  assert_eq(cells[cell_key(1,0)], region.id)
  assert_true(#calls3.cells >= 1, "redo didn't notify cells")

  log("test_rectangle_fill_undo_redo PASS")
end

local function test_region_delete_remap()
  reset_backend()
  local c = ctx()
  local za = backend.add_region(c.force_index, c.player_index, "A", {r=1,g=1,b=1,a=1})
  local zb = backend.add_region(c.force_index, c.player_index, "B", {r=0,g=0,b=1,a=1})
  local layer_id = active_layer(c).id
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, zb.id, {x=0,y=0}, {x=7,y=7}) -- (0,0)

  local calls = with_captured_notifications(function()
    backend.delete_region(c.force_index, c.player_index, zb.id, za.id)
  end)
  local cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(0,0)], za.id)
  assert_true(#calls.cells >= 1, "region delete should notify cells changed")

  log("test_region_delete_remap PASS")
end

local function test_set_grid_notifications_and_reproject()
  reset_backend()
  local c = ctx()
  local z = backend.add_region(c.force_index, c.player_index, "G", {r=1,g=0.5,b=0,a=1})
  local layer_id = active_layer(c).id

  -- place a cell at (1,1) using 8x8 default grid
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=8,y=8}, {x=15,y=15})
  local cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(1,1)], z.id)

  -- notify on grid change without reproject
  local calls1 = with_captured_notifications(function()
    backend.set_grid(c.force_index, c.surface_index, layer_id, c.player_index, {width=8,height=8,x_offset=0,y_offset=0}, {reproject=false})
  end)
  assert_true(#calls1.grid >= 1, "grid change should notify")

  -- reproject to 4x4: old cell (1,1) at 8x8 = tile [8,16), new 4x4 -> cell (2,2) is top-left
  local calls2 = with_captured_notifications(function()
    backend.set_grid(c.force_index, c.surface_index, layer_id, c.player_index, {width=4,height=4,x_offset=0,y_offset=0}, {reproject=true})
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_true(cells[cell_key(1,1)] == nil)
  assert_eq(cells[cell_key(2,2)], z.id)
  assert_true(#calls2.grid >= 1, "reproject grid should notify grid changed")

  -- undo reproject
  local calls3 = with_captured_notifications(function()
    backend.undo(c.player_index)
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(1,1)], z.id)
  assert_true(#calls3.grid >= 1, "undo reproject should notify grid changed")
  assert_true(#calls3.cells >= 1, "undo reproject should notify cells changed")
  local last_cells = calls3.cells[#calls3.cells]
  assert_true(last_cells ~= nil and last_cells.changed == nil, "undo reproject should send full refresh (nil changed_set)")

  log("test_set_grid_notifications_and_reproject PASS")
end

-- Additional tests -----------------------------------------------------------

local function test_tile_to_cell_offsets_and_negative()
  reset_backend()
  local c = ctx()
  local layer_id = active_layer(c).id
  backend.set_grid(c.force_index, c.surface_index, layer_id, c.player_index, {width=32,height=32,x_offset=16,y_offset=32}, {reproject=false})
  local layer = active_layer(c)
  assert(layer)

  local x0, y0 = backend.tile_to_cell_layer(layer, 16.0, 32.0)
  assert_eq(x0, 0, "offset origin x")
  assert_eq(y0, 0, "offset origin y")

  local xm, ym = backend.tile_to_cell_layer(layer, 15.9, 31.9)
  assert_eq(xm, -1, "negative boundary x")
  assert_eq(ym, -1, "negative boundary y")

  local xn, yn = backend.tile_to_cell_layer(layer, -1.0, -1.0)
  assert_eq(xn, -1, "negative tile x with offset")
  assert_eq(yn, -2, "negative tile y with offset")

  local xp, yp = backend.tile_to_cell_layer(layer, 48.0, 64.0)
  assert_eq(xp, 1, "positive tile x with offset")
  assert_eq(yp, 1, "positive tile y with offset")

  log("test_tile_to_cell_offsets_and_negative PASS")
end

local function test_eraser_behavior_nil_vs_empty()
  reset_backend()
  local c = ctx()
  local z = backend.add_region(c.force_index, c.player_index, "E1", {r=0.8,g=0.2,b=0.2,a=1})
  local layer_id = active_layer(c).id

  -- Fill (0,0)
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=0,y=0}, {x=7,y=7})
  local cells = get_cells(c.force_index, c.surface_index)
  assert_eq(cells[cell_key(0,0)], z.id)

  -- Erase with nil
  local calls_nil = with_captured_notifications(function()
    backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, nil, {x=0,y=0}, {x=7,y=7})
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_true(cells[cell_key(0,0)] == nil, "erase with nil should clear to nil")
  assert_true(#calls_nil.cells >= 1, "erase (nil) should notify")

  -- Fill again and erase with EMPTY_ZONE_ID (0)
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=0,y=0}, {x=7,y=7})
  local calls_empty = with_captured_notifications(function()
    backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, 0, {x=0,y=0}, {x=7,y=7})
  end)
  cells = get_cells(c.force_index, c.surface_index)
  assert_true(cells[cell_key(0,0)] == nil, "erase (EMPTY_ZONE_ID) should clear to nil")
  assert_true(#calls_empty.cells >= 1, "erase (EMPTY_ZONE_ID) should notify")

  log("test_eraser_behavior_nil_vs_empty PASS")
end

local function test_region_ids_unique()
  reset_backend()
  local c = ctx()
  local z1 = select(1, backend.add_region(c.force_index, c.player_index, "Z_A", {r=1,g=0,b=0,a=1}))
  local z2 = select(1, backend.add_region(c.force_index, c.player_index, "Z_B", {r=0,g=1,b=0,a=1}))
  local z3 = select(1, backend.add_region(c.force_index, c.player_index, "Z_C", {r=0,g=0,b=1,a=1}))
  assert_true(z1 and z2 and z3, "regions should be created")
  assert_true(z1.id ~= 0 and z2.id ~= 0 and z3.id ~= 0, "region ids must be non-zero (0 reserved for Empty)")
  assert_true(z1.id ~= z2.id and z2.id ~= z3.id and z1.id ~= z3.id, "region ids must be unique")
  log("test_region_ids_unique PASS")
end

local function test_region_delete_to_empty()
  reset_backend()
  local c = ctx()
  local z = select(1, backend.add_region(c.force_index, c.player_index, "Z_DEL", {r=0.6,g=0.6,b=0.1,a=1}))
  local layer_id = active_layer(c).id
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=0,y=0}, {x=7,y=7})
  local calls = with_captured_notifications(function()
    backend.delete_region(c.force_index, c.player_index, z.id, nil) -- replace with Empty
  end)
  local cells = get_cells(c.force_index, c.surface_index)
  assert_true(cells[cell_key(0,0)] == nil, "delete to Empty should clear to nil")
  assert_true(#calls.cells >= 1, "delete to Empty should notify cells changed")
  log("test_region_delete_to_empty PASS")
end

local function test_undo_redo_descriptions_and_stacks()
  reset_backend()
  local c = ctx()
  local z = select(1, backend.add_region(c.force_index, c.player_index, "Z_U", {r=0.3,g=0.3,b=0.9,a=1}))
  local layer_id = active_layer(c).id

  -- Perform an action
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=0,y=0}, {x=7,y=7})
  local desc_undo = backend.peek_undo_description(c.player_index)
  assert_true(desc_undo ~= nil and desc_undo:match("Fill rectangle"), "undo description should describe last action")

  -- Undo: redo should now have the last action, undo should be empty
  backend.undo(c.player_index)
  local desc_redo = backend.peek_redo_description(c.player_index)
  assert_true(desc_redo ~= nil and desc_redo:match("Fill rectangle"), "redo description should show last undone action")
  assert_true(backend.peek_undo_description(c.player_index) == nil, "undo stack should be empty after undo of single action")

  -- New action clears redo
  backend.fill_rectangle(c.player_index, c.force_index, c.surface_index, layer_id, z.id, {x=8,y=0}, {x=15,y=7})
  assert_true(backend.peek_redo_description(c.player_index) == nil, "redo stack should clear on new action")

  -- Undo then redo restores undo description
  backend.undo(c.player_index)
  backend.redo(c.player_index)
  local desc_undo2 = backend.peek_undo_description(c.player_index)
  assert_true(desc_undo2 ~= nil and desc_undo2:match("Fill rectangle"), "undo description should restore after redo")

  log("test_undo_redo_descriptions_and_stacks PASS")
end

local TESTS = {
  test_tile_to_cell = test_tile_to_cell,
  test_rectangle_fill_undo_redo = test_rectangle_fill_undo_redo,
  test_region_delete_remap = test_region_delete_remap,
  test_set_grid_notifications_and_reproject = test_set_grid_notifications_and_reproject,
  test_tile_to_cell_offsets_and_negative = test_tile_to_cell_offsets_and_negative,
  test_eraser_behavior_nil_vs_empty = test_eraser_behavior_nil_vs_empty,
  test_region_ids_unique = test_region_ids_unique,
  test_region_delete_to_empty = test_region_delete_to_empty,
  test_undo_redo_descriptions_and_stacks = test_undo_redo_descriptions_and_stacks,
}

local function run_one(name)
  local fn = TESTS[name]
  if not fn then error("Unknown test: " .. tostring(name)) end
  local ok, err = pcall(fn)
  if ok then log("[PASS] " .. name) else log("[FAIL] " .. name .. ": " .. tostring(err)) end
  return ok
end

local function run_all()
  log_reset()
  local pass, total = 0, 0
  for name in pairs(TESTS) do
    total = total + 1
    if run_one(name) then pass = pass + 1 end
  end
  local summary = ("Tests: %d, Passed: %d, Failed: %d"):format(total, pass, total - pass)
  log(summary)
  game.print("grid_planner_tests: " .. summary)
end

remote.add_interface("grid_planner_tests", {
  run_all = run_all,
  run = function(name)
    log_reset()
    local ok = run_one(name)
    local msg = ok and ("PASS: %s"):format(name) or ("FAIL: %s"):format(name)
    game.print("grid_planner_tests: " .. msg)
  end,
  list = function()
    local names = {}
    for name in pairs(TESTS) do names[#names+1] = name end
    table.sort(names)
    game.print("grid_planner_tests: " .. table.concat(names, ", "))
  end,
})

-- Demo interface to paint a few sample cells for renderer testing
remote.add_interface("region_planner_demo", {
  ---@param force_index uint|nil
  ---@param surface_index uint|nil
  paint_sample = function(force_index, surface_index)
    local c = ctx()
    local f_idx = force_index or c.force_index or 1
    local s_idx = surface_index or c.surface_index or 1

    -- Ensure some regions exist
    local f = storage.gp and storage.gp.forces and storage.gp.forces[f_idx]
    if not f then
      backend.reset_all()
      f = backend.get_force(f_idx)
    end
    local ids = {}
    for id in pairs(f.regions) do
      if id ~= 0 then ids[#ids+1] = id end
    end
    table.sort(ids)
    if #ids < 3 then
      backend.add_region(f_idx, 1, "Demo A", {r=1,g=0.2,b=0.2,a=1})
      backend.add_region(f_idx, 1, "Demo B", {r=0.2,g=1,b=0.2,a=1})
      backend.add_region(f_idx, 1, "Demo C", {r=0.2,g=0.2,b=1,a=1})
      ids = {}
      for id in pairs(storage.gp.forces[f_idx].regions) do if id ~= 0 then ids[#ids+1] = id end end
      table.sort(ids)
    end

    local z1, z2, z3 = ids[1], ids[2], ids[3]
    if not (z1 and z2 and z3) then return end
    local layer = backend.get_active_layer(c.player_index, f_idx, s_idx)
    local W = layer.grid.width
    local H = layer.grid.height
    local lid = layer.id
    local count = 0
    count = count + backend.fill_rectangle(c.player_index, f_idx, s_idx, lid, z1, {x=0,y=0}, {x=W-1,y=H-1})
    count = count + backend.fill_rectangle(c.player_index, f_idx, s_idx, lid, z2, {x=W,y=0}, {x=2*W-1,y=H-1})
    count = count + backend.fill_rectangle(c.player_index, f_idx, s_idx, lid, z3, {x=0,y=H}, {x=W-1,y=2*H-1})
    count = count + backend.fill_rectangle(c.player_index, f_idx, s_idx, lid, z2, {x=W,y=H}, {x=2*W-1,y=2*H-1})

    game.print("region_planner_demo: painted sample cells on surface " .. s_idx .. ", force " .. f_idx .. ", total cells: " .. tostring(count))
  end,
})

return M
