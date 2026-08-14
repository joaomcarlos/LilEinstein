local test_lab = table.deepcopy(data.raw.lab["lab"])
test_lab.name = "lil-einstein-test-lab"
test_lab.minable = nil
test_lab.fast_replaceable_group = nil
test_lab.energy_source = {type = "void"}
test_lab.energy_usage = "1W"

local function make_test_technology(name, science_pack)
    local technology = table.deepcopy(data.raw.technology["automation"])
    technology.name = name
    technology.localised_name = name
    technology.prerequisites = {}
    technology.effects = {}
    technology.enabled = true
    technology.hidden = false
    technology.unit = {
        count = 100000,
        ingredients = {{science_pack, 1}},
        time = 1
    }
    return technology
end

data:extend({
    test_lab,
    make_test_technology("lil-einstein-test-starved", "automation-science-pack"),
    make_test_technology("lil-einstein-test-supplied", "logistic-science-pack")
})
