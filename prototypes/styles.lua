local default = data.raw["gui-style"].default

-- 28x28 icon button base
default["gp_icon_button"] = {
  type = "button_style",
  parent = "button",
  width = 28,
  height = 28,
  padding = 0,
  top_padding = 0,
  right_padding = 0,
  bottom_padding = 0,
  left_padding = 0,
}

-- Green confirm icon button (28x28)
default["gp_icon_button_green"] = {
  type = "button_style",
  parent = "green_button",
  width = 28,
  height = 28,
  padding = 0,
}

-- Red delete icon button (28x28)
default["gp_icon_button_red"] = {
  type = "button_style",
  parent = "red_button",
  width = 28,
  height = 28,
  padding = 0,
}

-- Bigger heading label for section headers
default["gp_heading_label"] = {
  type = "label_style",
  parent = "bold_label",
  font = "default-large-bold",
}

-- 28x28 color patch label
default["gp_color_patch_label"] = {
  type = "label_style",
  parent = "label",
  width = 32,
  height = 32,
  horizontal_align = "center",
  vertical_align = "center",
  font = "default-large-bold",
}

-- Zone row button (list item)
default["gp_region_row_button"] = {
  type = "button_style",
  parent = "list_box_item",
  height = 40,
  horizontally_stretchable = "on",
  draw_shadow_under_picture = true,
  icon_horizontal_align = "left",
}

-- Zone row frame (non-interactive, matches list_box_item visuals)
default["gp_region_row_frame"] = {
  type = "frame_style",
  parent = "frame",
  height = 40,
  graphical_set = { position = { 208, 17 }, corner_size = 8 },
  minimal_width = 0,
  horizontal_align = "left",
  top_padding = 4,
  right_padding = 4,
  bottom_padding = 4,
  left_padding = 4,
}
