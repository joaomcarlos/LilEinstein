local testlib = {}

local function stringify(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function testlib.assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. stringify(expected) ..
            ", got " .. stringify(actual), 2)
    end
end

function testlib.assert_true(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

function testlib.assert_false(value, message)
    if value ~= false then
        error(message or "expected false", 2)
    end
end

function testlib.assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ": got " .. stringify(value), 2)
    end
end

function testlib.assert_has_value(array, value, message)
    for _, item in pairs(array or {}) do
        if item == value then
            return
        end
    end
    error((message or "value not found") .. ": " .. stringify(value), 2)
end

function testlib.assert_table_keys(table_value, expected_keys, message)
    for key, expected in pairs(expected_keys) do
        if table_value[key] ~= expected then
            error((message or "table value differs") .. " at " .. tostring(key) ..
                ": expected " .. stringify(expected) .. ", got " .. stringify(table_value[key]), 2)
        end
    end
end

function testlib.reset_modules(names)
    for _, name in ipairs(names) do
        package.loaded[name] = nil
    end
end

function testlib.install_module(name, value)
    package.preload[name] = function()
        return value
    end
    package.loaded[name] = nil
end

function testlib.run(suite_name, tests)
    local passed = 0
    for _, test in ipairs(tests) do
        local ok, err = pcall(test[2])
        if not ok then
            error(suite_name .. " / " .. test[1] .. " failed: " .. tostring(err), 0)
        end
        passed = passed + 1
    end
    print(suite_name .. ": " .. tostring(passed) .. " passed")
    return passed
end

return testlib
