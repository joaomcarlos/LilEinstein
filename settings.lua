data:extend({
    {
        type = "bool-setting",
        name = "lil_einstein-show-warnings",
        setting_type = "runtime-global",
        default_value = false,
        order = "a"
    },
    {
        type = "bool-setting",
        name = "lil_einstein-notify-switches",
        setting_type = "runtime-global",
        default_value = true,
        order = "b"
    },
    {
        type = "double-setting",
        name = "lil_einstein-warn-every-n-seconds",
        setting_type = "runtime-global",
        default_value = 60,
        minimum_value = 1,
        order = "c"
    }
})
