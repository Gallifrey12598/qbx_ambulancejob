local config       = require 'config.client'
local sharedConfig = require 'config.shared'

local bedObject
local bedOccupyingData
local cam
local hospitalOccupying
local bedIndexOccupying
local playerState = LocalPlayer.state
local Interactions = {}

-- external anim names (defined elsewhere in your repo)
InBedDict = InBedDict or 'anim@gangops@morgue@table@'
InBedAnim = InBedAnim or 'ko_front'

-- runtime flags (globals so other files can read them)
IsInHospitalBed = IsInHospitalBed or false
CanLeaveBed     = CanLeaveBed or false

-- ========== helpers ==========

local function safeRequestDict(dict, timeout)
    local ok = lib.requestAnimDict(dict, timeout or 5000)
    if not ok then lib.print.warn('Failed to load anim dict:', dict) end
    return ok
end

---Teleports the player to lie down in bed and sets the player's camera.
local function setBedCam()
    DoScreenFadeOut(1000)
    while not IsScreenFadedOut() do Wait(50) end

    if IsPedDeadOrDying(cache.ped, true) then
        local pos = GetEntityCoords(cache.ped)
        NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, GetEntityHeading(cache.ped), 0, false)
    end

    if not bedOccupyingData then
        lib.print.error("No bed data found for", tostring(hospitalOccupying), tostring(bedIndexOccupying))
        DoScreenFadeIn(500)
        return
    end

    -- find / freeze bed object (bed model may not have spawned yet)
    for i = 1, 20 do
        bedObject = GetClosestObjectOfType(
            bedOccupyingData.coords.x, bedOccupyingData.coords.y, bedOccupyingData.coords.z,
            2.0, bedOccupyingData.model, false, false, false
        )
        if bedObject and bedObject ~= 0 then break end
        Wait(100)
    end
    if bedObject and bedObject ~= 0 then
        FreezeEntityPosition(bedObject, true)
    else
        lib.print.warn('Bed object not found for model', bedOccupyingData.model)
    end

    SetEntityCoordsNoOffset(cache.ped, bedOccupyingData.coords.x, bedOccupyingData.coords.y, bedOccupyingData.coords.z + 0.02, false, false, false)
    SetEntityHeading(cache.ped, bedOccupyingData.coords.w)
    FreezeEntityPosition(cache.ped, true)

    safeRequestDict(InBedDict)
    TaskPlayAnim(cache.ped, InBedDict, InBedAnim, 8.0, 1.0, -1, 1, 0.0, false, false, false)

    -- camera
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 1, true, true)
    AttachCamToPedBone(cam, cache.ped, 31085, 0.0, 1.0, 1.0, true)
    SetCamFov(cam, 90.0)
    local heading = GetEntityHeading(cache.ped)
    heading = (heading > 180) and heading - 180 or heading + 180
    SetCamRot(cam, -45.0, 0.0, heading, 2)

    DoScreenFadeIn(600)
end

local function putPlayerInBed(hospitalName, bedIndex, isRevive, skipOpenCheck)
    lib.print.info('putPlayerInBed', hospitalName, bedIndex, isRevive, skipOpenCheck, IsInHospitalBed)

    if IsInHospitalBed then
        lib.notify({ title = locale('error.beds_taken') or "There is already a person in this bed.", type = 'error' })
        lib.print.warn("IsInHospitalBed: Player already in bed")
        return
    end

    if not sharedConfig.locations.hospitals[hospitalName] then
        lib.notify({ title = "Invalid hospital.", type = 'error' })
        return
    end

    if not skipOpenCheck then
        local taken = lib.callback.await('qbx_ambulancejob:server:isBedTaken', false, hospitalName, bedIndex)
        if taken then
            lib.notify({ title = locale('error.beds_taken'), type = 'error' })
            return
        end
    end

    hospitalOccupying = hospitalName
    bedIndexOccupying = bedIndex
    bedOccupyingData  = sharedConfig.locations.hospitals[hospitalName].beds[bedIndex]
    if not bedOccupyingData then
        lib.notify({ title = "Bed not found.", type = 'error' })
        return
    end

    IsInHospitalBed = true
    CanLeaveBed     = false

    -- soften gameplay while in bed
    if exports.qbx_medical?.DisableDamageEffects then exports.qbx_medical:DisableDamageEffects() end
    if exports.qbx_medical?.DisableRespawn       then exports.qbx_medical:DisableRespawn()       end

    setBedCam()

    -- begin heal flow
    CreateThread(function()
        lib.print.info("Starting healing thread")
        -- AI heal by default; explicit isRevive=false skips it
        if isRevive == nil or isRevive == true then
            lib.notify({ title = locale('success.being_helped') or 'You are being treated...', type = 'success' })
            Wait((config.aiHealTimer or 20) * 1000)
            TriggerEvent('hospital:client:Revive') -- your client-side revive flow
        else
            lib.print.info("Bed: no revive requested; allow exit")
            CanLeaveBed = true
        end
    end)

    -- mark bed as occupied server-side
    TriggerServerEvent('qbx_ambulancejob:server:playerEnteredBed', hospitalName, bedIndex)
