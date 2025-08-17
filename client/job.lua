local config       = require 'config.client'
local sharedConfig = require 'config.shared'

-- Safe animation fallbacks (used by TreatWounds/Revive flows)
HealAnimDict = HealAnimDict or 'mini@cpr@char_a@cpr_str'
HealAnim     = HealAnim     or 'cpr_pumpchest'

-- Cache the player's job safely
JobCached = (QBX and QBX.PlayerData and QBX.PlayerData.job) or nil

-- Events
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    -- If switching into EMS and turning onduty, clock in
    if job.type == 'ems' and job.onduty then
        TriggerServerEvent('QBCore:Everfall:EMSClockIn')
    -- If we were EMS and are switching out of EMS, clock out
    elseif (QBX and QBX.PlayerData and QBX.PlayerData.job and QBX.PlayerData.job.type == 'ems') and job.type ~= 'ems' then
        TriggerServerEvent('QBCore:Everfall:EMSClockOut')
    end

    JobCached = job
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    local pd = QBX and QBX.PlayerData
    if pd and pd.job and pd.job.type == 'ems' then
        if duty then
            TriggerServerEvent('QBCore:Everfall:EMSClockIn')
        else
            TriggerServerEvent('QBCore:Everfall:EMSClockOut')
        end
    end

    if JobCached then
        JobCached.onduty = duty
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local pd = QBX and QBX.PlayerData
    if pd and pd.job and pd.job.type == 'ems' and pd.job.onduty then
        TriggerServerEvent('QBCore:Everfall:EMSClockIn')
    end
    JobCached = pd and pd.job or nil
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if JobCached and JobCached.type == 'ems' and JobCached.onduty then
        TriggerServerEvent('QBCore:Everfall:EMSClockOut')
    end
    JobCached = nil
end)

---Show patient's treatment menu.
---@param status string[]
local function showTreatmentMenu(status)
    local statusMenu = {}
    for i = 1, #status do
        statusMenu[i] = {
            title = status[i],
            event = 'hospital:client:TreatWounds',
        }
    end

    lib.registerContext({
        id = 'ambulance_status_context_menu',
        title = locale('menu.status'),
        options = statusMenu
    })

    lib.showContext('ambulance_status_context_menu')
end

---Check status of nearest player and show treatment menu.
---Intended to be invoked by client or server.
RegisterNetEvent('hospital:client:CheckStatus', function()
    local player = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0)
    if not player then
        lib.notify({ title = locale('error.no_player'), type = 'error' })
        return
    end

    local playerId = GetPlayerServerId(player)
    local status = lib.callback.await('qbx_ambulancejob:server:getPlayerStatus', false, playerId)
    if not status or not status.injuries then
        lib.notify({ title = locale('error.no_player'), type = 'error' })
        return
    end

    if #status.injuries == 0 then
        lib.notify({ title = locale('success.healthy_player'), type = 'success' })
        return
    end

    --[[ If you have a WEAPONS table with damagereason, you can re-enable this.
    for hash in pairs(status.damageCauses) do
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = false,
            args = { locale('info.status'), WEAPONS[hash].damagereason }
        })
    end
    ]]

    if status.bleedLevel and status.bleedLevel > 0 then
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = false,
            -- If your locale needs a table param, change to: locale('info.is_status', { state = status.bleedState })
            args = { locale('info.status'), locale('info.is_status', status.bleedState) }
        })
    end

    showTreatmentMenu(status.injuries)
end)

---Use first aid on nearest player to revive them.
---Intended to be invoked by client or server.
RegisterNetEvent('hospital:client:RevivePlayer', function()
    local hasFirstAid = (exports.ox_inventory:Search('count', 'firstaid') or 0) > 0
    if not hasFirstAid then
        lib.notify({ title = locale('error.no_firstaid'), type = 'error' })
        return
    end

    local player = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0)
    if not player then
        lib.notify({ title = locale('error.no_player'), type = 'error' })
        return
    end

    local ok = lib.progressCircle({
        duration   = 5000,
        position   = 'bottom',
        label      = locale('progress.revive'),
        useWhileDead = false,
        canCancel  = true,
        disable    = { move = false, car = false, combat = true, mouse = false },
        anim       = { dict = HealAnimDict, clip = HealAnim },
    })

    StopAnimTask(cache.ped, HealAnimDict, 'exit', 1.0)

    if ok then
        lib.notify({ title = locale('success.revived'), type = 'success' })
        TriggerServerEvent('hospital:server:RevivePlayer', GetPlayerServerId(player))
    else
        lib.notify({ title = locale('error.canceled'), type = 'error' })
    end
end)

