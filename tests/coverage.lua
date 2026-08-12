local coverage = {
    hits = {},
    active = false
}

local function is_production_source(source)
    if type(source) ~= "string" then
        return false
    end
    source = source:gsub("\\", "/")
    return source:find("/lib/", 1, true) ~= nil or
        source:find("/model/", 1, true) ~= nil or
        source:find("/view/", 1, true) ~= nil
end

function coverage.start()
    coverage.hits = {}
    coverage.active = true
    debug.sethook(function(event, line)
        if event ~= "line" then
            return
        end
        local info = debug.getinfo(2, "S")
        local source = info and info.source or nil
        if not is_production_source(source) then
            return
        end
        source = source:gsub("^@", ""):gsub("\\", "/")
        coverage.hits[source] = coverage.hits[source] or {}
        coverage.hits[source][line] = true
    end, "l")
end

function coverage.stop()
    debug.sethook()
    coverage.active = false
end

function coverage.write(path)
    local file = assert(io.open(path, "w"))
    local files = {}
    for source, lines in pairs(coverage.hits) do
        local count = 0
        for _ in pairs(lines) do
            count = count + 1
        end
        table.insert(files, {source = source, count = count})
    end
    table.sort(files, function(left, right) return left.source < right.source end)
    for _, item in ipairs(files) do
        local line_numbers = {}
        for line in pairs(coverage.hits[item.source]) do
            table.insert(line_numbers, line)
        end
        table.sort(line_numbers)
        for _, line in ipairs(line_numbers) do
            file:write(item.source, "\t", tostring(line), "\n")
        end
    end
    file:close()
end

function coverage.get_hits()
    return coverage.hits
end

return coverage