end

RegisterNetEvent('qbx_ambulancejob:client:putPlayerInBed', function(hospitalName, bedIndex)
    putPlayerInBed(hospitalName, bedIndex, true, true)
end)

---Notifies doctors, and puts player in a hospital bed.
local function checkIn(hospitalName)
    local canCheck = lib.callback.await('qbx_ambulancejob:server:canCheckIn', false, hospitalName)
    if not canCheck then return end

    local ok = lib.progressCircle({
        duration = 2000,
        position = 'bottom',
        label = locale('progress.checking_in'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false },
        anim = { clip = 'base', dict = 'missheistdockssetup1clipboard@base', flag = 16 },
        prop = {
            { model = 'prop_notepad_01', bone = 18905, pos = vec3(0.1, 0.02, 0.05),   rot = vec3(10.0, 0.0, 0.0) },
            { model = 'prop_pencil_01',  bone = 58866, pos = vec3(0.11, -0.02, 0.001), rot = vec3(-120.0, 0.0, 0.0) }
        }
    })

    if not ok then
        lib.notify({ title = locale('error.canceled'), type = 'error' })
        return
    end

    -- server will validate & emit :client:checkedIn to place us in bed
    lib.callback('qbx_ambulancejob:server:checkIn', false, nil, cache.serverId, hospitalName)
end

RegisterNetEvent('qbx_ambulancejob:client:checkedIn', function(hospitalName, bedIndex)
    putPlayerInBed(hospitalName, bedIndex, true, true)
end)

-- ========== interactions ==========

