-- Migrate the old queue style to the new queue style
for _, f in pairs(game.forces) do
    -- Check if we have an old style queue. This migration predates the current
    -- release numbering, so it must also be safe when upgrading a modern save.
    local force_store = storage and storage.forces and storage.forces[f.index]
    local queue_store = force_store and force_store.queue
    if not queue_store or type(queue_store.queue) == "table" then
        goto continue
    end

    -- Migrate each tech to the new style queue
    local migrated_queue = {}
    for _, q in pairs(queue_store) do
        if type(q) == "table" and type(q.technology_name) == "string" then
            table.insert(migrated_queue, q.technology_name)
        end
    end
    queue_store.queue = migrated_queue
    ::continue::
end
