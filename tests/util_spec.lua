package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local util = require("lib.util")

local old_prototypes = prototypes

local tests = {
    {"recognizes empty and non-empty tables", function()
        t.assert_true(util.table_is_empty(nil))
        t.assert_true(util.table_is_empty({}))
        t.assert_false(util.table_is_empty({value = true}))
    end},
    {"finds values and requires every value", function()
        t.assert_true(util.array_has_value({"a", "b"}, "b"))
        t.assert_false(util.array_has_value({"a", "b"}, "c"))
        t.assert_true(util.array_has_all_values({"a", "b", "c"}, {"c", "a"}))
        t.assert_false(util.array_has_all_values({"a", "b"}, {"a", "c"}))
    end},
    {"fuzzy searches strings and word lists", function()
        t.assert_true(util.fuzzy_search("iron plate", {"Iron plate production"}))
        t.assert_true(util.fuzzy_search({"iron", "plate"}, {"steel", "iron", "plate"}))
        t.assert_false(util.fuzzy_search("iron plate", {"iron"}))
        t.assert_true(util.fuzzy_search("iron plate", {"iron"}, 50))
        t.assert_true(util.fuzzy_search("plate", "Iron plate production"))
        t.assert_false(util.fuzzy_search({}, {"anything"}))
    end},
    {"uses the manual lower map for non-ascii searches", function()
        t.assert_true(util.fuzzy_search("Ä", {"ä"}, 100, true))
    end},
    {"counts array entries and flattens keys", function()
        local keys = util.get_array_keys_flat({first = 1, second = 2})
        t.assert_equal(util.get_array_length({first = 1, second = 2}), 2)
        t.assert_equal(#keys, 2)
        t.assert_has_value(keys, "first")
        t.assert_has_value(keys, "second")
    end},
    {"copies non-empty tables without sharing the top level", function()
        local source = {name = "source", count = 2}
        local copy = util.deepcopy(source)
        t.assert_table_keys(copy, source)
        copy.name = "copy"
        t.assert_equal(source.name, "source")
        t.assert_nil(util.deepcopy(nil))
        t.assert_nil(util.deepcopy({}))
    end},
    {"joins arrays while excluding right-side values", function()
        local left = {"a", "b", "c"}
        local result = util.left_excluding_join(left, {"b"})
        t.assert_equal(#result, 2)
        t.assert_has_value(result, "a")
        t.assert_has_value(result, "c")
        t.assert_equal(#left, 3)
        t.assert_nil(util.left_excluding_join(nil, {"a"}))
        t.assert_equal(#util.left_excluding_join({"a"}, nil), 1)
    end},
    {"drops every matching array value", function()
        local values = {"a", "b", "a", "c"}
        util.array_drop_value(values, "a")
        t.assert_equal(#values, 2)
        t.assert_equal(values[1], "b")
        t.assert_equal(values[2], "c")
        t.assert_nil(util.array_drop_value({}, "none"))
    end},
    {"inserts unique values and appends arrays", function()
        local values = {"a"}
        util.insert_unique(values, "a")
        util.insert_unique(values, "b")
        util.array_append_array(values, {"c", "d"})
        t.assert_equal(#values, 4)
        t.assert_equal(values[4], "d")
    end},
    {"appends only unseen values", function()
        local values = {"a"}
        util.array_append_array_unique(values, {"a", "b", "b", "c"})
        t.assert_equal(#values, 3)
        t.assert_equal(values[1], "a")
        t.assert_equal(values[2], "b")
        t.assert_equal(values[3], "c")
    end},
    {"collects unique science packs accepted by lab prototypes", function()
        prototypes = {
            get_entity_filtered = function()
                return {
                    {lab_inputs = {"automation-science-pack", "logistic-science-pack"}},
                    {lab_inputs = {"logistic-science-pack", "chemical-science-pack"}}
                }
            end
        }
        local sciences = util.get_all_sciences()
        t.assert_equal(#sciences, 3)
        t.assert_has_value(sciences, "automation-science-pack")
        t.assert_has_value(sciences, "chemical-science-pack")
    end}
}

local passed = t.run("util_spec", tests)
prototypes = old_prototypes
return passed
