package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local coverage = require("tests.coverage")
coverage.start()

local specs = {
    "tests.util_spec",
    "tests.queue_spec",
    "tests.queue_core_spec",
    "tests.queue_diagnostic_spec",
    "tests.queue_submodule_spec",
    "tests.upcoming_component_spec",
    "tests.tech_component_spec",
    "tests.queue_component_spec",
    "tests.components_facade_spec",
    "tests.components_behavior_spec",
    "tests.env_tech_spec",
    "tests.env_edges_spec",
    "tests.cmd_spec",
    "tests.state_spec",
    "tests.policy_spec",
    "tests.policy_edges_spec",
    "tests.lab_spec",
    "tests.gutil_spec",
    "tests.gutil_deep_spec",
    "tests.analyzer_spec",
    "tests.debug_report_spec",
    "tests.builder_spec",
    "tests.gui_spec",
    "tests.component_guard_spec",
    "tests.foundation_spec",
    "tests.data_migration_spec",
    "tests.translate_spec",
    "tests.locale_spec",
    "tests.control_spec"
}

local total = 0
for _, name in ipairs(specs) do
    local ok, result = pcall(require, name)
    if not ok then
        error("test suite failed: " .. name .. ": " .. tostring(result), 0)
    end
    if type(result) == "number" then
        total = total + result
    end
end

print("run_all: " .. tostring(total) .. " tests passed")
coverage.stop()
coverage.write("coverage-unit-lines.tsv")
