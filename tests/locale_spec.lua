package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local status_keys = {
    "unknown-research",
    "pack-bound",
    "pack-bound-tooltip",
    "missing-pack",
    "missing-pack-tooltip",
    "operational-fault",
    "operational-fault-tooltip",
    "temporary",
    "temporary-tooltip",
    "switch-ready",
    "switch-ready-tooltip",
    "science-risk",
    "science-risk-tooltip",
    "progress",
    "progress-tooltip",
    "idle",
    "idle-tooltip"
}

local locales = {
    "locale/en/en.cfg",
    "locale/de/de.cfg",
    "locale/fr/fr.cfg",
    "locale/pt-PT/pt-PT.cfg"
}

local read_file = function(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*a")
    file:close()
    return content
end

local tests = {}
for _, path in ipairs(locales) do
    table.insert(tests, {"defines every research status key in " .. path, function()
        local content = read_file(path)
        for _, key in ipairs(status_keys) do
            t.assert_true(string.find(content, "\n" .. key .. "=", 1, true) ~= nil or
                          content:sub(1, #key + 1) == key .. "=",
                          path .. " is missing " .. key)
        end
    end})
end

return t.run("locale_spec", tests)
