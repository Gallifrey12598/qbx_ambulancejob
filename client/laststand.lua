-- client/laststand.lua

-- Client callback invoked by the server when the player uses a first aid kit
-- Must return true/false so the server knows whether to remove the item.
lib.callback.register('hospital:client:UseFirstAid', function()
    -- Basic action blocks
    if LocalPlayer.state.isEscorting then
        lib.notify({ title = locale('error.cant_help_now') or "You cannot do this right now.", type = 'error' })
        return false
    end

    if IsPedGettingIntoAVehicle(cache.ped) then
        lib.notify({ title = locale('error.cant_help_now') or "You cannot do this right now.", type = 'error' })
        return false
    end

    -- Find a nearby player to help
    local player = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0)
    if not player then
        lib.notify({ title = locale('error.no_player') or "No players nearby.", type = 'error' })
        return false
    end

    -- Ask server to start the help flow on that target
    local playerId = GetPlayerServerId(player)
    TriggerServerEvent('hospital:server:UseFirstAid', playerId)

    -- Tell server it's okay to remove one first aid kit
    return true
end)

-- Server queries the target to see if they're eligible to be helped with first aid
lib.callback.register('hospital:client:canHelp', function()
    -- Compatible with qbx_medical exports we added earlier
    local inLastStand = exports.qbx_medical and exports.qbx_medical:getLaststand()
    local timeLeft    = exports.qbx_medical and exports.qbx_medical:getLaststandTime()
    return inLastStand and (timeLeft ~= nil and timeLeft <= 300)
end)

---@param targetId number server id of the patient being helped
RegisterNetEvent('hospital:client:HelpPerson', function(targetId)
    if GetInvokingResource() then return end

    -- Perform revive progress on the helper
    local ok = lib.progressCircle({
        duration     = math.random(30000, 60000),
        position     = 'bottom',
        label        = locale('progress.revive'),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = false, car = false, combat = true, mouse = false },
        anim         = { dict = HealAnimDict or 'mini@cpr@char_a@cpr_str', clip = HealAnim or 'cpr_pumpchest' },
    })

    ClearPedTasks(cache.ped)

    if ok then
        lib.notify({ title = locale('success.revived'), type = 'success' })
        TriggerServerEvent('hospital:server:RevivePlayer', targetId)
    else
        lib.notify({ title = locale('error.canceled'), type = 'error' })
    end
end)
