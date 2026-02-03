

for _, name in pairs{"0", "1"} do
    data:extend{{
        type = "sprite",
        name = "gl-center-" .. name,
        filename = "__zone-planner__/graphics/base/center/" .. name .. ".png",
        size = 64 * 20,
        scale = 0.5,
        -- blend_mode = "multiplicative-with-alpha",
    }}
end

for _, name in pairs{"0-0", "0-1", "1-0", "1-1", "2"} do
    data:extend{{
        type = "sprite",
        name = "gl-edge-" .. name,
        filename = "__zone-planner__/graphics/base/edge/" .. name .. ".png",
        width = 64 * 20,
        height = 64 * 6,
        scale = 0.5,
        -- blend_mode = "multiplicative-with-alpha",
    }}
end

for _, name in pairs{"0", "1", "2", "3", "4", "5"} do
    data:extend{{
        type = "sprite",
        name = "gl-corner-" .. name,
        filename = "__zone-planner__/graphics/base/corner/" .. name .. ".png",
        size = 64 * 6,
        scale = 0.5,
        -- blend_mode = "multiplicative-with-alpha",
    }}
end

data:extend{{
    type = "sprite",
    name = "gl-chart-border",
    filename = "__zone-planner__/graphics/base/chart-border.png",
    height = 64,
    width = 64 * 34,
    scale = 0.5,
    -- blend_mode = "multiplicative-with-alpha",
}}

-- Variant boundary sprite sets (three alpha pairs)
local edge_names = {"0-0", "0-1", "1-0", "1-1", "2"}
local corner_names = {"0", "1", "2", "3", "4", "5"}
local center_names = {"0", "1"}
local tags = {"a40_15", "a20_075", "a10_25"}

for _, tag in pairs(tags) do
    for _, name in pairs(edge_names) do
        data:extend{{
            type = "sprite",
            name = "gl-edge-" .. tag .. "-" .. name,
            filename = "__zone-planner__/graphics/" .. tag .. "/edge/" .. name .. ".png",
            width = 64 * 20,
            height = 64 * 6,
            scale = 0.5,
        }}
    end
    for _, name in pairs(corner_names) do
        data:extend{{
            type = "sprite",
            name = "gl-corner-" .. tag .. "-" .. name,
            filename = "__zone-planner__/graphics/" .. tag .. "/corner/" .. name .. ".png",
            size = 64 * 6,
            scale = 0.5,
        }}
    end
    for _, name in pairs(center_names) do
        data:extend{{
            type = "sprite",
            name = "gl-center-" .. tag .. "-" .. name,
            filename = "__zone-planner__/graphics/" .. tag .. "/center/" .. name .. ".png",
            size = 64 * 20,
            scale = 0.5,
        }}
    end
    data:extend{{
        type = "sprite",
        name = "gl-chart-border-" .. tag,
        filename = "__zone-planner__/graphics/" .. tag .. "/chart-border.png",
        height = 64,
        width = 64 * 34,
        scale = 0.5,
    }}
end

-- UI icons for undo/redo (24px base, suitable for 28px buttons)
data:extend({
    {
        type = "sprite",
        name = "zp_undo_icon",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/undo-x24.png",
        size = 24,
        flags = {"gui-icon"},
    },
    {
        type = "sprite",
        name = "zp_redo_icon",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/redo-x24.png",
        size = 24,
        flags = {"gui-icon"},
    }
})