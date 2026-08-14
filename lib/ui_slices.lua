-- UI image primitives that still exist under graphics/ui.
-- Full-window and full-panel mockup crops were intentionally removed from the
-- asset set, so this module only exposes atomic pieces that can be safely
-- composed with live Factorio GUI elements.
local ui = "__LilEinstein__/graphics/ui/"

local slices = {
    { name = "window-background-clean", key = "window_background_clean", file = ui .. "window-background-clean.png", w = 1672, h = 941, image_w = 1672, image_h = 941 },
    { name = "decision-console-background-clean", key = "decision_console_background", file = ui .. "decision-console-background-clean.png", w = 1672, h = 941, image_w = 1672, image_h = 941 },
    { name = "decision-console-stage-arrow", key = "decision_console_stage_arrow", file = ui .. "decision-console-stage-arrow.png", w = 40, h = 52, image_w = 40, image_h = 52 },
    { name = "decision-console-step-1", key = "decision_console_step_1", file = ui .. "decision-console-step-1.png", w = 39, h = 39, image_w = 39, image_h = 39 },
    { name = "decision-console-step-2", key = "decision_console_step_2", file = ui .. "decision-console-step-2.png", w = 39, h = 39, image_w = 39, image_h = 39 },
    { name = "decision-console-step-3", key = "decision_console_step_3", file = ui .. "decision-console-step-3.png", w = 39, h = 39, image_w = 39, image_h = 39 },
    { name = "allowed-button-all",      key = "allowed_button_all",      file = ui .. "allowed-button-all.png",      w = 55,   h = 27,  image_w = 55,   image_h = 27 },
    { name = "allowed-button-invert",   key = "allowed_button_invert",   file = ui .. "allowed-button-invert.png",   w = 66,   h = 27,  image_w = 66,   image_h = 27 },
    { name = "allowed-button-none",     key = "allowed_button_none",     file = ui .. "allowed-button-none.png",     w = 58,   h = 27,  image_w = 58,   image_h = 27 },
    { name = "allowed-button-produced", key = "allowed_button_produced", file = ui .. "allowed-button-produced.png", w = 75,   h = 27,  image_w = 75,   image_h = 27 },
    { name = "toggle-on",               key = "toggle_on",          file = ui .. "toggle-on.png",          w = 39,   h = 24,  image_w = 39,   image_h = 24 },
    { name = "toggle-off",              key = "toggle_off",         file = ui .. "toggle-off.png",         w = 39,   h = 24,  image_w = 39,   image_h = 24 },
    { name = "filter-checkbox-off",     key = "filter_checkbox_off",     file = ui .. "filter-checkbox-off.png",     w = 17,   h = 17,  image_w = 17,   image_h = 17 },
    { name = "settings-checkbox-on-1",  key = "settings_checkbox_on_1",  file = ui .. "settings-checkbox-on-1.png",  w = 17,   h = 17,  image_w = 17,   image_h = 17 },
    { name = "settings-checkbox-on-2",  key = "settings_checkbox_on_2",  file = ui .. "settings-checkbox-on-2.png",  w = 17,   h = 17,  image_w = 17,   image_h = 17 },
    { name = "filter-radio-off",        key = "filter_radio_off",        file = ui .. "filter-radio-off.png",        w = 18,   h = 18,  image_w = 18,   image_h = 18 },
    { name = "filter-radio-on",         key = "filter_radio_on",         file = ui .. "filter-radio-on.png",         w = 18,   h = 18,  image_w = 18,   image_h = 18 },
    { name = "number-input-bg",         key = "number_input_bg",         file = ui .. "mockup_number_input_bg.png",  w = 45,   h = 26,  image_w = 45,   image_h = 26 },
    { name = "stepper-left",            key = "stepper_left",            file = ui .. "stepper-left.png",            w = 23,   h = 26,  image_w = 23,   image_h = 26 },
    { name = "stepper-right",           key = "stepper_right",           file = ui .. "stepper-right.png",           w = 23,   h = 26,  image_w = 23,   image_h = 26 },
    { name = "tech-row-down-button",    key = "tech_row_down_button",    file = ui .. "tech-row-down-button.png",    w = 33,   h = 26,  image_w = 33,   image_h = 26 },
    { name = "tech-row-up-button",      key = "tech_row_up_button",      file = ui .. "tech-row-up-button.png",      w = 35,   h = 26,  image_w = 35,   image_h = 26 },
    { name = "upcoming-drag-handle",    key = "upcoming_drag_handle",    file = ui .. "upcoming-drag-handle.png",    w = 32,   h = 52,  image_w = 32,   image_h = 52 },
    { name = "upcoming-row-separator",  key = "upcoming_row_separator",  file = ui .. "upcoming-row-separator.png",  w = 525,  h = 74,  image_w = 525,  image_h = 74 }
}

local by_name = {}
local by_key = {}
for _, item in ipairs(slices) do
    by_name[item.name] = item
    by_key[item.key] = item
end

return {
    slices = slices,
    by_name = by_name,
    by_key = by_key
}