---Use bandage on nearest player to treat their wounds.
---Intended to be invoked by client or server.
RegisterNetEvent('hospital:client:TreatWounds', function()
    local hasBandage = (exports.ox_inventory:Search('count', 'bandage') or 0) > 0
    if not hasBandage then
        lib.notify({ title = locale('error.no_bandage'), type = 'error' })
        return
    end

    local player = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0)
    if not player then
        lib.notify({ title = locale('error.no_player'), type = 'error' })
        return
    end

    local ok = lib.progressCircle({
        duration   = 5000,
        position   = 'bottom',
        label      = locale('progress.healing'),
        useWhileDead = false,
        canCancel  = true,
        disable    = { move = false, car = false, combat = true, mouse = false },
        anim       = { dict = HealAnimDict, clip = HealAnim },
    })

    StopAnimTask(cache.ped, HealAnimDict, 'exit', 1.0)

    if ok then
        lib.notify({ title = locale('success.helped_player'), type = 'success' })
        TriggerServerEvent('hospital:server:TreatWounds', GetPlayerServerId(player))
    else
        lib.notify({ title = locale('error.canceled'), type = 'error' })
    end
end)

---Opens the hospital armory.
---@param armoryId integer id of armory to open
---@param stashId integer id of armory to open
local function openArmory(armoryId, stashId)
    local pd = QBX and QBX.PlayerData
    if not (pd and pd.job and pd.job.onduty) then return end
    local arm = sharedConfig.locations.armory[armoryId]
    if not arm then return end
    exports.ox_inventory:openInventory('shop', { type = arm.shopType, id = stashId })
end

---Toggles the on duty status of the player.
local function toggleDuty()
    TriggerServerEvent('QBCore:ToggleDuty')
    TriggerServerEvent('police:server:UpdateBlips')
end

---Sets up duty toggle and armory using ox_target or zones.
if config.useTarget then
    CreateThread(function()
        -- Duty points
        for i = 1, #sharedConfig.locations.duty do
            exports.ox_target:addBoxZone({
                name     = 'ems_duty_' .. i,
                coords   = sharedConfig.locations.duty[i],
                size     = vec3(1.5, 1.0, 2.0),
                rotation = 71,
                debug    = config.debugPoly,
                options  = {
                    {
                        icon     = 'fa fa-clipboard',
                        label    = locale('text.duty'),
                        onSelect = toggleDuty,
                        distance = 2.0,
                        groups   = 'ambulance',
                    }
                }
            })
        end

        -- Armory points
        for i = 1, #sharedConfig.locations.armory do
            local arm = sharedConfig.locations.armory[i]
            for ii = 1, #arm.locations do
                exports.ox_target:addBoxZone({
                    name     = ('ems_armory_%d_%d'):format(i, ii),
                    coords   = arm.locations[ii],
                    size     = vec3(1.0, 1.0, 2.0),
                    rotation = -20,
                    debug    = config.debugPoly,
                    options  = {
                        {
                            icon     = 'fa fa-clipboard',
                            label    = locale('text.armory'),
                            onSelect = function() openArmory(i, ii) end,
                            distance = 1.5,
                            groups   = 'ambulance',
                        }
                    }
                })
            end
        end
    end)
else
    CreateThread(function()
        -- Duty points
        for i = 1, #sharedConfig.locations.duty do
            lib.zones.box({
                coords   = sharedConfig.locations.duty[i],
                size     = vec3(1.0, 1.0, 2.0),
                rotation = -20,
                debug    = config.debugPoly,
                onEnter  = function()
                    local pd = QBX and QBX.PlayerData
                    local onduty = pd and pd.job and pd.job.onduty
                    local label = onduty and locale('text.onduty_button') or locale('text.offduty_button')
                    lib.showTextUI(label)
                end,
                onExit   = function() lib.hideTextUI() end,
                inside   = function()
                    if OnKeyPress then
                        OnKeyPress(toggleDuty)
                    else
                        if IsControlJustPressed(0, 38) then toggleDuty() end
                    end
                end,
            })
        end

        -- Armory points
        for i = 1, #sharedConfig.locations.armory do
            local arm = sharedConfig.locations.armory[i]
            for ii = 1, #arm.locations do
                lib.zones.box({
                    coords   = arm.locations[ii],
                    size     = vec3(1.0, 1.0, 2.0),
                    rotation = -20,
                    debug    = config.debugPoly,
                    onEnter  = function()
                        local pd = QBX and QBX.PlayerData
                        if pd and pd.job and pd.job.onduty then
                            lib.showTextUI(locale('text.armory_button'))
                        end
                    end,
                    onExit   = function() lib.hideTextUI() end,
                    inside   = function()
                        if OnKeyPress then
                            OnKeyPress(function() openArmory(i, ii) end)
                        else
                            if IsControlJustPressed(0, 38) then openArmory(i, ii) end
                        end
                    end,
                })
            end
        end
    end)
end