if config.useTarget then
    CreateThread(function()
        for hospitalName, hospital in pairs(sharedConfig.locations.hospitals) do
            if hospital.checkIn then
                exports.sleepless_interact:addCoords(hospital.checkIn, {
                    {
                        id = hospitalName .. '_checkin',
                        label = locale('text.check'),
                        icon = 'fas fa-clipboard',
                        onSelect = function() checkIn(hospitalName) end,
                        debug = config.debugPoly,
                        distance = 2.5,
                    },
                    {
                        id = hospitalName .. '_checkin_carry',
                        label = "Check Carried Person In",
                        icon = "fa fa-clipboard",
                        canInteract = function() return playerState.isCarrying or playerState.isEscorting end,
                        onSelect = function()
                            local tgt = playerState.isCarrying or playerState.isEscorting
                            if tgt then
                                local open = lib.callback.await("qbx_ambulancejob:server:getOpenBed", false, hospitalName)
                                if open then
                                    TriggerServerEvent('hospital:server:putPlayerInBed', tgt, hospitalName, open)
                                else
                                    lib.notify({ title = locale('error.beds_taken'), type = 'error' })
                                end
                            end
                        end,
                        debug = config.debugPoly,
                        distance = 2.5,
                    }
                })
                Interactions[#Interactions + 1] = hospitalName .. '_checkin'
                Interactions[#Interactions + 1] = hospitalName .. '_checkin_carry'
            end

            for i = 1, #hospital.beds do
                local bed = hospital.beds[i]
                exports.ox_target:addBoxZone({
                    name     = hospitalName .. '_bed_' .. i,
                    coords   = bed.coords.xyz,
                    size     = vec3(1.7, 1.9, 2.0),
                    rotation = bed.coords.w,
                    debug    = config.debugPoly,
                    options  = {
                        {
                            canInteract = function() return not IsInHospitalBed end,
                            onSelect    = function() putPlayerInBed(hospitalName, i, true) end,
                            icon        = 'fas fa-bed',
                            label       = locale('text.bed'),
                            distance    = 1.5,
                        },
                        {
                            canInteract = function() return (playerState.isCarrying or playerState.isEscorting) and not IsInHospitalBed end,
                            onSelect    = function()
                                local tgt = playerState.isCarrying or playerState.isEscorting
                                if tgt then
                                    TriggerServerEvent('hospital:server:putPlayerInBed', tgt, hospitalName, i)
                                end
                            end,
                            icon     = 'fas fa-user-injured',
                            label    = locale('text.put_bed'),
                            distance = 1.5,
                        }
                    }
                })
            end
        end
    end)
end

-- ========== exit bed flow ==========

local rightOffset = -1

---Plays animation to get out of bed and resets variables
local function leaveBed()
    safeRequestDict('switch@franklin@bed')
    FreezeEntityPosition(cache.ped, false)
    SetEntityInvincible(cache.ped, false)
    SetEntityHeading(cache.ped, bedOccupyingData.coords.w + 90.0)
    TaskPlayAnim(cache.ped, 'switch@franklin@bed', 'sleep_getup_rubeyes', 4.0, 1.0, -1, 8, -1.0, false, false, false)

    Wait(1200)
    ClearPedTasks(cache.ped)

    -- move off the side of the bed
    local newX = bedOccupyingData.coords.x + rightOffset * math.sin(math.rad(bedOccupyingData.coords.w))
    local newY = bedOccupyingData.coords.y + rightOffset * math.cos(math.rad(bedOccupyingData.coords.w))
    SetEntityCoords(cache.ped, newX, newY, bedOccupyingData.coords.z - 1.0, false, false, false, false)

    TriggerServerEvent('qbx_ambulancejob:server:playerLeftBed', hospitalOccupying, bedIndexOccupying)

    if bedObject and bedObject ~= 0 then
        FreezeEntityPosition(bedObject, true)
    end
    RenderScriptCams(false, true, 200, true, true)
    if cam then DestroyCam(cam, false) cam = nil end

    hospitalOccupying = nil
    bedIndexOccupying = nil
    bedObject         = nil
    bedOccupyingData  = nil
    IsInHospitalBed   = false

    if exports.qbx_medical?.EnableDamageEffects then exports.qbx_medical:EnableDamageEffects() end
    if exports.qbx_medical?.AllowRespawn       then exports.qbx_medical:AllowRespawn()       end

    -- jail return logic — preserve original semantics
    if QBX?.PlayerData?.metadata?.injail then return end
    TriggerEvent('prison:client:Enter', QBX.PlayerData.metadata.injail)
end

---Shows player option to press key to leave bed when available.
CreateThread(function()
    while true do
        if IsInHospitalBed and CanLeaveBed then
            lib.showTextUI(locale('text.bed_out'))
            while IsInHospitalBed and CanLeaveBed do
                if not IsEntityPlayingAnim(cache.ped, InBedDict, InBedAnim, 3) then
                    lib.playAnim(cache.ped, InBedDict, InBedAnim, 8.0, 1.0, -1, 1, 0.0, false, 0, false)
                end
                if OnKeyPress then
                    OnKeyPress(leaveBed) -- your shared keybind helper
                else
                    -- Fallback: E key
                    if IsControlJustPressed(0, 38) then leaveBed() end
                end
                Wait(0)
            end
            lib.hideTextUI()
        else
            Wait(500)
        end
    end
end)

---Reset player settings that the server is storing
local function onPlayerUnloaded()
    if bedIndexOccupying and hospitalOccupying then
        TriggerServerEvent('qbx_ambulancejob:server:playerLeftBed', hospitalOccupying, bedIndexOccupying)
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', onPlayerUnloaded)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    lib.hideTextUI()
    onPlayerUnloaded()
    for _, id in ipairs(Interactions) do
        if exports.sleepless_interact?.removeCoords then
            exports.sleepless_interact:removeCoords(id)
        end
    end
end)
