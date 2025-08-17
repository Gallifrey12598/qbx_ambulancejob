local sharedConfig = require 'config.shared'
local serverConfig = require 'config.server'
local treatments   = sharedConfig.treatments or {}

---@alias source number

-- Normalize EMS duty count across different qbx_core versions
local function getEmsDuty()
    local count, list = exports.qbx_core:GetDutyCountType('ems')
    if type(count) ~= 'number' and type(list) == 'table' then
        count = #list
    end
    return count or 0, list
end

lib.callback.register('qbx_ambulancejob:server:getPlayerStatus', function(_, targetSrc)
    return exports.qbx_medical:GetPlayerStatus(targetSrc)
end)

local function registerArmory()
    if not (sharedConfig.locations and sharedConfig.locations.armory) then return end
    for _, armory in pairs(sharedConfig.locations.armory) do
        if armory and armory.shopType then
            exports.ox_inventory:RegisterShop(armory.shopType, armory)
        end
    end
end

---@param playerId number
RegisterNetEvent('hospital:server:TreatWounds', function(playerId)
    local src = source
    lib.print.debug('hospital:server:TreatWounds', playerId)

    if GetInvokingResource() then return end

    local player  = exports.qbx_core:GetPlayer(src)
    local patient = exports.qbx_core:GetPlayer(playerId)
    if not player or not patient then return end
    if player.PlayerData.job.type ~= 'ems' then return end

    if not exports.ox_inventory:RemoveItem(src, 'bandage', 1) then
        lib.print.warn(("hospital:server:TreatWounds called by %s but they didn't have a bandage."):format(src))
        return
    end

    -- Ask the target client to heal (full)
    lib.callback.await('qbx_medical:client:heal', playerId, 'full')
end)

---@param playerId number
---@param injuryType string
RegisterNetEvent('hospital:server:TreatInjury', function(playerId, injuryType)
    local src = source
    lib.print.debug('hospital:server:TreatInjury', playerId, injuryType)

    if GetInvokingResource() then return end

    local player  = exports.qbx_core:GetPlayer(src)
    local patient = exports.qbx_core:GetPlayer(playerId)
    if not player or not patient then return end
    if player.PlayerData.job.type ~= 'ems' then return end

    local treatment = treatments[injuryType]
    if not treatment then return end

    if not exports.ox_inventory:RemoveItem(src, treatment.item, 1) then
        lib.print.warn(('hospital:server:TreatInjury called by %s but they did not have %s.'):format(src, treatment.item))
        return
    end

    lib.callback.await('qbx_medical:client:heal', playerId, injuryType)
end)

local reviveCost    = sharedConfig.reviveCost
local revivePayment = math.floor((reviveCost * 0.4) + 0.5)

---@param playerId number
RegisterNetEvent('hospital:server:RevivePlayer', function(playerId)
    if GetInvokingResource() then return end

    local src     = source
    local player  = exports.qbx_core:GetPlayer(src)
    local patient = exports.qbx_core:GetPlayer(playerId)
    if not player or not patient then return end

    if player.PlayerData.job.type == 'ems' then
        patient.Functions.RemoveMoney("bank", reviveCost,
            "San Andreas Medical Network - Payment",
            { type = "purchase:services", subtype = 'medical', business = player.PlayerData.job.name }
        )

        -- deposit to business (minus commission)
        if exports.fd_banking then
            exports.fd_banking:AddMoney(
                player.PlayerData.job.name, reviveCost - revivePayment,
                "San Andreas Medical Network - Payment",
                {
                    type = "sale:services",
                    subtype = 'medical',
                    employee = player.PlayerData.citizenid,
                    purchaser = patient.PlayerData.citizenid
                }
            )
        end

        -- commission to medic
        player.Functions.AddMoney("bank", revivePayment,
            "San Andreas Medical Network - Pay",
            { type = "commission:services", subtype = 'medical', business = player.PlayerData.job.name }
        )

        TriggerClientEvent('hospital:client:SendBillEmail', patient.PlayerData.source, reviveCost)
    end

    exports.ox_inventory:RemoveItem(player.PlayerData.source, 'firstaid', 1)
    TriggerClientEvent('qbx_medical:client:playerRevived', patient.PlayerData.source)
end)

---@param targetId number
RegisterNetEvent('hospital:server:UseFirstAid', function(targetId)
    if GetInvokingResource() then return end
    local src    = source
    local target = exports.qbx_core:GetPlayer(targetId)
    if not target then return end

    local canHelp = lib.callback.await('hospital:client:canHelp', targetId)
    if not canHelp then
        exports.qbx_core:Notify(src, locale('error.cant_help'), 'error')
        return
    end

    TriggerClientEvent('hospital:client:HelpPerson', src, targetId)

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local playerName = ("%s (%s)"):format(player.PlayerData.name,  player.PlayerData.citizenid)
    local targetName = ("%s (%s)"):format(target.PlayerData.name, target.PlayerData.citizenid)

    if exports.ef_logs then
        exports.ef_logs:Log({
            event   = 'hospital',
            subevent= 'use_first_aid',
            message = playerName .. " used First Aid Kit on " .. targetName,
            source  = src,
            tags    = { target = target.PlayerData.citizenid }
        })
    end
end)

