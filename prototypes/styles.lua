local default = data.raw["gui-style"].default

-- 28x28 icon button base
default["zp_icon_button"] = {
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
default["zp_icon_button_green"] = {
  type = "button_style",
  parent = "green_button",
  width = 28,
  height = 28,
  padding = 0,
}

-- Red delete icon button (28x28)
default["zp_icon_button_red"] = {
  type = "button_style",
  parent = "red_button",
  width = 28,
  height = 28,
  padding = 0,
}

-- Bigger heading label for section headers
default["zp_heading_label"] = {
  type = "label_style",
  parent = "bold_label",
  font = "default-large-bold",
}

-- 28x28 color patch label
default["zp_color_patch_label"] = {
  type = "label_style",
  parent = "label",
  width = 28,
  height = 28,
  horizontal_align = "center",
  vertical_align = "center",
  font = "default-large-bold",
}
