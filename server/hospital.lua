-- server/hospital.lua
-- Contains code relevant to the physical hospital building. Check-in, beds, respawn, etc.

local config = require 'config.server'
local sharedConfig = require 'config.shared'
local triggerEventHooks = require '@qbx_core.modules.hooks'

local doctorCalled = false

---@type table<string, table<number, boolean>>
local hospitalBedsTaken = {}

for hospitalName, hospital in pairs(sharedConfig.locations.hospitals) do
    hospitalBedsTaken[hospitalName] = {}
    for i = 1, #hospital.beds do
        hospitalBedsTaken[hospitalName][i] = false
    end
end

local function getOpenBed(hospitalName)
    local beds = hospitalBedsTaken[hospitalName]
    if not beds then return nil end
    for i = 1, #beds do
        if not beds[i] then
            return i
        end
    end
    return nil
end

lib.callback.register('qbx_ambulancejob:server:getOpenBed', function(_, hospitalName)
    return getOpenBed(hospitalName)
end)

---@param src number
local function billPlayer(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    player.Functions.RemoveMoney('bank', sharedConfig.checkInCost,
        'San Andreas Medical Network: Medical Bills (Hospital)',
        { type = "purchase:services", subtype = "medical" }
    )

    if config.depositSociety then
        config.depositSociety('sams', sharedConfig.checkInCost, "Hospital Bills: " .. player.PlayerData.citizenid, {
            type = "sale:services",
            subtype = "medical",
            purchaser = player.PlayerData.citizenid,
        })
    end

    TriggerClientEvent('hospital:client:SendBillEmail', src, sharedConfig.checkInCost)
end

--- Clear carry/escort relationships on source player (and their target) using replicated state
local function clearCarryEscortState(src)
    local state = Player(src) and Player(src).state
    if not state then return end

    local target = state.isCarrying or state.isEscorting
    if target then
        local tState = Player(target) and Player(target).state
        -- clear source flags
        state:set('isCarrying', false, true)
        state:set('isEscorting', false, true)
        -- clear target flags
        if tState then
            if tState.isCarried then tState:set('isCarried', false, true) end
            if tState.isEscorted then tState:set('isEscorted', false, true) end
        end
    end
end

RegisterNetEvent('qbx_ambulancejob:server:playerEnteredBed', function(hospitalName, bedIndex)
    if GetInvokingResource() then return end
    local src = source

    clearCarryEscortState(src)
    billPlayer(src)

    local state = Player(src) and Player(src).state
    if state then
        state:set('hospitalName', hospitalName, true)
        state:set('bedIndex', bedIndex, true)
    end

    if hospitalBedsTaken[hospitalName] then
        hospitalBedsTaken[hospitalName][bedIndex] = true
    end
end)

RegisterNetEvent('qbx_ambulancejob:server:playerLeftBed', function(hospitalName, bedIndex)
    if GetInvokingResource() then return end
    if hospitalBedsTaken[hospitalName] then
        hospitalBedsTaken[hospitalName][bedIndex] = false
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local state = Player(src) and Player(src).state
    if not state then return end

    local hName = state.hospitalName
    local bIndex = state.bedIndex

    if hName and bIndex and hospitalBedsTaken[hName] then
        hospitalBedsTaken[hName][bIndex] = false
    end

    state:set('hospitalName', nil, true)
    state:set('bedIndex', nil, true)
end)

---@param playerId number
---@param hospitalName string
---@param bedIndex number
RegisterNetEvent('hospital:server:putPlayerInBed', function(playerId, hospitalName, bedIndex)
    if GetInvokingResource() then return end
    local src = source

    clearCarryEscortState(src)
    TriggerClientEvent('qbx_ambulancejob:client:putPlayerInBed', playerId, hospitalName, bedIndex)
end)

lib.callback.register('qbx_ambulancejob:server:isBedTaken', function(_, hospitalName, bedIndex)
    return hospitalBedsTaken[hospitalName] and hospitalBedsTaken[hospitalName][bedIndex] or false
end)

local function getEmsDuty()
    -- Be robust: qbx_core:GetDutyCountType('ems') may return count or count,list
    local count, list = exports.qbx_core:GetDutyCountType('ems')
    if type(count) ~= 'number' and type(list) == 'table' then
        -- some builds might return only a list
        count = #list
    end
    return count or 0, list
end

local function sendDoctorAlert()
    if doctorCalled then return end
    doctorCalled = true

    local _, doctors = getEmsDuty()
    if type(doctors) == 'table' then
        for i = 1, #doctors do
            local doctor = doctors[i]
            exports.qbx_core:Notify(doctor, locale('info.dr_needed'), 'inform')
        end
    end

    SetTimeout((config.doctorCallCooldown or 5) * 60000, function()
        doctorCalled = false
    end)
end

local function canCheckIn(source, hospitalName)
    local numDoctors = getEmsDuty()
    if numDoctors >= (sharedConfig.minForCheckIn or 2) then
        exports.qbx_core:Notify(source, locale('info.dr_alert'), 'inform')
        sendDoctorAlert()
        return false
    end

    if not triggerEventHooks('checkIn', { source = source, hospitalName = hospitalName }) then
        return false
    end

    return true
end

lib.callback.register('qbx_ambulancejob:server:canCheckIn', canCheckIn)

---Sends the patient to an open bed within the hospital
---@param src number the player doing the checking in
---@param patientSrc number the player being checked in
---@param hospitalName string name of the hospital matching the config where player should be placed
---@return boolean
local function checkIn(src, patientSrc, hospitalName)
    if not canCheckIn(patientSrc, hospitalName) then return false end

    local bedIndex = getOpenBed(hospitalName)
    if not bedIndex then
        exports.qbx_core:Notify(src, locale('error.beds_taken'), 'error')
        return false
    end

    clearCarryEscortState(src)
    TriggerClientEvent('qbx_ambulancejob:client:checkedIn', patientSrc, hospitalName, bedIndex)
    return true
end

lib.callback.register('qbx_ambulancejob:server:checkIn', checkIn)
exports('CheckIn', checkIn)

local function respawn(src)
    local closestHospital

    local p = Player(src)
    local pState = p and p.state or nil

    if pState and pState.jailTime then
        closestHospital = 'jail'
    else
        local ped = GetPlayerPed(src)
        local coords = ped and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
        local closestDist = nil

        for hospitalName, hospital in pairs(sharedConfig.locations.hospitals) do
            if hospitalName ~= 'jail' then
                local dist = #(coords - hospital.coords)
                if not closestDist or dist < closestDist then
                    closestDist = dist
                    closestHospital = hospitalName
                end
            end
        end
    end

    if not closestHospital then
        exports.qbx_core:Notify(src, locale('error.beds_taken'), 'error')
        return
    end

    local bedIndex = getOpenBed(closestHospital)
    if not bedIndex then
        exports.qbx_core:Notify(src, locale('error.beds_taken'), 'error')
        return
    end

    TriggerClientEvent('qbx_ambulancejob:client:checkedIn', src, closestHospital, bedIndex)
end

AddEventHandler('qbx_medical:server:playerRespawned', function(src)
    -- ensure src exists if event was triggered with only source implicitly
    respawn(src or source)
end)