lib.callback.register('qbx_ambulancejob:server:getNumDoctors', function()
    return getEmsDuty()
end)

---@param src number
---@param event string
local function triggerEventOnEmsPlayer(src, event)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    if player.PlayerData.job.type ~= 'ems' then
        exports.qbx_core:Notify(src, locale('error.not_ems'), 'error')
        return
    end

    TriggerClientEvent(event, src)
end

lib.addCommand('status', { help = locale('info.check_health') }, function(source)
    triggerEventOnEmsPlayer(source, 'hospital:client:CheckStatus')
end)

lib.addCommand('heal', { help = locale('info.heal_player') }, function(source)
    triggerEventOnEmsPlayer(source, 'hospital:client:TreatWounds')
end)

lib.addCommand('revivep', { help = locale('info.revive_player') }, function(source)
    triggerEventOnEmsPlayer(source, 'hospital:client:RevivePlayer')
end)

-- Items
---@param src number
---@param item table
---@param event string
local function triggerItemEventOnPlayer(src, item, event)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    if exports.ox_inventory:Search(src, 'count', item.name) == 0 then return end

    local pState = Player(src) and Player(src).state or nil
    if player.PlayerData.metadata.isdead or player.PlayerData.metadata.inlaststand or (pState and pState.isCuffed) then
        exports.qbx_core:Notify(src, locale('error.cant_help_now') or "You cannot do this right now.", 'error')
        return
    end

    local removeItem = lib.callback.await(event, src)
    if not removeItem then return end

    exports.ox_inventory:RemoveItem(src, item.name, 1)
end

exports.qbx_core:CreateUseableItem('ifaks', function(source, item)
    triggerItemEventOnPlayer(source, item, 'hospital:client:UseIfaks')
end)

exports.qbx_core:CreateUseableItem('bandage', function(source, item)
    triggerItemEventOnPlayer(source, item, 'hospital:client:UseBandage')
end)

exports.qbx_core:CreateUseableItem('painkillers', function(source, item)
    triggerItemEventOnPlayer(source, item, 'hospital:client:UsePainkillers')
end)

exports.qbx_core:CreateUseableItem('firstaid', function(source, item)
    triggerItemEventOnPlayer(source, item, 'hospital:client:UseFirstAid')
end)

-- Startup hooks
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    registerArmory()
end)

-- Timeclock logging
RegisterNetEvent('QBCore:Everfall:EMS:Timeclock', function(player, ClockingIn)
    local source = player and player.PlayerData and player.PlayerData.source
    if not source then return end

    local department = "SAMS"
    local data = {
        Webhook = serverConfig.logWebhook,
        Icon = "https://files.jellyton.me/ShareX/2023/04/LSCFD-GTAV-Logo.png"
    }

    local name = (player.PlayerData.charinfo.firstname or "?") .. " " .. (player.PlayerData.charinfo.lastname or "?")
    local discordId = exports.ef_lib and exports.ef_lib:GetDiscordID(source) or "0"
    local message = ClockingIn
        and (":inbox_tray:  **" .. name .. " (<@" .. discordId .. ">)** has clocked in for duty.")
        or  (":outbox_tray:  **" .. name .. " (<@" .. discordId .. ">)** has clocked out.")

    local fields
    if ClockingIn then
        fields = {
            { name = "CitizenID", value = player.PlayerData.citizenid,      inline = true },
            { name = "Grade",     value = player.PlayerData.job.grade.name, inline = true },
        }
    else
        fields = {
            { name = "CitizenID",    value = player.PlayerData.citizenid, inline = true },
            { name = "Time Patrolled", value = "Unknown",                inline = true },
        }
    end

    local embedData = {{
        author = {
            name = GetPlayerName(source),
            icon_url = (exports.ef_discordbot and exports.ef_discordbot:GetMemberAvatar(source)) or data.Icon,
        },
        title = ClockingIn and "Clock In" or "Clock Out",
        color = ClockingIn and 3858002 or 16068139,
        description = message,
        fields = fields,
        thumbnail = { url = data.Icon }
    }}

    if data.Webhook and data.Webhook ~= "" then
        PerformHttpRequest(data.Webhook, function() end, 'POST', json.encode({
            username = department .. ' Timeclock',
            avatar_url = data.Icon,
            embeds = embedData
        }), { ['Content-Type'] = 'application/json' })
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    if not player.PlayerData.job.onduty then return end
    if player.PlayerData.job.type ~= "ems" then return end
    TriggerEvent('QBCore:Everfall:EMS:Timeclock', player, false)
end)

RegisterNetEvent("QBCore:Everfall:EMSClockIn", function(_source)
    local src = source or _source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    TriggerEvent('QBCore:Everfall:EMS:Timeclock', player, true)
end)

RegisterNetEvent("QBCore:Everfall:EMSClockOut", function(_source)
    local src = source or _source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    TriggerEvent('QBCore:Everfall:EMS:Timeclock', player, false)
end)

local function triggerEventOnEmsPlayer(src, event)
    local player = exports.qbx_core:GetPlayer(src)
    if player.PlayerData.job.type ~= 'ems' then
        exports.qbx_core:Notify(src, locale('error.not_ems'), 'error')  -- ✅ server->client notify
        return
    end
    TriggerClientEvent(event, src)
end
