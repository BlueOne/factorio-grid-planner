
-- Map
------------------------------------------------------------------------------
---
local blend_mode = "normal"
local filename = "__zone-planner__/graphics/base/empty-square.png"
for x = 0, 2 do
    data:extend{{
        type = "sprite",
        name = "zp-empty-square-" .. x,
        filename = filename,
        size = 512,
        x = x * 512,
        blend_mode = blend_mode
    }}
end

local filename = "__zone-planner__/graphics/base/corners.png"
for x = 0, 2 do
    for y = 0, 3 do
        data:extend{{
            type = "sprite",
            name = ("zp-corner-%d-%d"):format(x, y),
            filename = filename,
            size = 256,
            x = x * 256,
            y = y * 256,
            blend_mode = blend_mode
        }}
    end
end


-- Icons
------------------------------------------------------------------------------

local function add_icon_row(name, suffix, y, filename, icon_size)
    local variations = {
        {name = name .. "-dark", x = 0},
        {name = name .. "-mid", x = icon_size},
        {name = name .. "-light", x = 2 * icon_size},
    }
    for _, variation in pairs(variations) do
        data:extend{{
            type = "sprite",
            name = variation.name .. suffix,
            filename = filename,
            size = icon_size,
            x = variation.x,
            y = y * icon_size,
        }}
    end
end

-- example "zp-up-dark-16", "zp-up-mid-16", "zp-up-light-16", "zp-up-dark-64", etc
local names = {"up", "down", "right", "left", "visibility", "edit"}
local resolutions = {16, 32, 64}
for _, resolution in pairs(resolutions) do
    for i, name in pairs(names) do
        add_icon_row("zp-" .. name, "-" .. resolution, i - 1, "__zone-planner__/graphics/icons/icons-" .. resolution .. ".png", resolution)
    end
end


-- UI icons for undo/redo (24px base, suitable for 28px buttons)
data:extend({
    {
        type = "sprite",
        name = "zp-undo-icon",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/undo-x24.png",
        size = 24,
        flags = {"gui-icon"},
    },
    {
        type = "sprite",
        name = "zp-undo-icon-light",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/undo-x24.png",
        invert_colors = true,
        size = 24,
        flags = {"gui-icon"},
    },
    {
        type = "sprite",
        name = "zp-redo-icon",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/redo-x24.png",
        size = 24,
        flags = {"gui-icon"},
    },
    {
        type = "sprite",
        name = "zp-redo-icon-light",
        filename = "__base__/graphics/icons/shortcut-toolbar/mip/redo-x24.png",
        invert_colors = true,
        size = 24,
        flags = {"gui-icon"},
    },
    {
        type = "sprite",
        name = "zp-mod-icon",
        filename = "__zone-planner__/graphics/icons/mod-icon.png",
        size = 64,
        flags = {"gui-icon"},
    }
})
