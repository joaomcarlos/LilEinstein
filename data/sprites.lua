-- Small = 16px, medium = 32px, large = 64px
local p = "__LilEinstein__/graphics/icons/"
local ui = "__LilEinstein__/graphics/ui/"
local ui_slices = require("lib.ui_slices")
local ui_slice_aliases = {
    button_all = "allowed_button_all",
    button_invert = "allowed_button_invert",
    button_none = "allowed_button_none",
    button_produced = "allowed_button_produced",
    checkbox_off = "filter_checkbox_off",
    checkbox_on = "filter_checkbox_on",
    settings_checkbox_on_1 = "settings_checkbox_on_1",
    settings_checkbox_on_2 = "settings_checkbox_on_2",
    drag_handle = "upcoming_drag_handle",
    enable_switch_off = "toggle_off",
    enable_switch_on = "toggle_on",
    radio_off = "filter_radio_off",
    radio_on = "filter_radio_on",
    row_arrow_down = "tech_row_down_button",
    row_arrow_up = "tech_row_up_button",
    row_scrollbar_thumb = "tech_scrollbar_thumb",
    tech_switch_on = "tech_enable_switch"
}

local get_sprite = function(name, w, h, filename)
    local prop = {
        type = "sprite",
        name = "lil_einstein_" .. name,
        filename = p .. (filename or name) .. ".png",
        priority = "extra-high-no-scale",
        width = w,
        height = h
    }
    return prop
end

local get_ui_sprite = function(name, w, h)
    local slice = ui_slices.by_key[ui_slice_aliases[name] or name]
    if not slice then
        return nil
    end

    local prop = {
        type = "sprite",
        name = "lil_einstein_mockup_" .. name,
        filename = slice.file,
        priority = "extra-high-no-scale",
        width = slice.image_w or w,
        height = slice.image_h or h
    }
    return prop
end

local get_research_sprite = function(name, w, h, filename)
    local prop = {
        type = "sprite",
        name = "lil_einstein_" .. name,
        filename = ui .. filename,
        priority = "extra-high-no-scale",
        width = w,
        height = h
    }
    return prop
end

-- Small sprites
data:extend({get_sprite("bin_small", 16, 16), get_sprite("arrow_down_small", 14, 10),
             get_sprite("arrow_down_small_black", 14, 10), get_sprite("arrow_up_small", 14, 10),
             get_sprite("arrow_up_small_black", 14, 10), get_sprite("arrow_left_small", 10, 14),
             get_sprite("arrow_left_small_black", 10, 14), get_sprite("arrow_right_small", 10, 14),
             get_sprite("arrow_right_small_black", 10, 14)})

-- Medium sprites
data:extend({get_sprite("queue_medium", 26, 26), get_sprite("blocked_medium", 26, 26),
             get_sprite("progress_medium", 32, 31), get_sprite("inherit_medium", 32, 32),
             get_sprite("no_science_medium", 32, 32), get_sprite("progress_smart_medium", 32, 32)})

-- Large sprites
data:extend({get_sprite("portrait_large", 96, 96, "lil_einstein_portrait_large")})

local ui_sprite_names = {
    "button_all",
    "button_invert",
    "button_none",
    "button_produced",
    "checkbox_off",
    "checkbox_on",
    "settings_checkbox_on_1",
    "settings_checkbox_on_2",
    "drag_handle",
    "enable_switch_off",
    "enable_switch_on",
    "filter_search_button",
    "number_input_bg",
    "radio_off",
    "radio_on",
    "row_arrow_down",
    "row_arrow_up",
    "row_scrollbar_thumb",
    "science_slot_bg",
    "stepper_left",
    "stepper_right",
    "tech_row_bg",
    "tech_search_button",
    "upcoming_row_separator",
    "tech_switch_on",
    "upcoming_row_bg"
}

local ui_sprites = {}
for _, name in ipairs(ui_sprite_names) do
    local sprite = get_ui_sprite(name)
    if sprite then
        table.insert(ui_sprites, sprite)
    end
end
data:extend(ui_sprites)

data:extend({
    get_research_sprite("research_bottle_fill_00", 179, 142, "research-bottle-fill-00.png"),
    get_research_sprite("research_bottle_fill_02", 179, 142, "research-bottle-fill-02.png"),
    get_research_sprite("research_bottle_fill_05", 179, 142, "research-bottle-fill-05.png"),
    get_research_sprite("research_bottle_fill_10", 179, 142, "research-bottle-fill-10.png"),
    get_research_sprite("research_bottle_fill_15", 179, 142, "research-bottle-fill-15.png"),
    get_research_sprite("research_bottle_fill_20", 179, 142, "research-bottle-fill-20.png"),
    get_research_sprite("research_bottle_fill_30", 179, 142, "research-bottle-fill-30.png"),
    get_research_sprite("research_bottle_fill_40", 179, 142, "research-bottle-fill-40.png"),
    get_research_sprite("research_bottle_fill_50", 179, 142, "research-bottle-fill-50.png"),
    get_research_sprite("research_bottle_fill_70", 179, 142, "research-bottle-fill-70.png"),
    get_research_sprite("research_bottle_fill_80", 179, 142, "research-bottle-fill-80.png"),
    get_research_sprite("research_bottle_fill_90", 179, 142, "research-bottle-fill-90.png"),
    get_research_sprite("research_bottle_fill_95", 179, 142, "research-bottle-fill-95.png"),
    get_research_sprite("research_bottle_fill_99", 179, 142, "research-bottle-fill-99.png")
})
