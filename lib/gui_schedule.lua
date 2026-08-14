local schedule = {}

schedule.is_due = function(tick, interval)
    return type(tick) == "number" and type(interval) == "number" and interval > 0 and
        tick % interval == 0
end

schedule.refresh_open_players = function(players, is_open, refresh)
    if type(is_open) ~= "function" or type(refresh) ~= "function" then
        return
    end
    for _, p in pairs(players or {}) do
        if p and p.index and is_open(p.index) then
            refresh(p.index, true)
        end
    end
end

return schedule
