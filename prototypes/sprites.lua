local empty_square_levels = {40, 25, 10}

for _, alpha in pairs(empty_square_levels) do
    data:extend{{
        type = "sprite",
        name = "zp-empty-square-" .. alpha,
        filename = "__zone-planner__/graphics/base/center/empty-square-" .. alpha .. ".png",
        size = 512,
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
    },
    {
        type = "sprite",
        name = "zp_visibility_icon",
        filename = "__zone-planner__/graphics/icons/eye_icon.png",
        size = 64,
        flags = {"gui-icon"},
    }
})