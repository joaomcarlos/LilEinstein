local log = {}

log.DEBUG = false

local prefix = "[font=default-bold][LilEinstein][/font] "
local warning_prefix = "[font=default-bold][LilEinstein] [color=orange]Warning[/color][/font]: "
local error_prefix = "[font=default-bold][LilEinstein] [color=red]Error[/color][/font]: "
local debug_prefix = "[font=default-bold][LilEinstein] [color=blue]Debug[/color][/font]: "

local print_message = function(target, message)
    if target and target.print then
        target.print(message)
        return
    end
    game.print(message)
end

local build_message = function(head, message)
    return {"", head, message}
end

---@param target LuaGameScript|LuaForce|LuaPlayer|nil
---@param message LocalisedString|string
log.log = function(target, message)
    print_message(target, build_message(prefix, message))
end

log.print = log.log

---@param target LuaGameScript|LuaForce|LuaPlayer|nil
---@param message LocalisedString|string
log.warn = function(target, message)
    print_message(target, build_message(warning_prefix, message))
end

---@param target LuaGameScript|LuaForce|LuaPlayer|nil
---@param message LocalisedString|string
log.error = function(target, message)
    print_message(target, build_message(error_prefix, message))
end

---@param target LuaGameScript|LuaForce|LuaPlayer|nil
---@param message LocalisedString|string
log.debug = function(target, message)
    if not log.DEBUG then
        return
    end
    print_message(target, build_message(debug_prefix, message))
end

return log
