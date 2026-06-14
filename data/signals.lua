local subgroup = nil
if data.raw["item-subgroup"]["virtual-signal"] ~= nil then
    subgroup = "virtual-signal"
end

data:extend({
    {
        type = "virtual-signal",
        name = "lil_einstein-science-alert",
        icon = "__LilEinstein__/graphics/icons/no_science_medium.png",
        icon_size = 32,
        subgroup = subgroup,
        order = "z",
    },
})
