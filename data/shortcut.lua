data:extend({ -- keybindings
{
    type = "custom-input",
    name = "lil_einstein_toggle_gui",
    key_sequence = "",
    linked_game_control = "open-technology-gui",
    consuming = "game-only"
}, {
    type = "custom-input",
    name = "lil_einstein_toggle_menu",
    key_sequence = "",
    linked_game_control = "toggle-menu",
    consuming = "none"
}, {
    type = "custom-input",
    name = "lil_einstein_focus_search",
    key_sequence = "",
    linked_game_control = "focus-search"
}, -- Shortcut buttons
{
    type = "shortcut",
    name = "lil_einstein_shortcut",
    action = "lua",
    icon = "__LilEinstein__/graphics/icons/shortcut-button.png",
    icon_size = 64,
    small_icon = "__LilEinstein__/graphics/icons/shortcut-button.png",
    small_icon_size = 64
}})
