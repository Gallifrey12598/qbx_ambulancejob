local config       = require 'config.client'
local sharedConfig = require 'config.shared'

local textLocation      = vec2(1.0, 1.40)
local textRequestOffset = vec2(0, 0.04)

-- Doctor count cache
local doctorCount = 0
local lastDocRefresh = 0
local DOC_REFRESH_MS = 3000  -- refresh every 3s while down/last stand

local function getDoctorCount()
    -- 60s timeout; server returns a number
    return lib.callback.await('qbx_ambulancejob:server:getNumDoctors', 60000)
end

local function refreshDoctorCountIfNeeded()
    local now = GetGameTimer()
    if now - lastDocRefresh < DOC_REFRESH_MS then return end
    lastDocRefresh = now
    CreateThread(function()
        local updatedCount = getDoctorCount()
        if type(updatedCount) == 'number' then
            doctorCount = updatedCount
            lib.print.debug("EMS count updated:", doctorCount)
        end
    end)
end

-- Helpers to read EF-Medical exports (with guards)
local function getDeathTime()
    if not exports.qbx_medical or not exports.qbx_medical.getDeathTime then return 0 end
    return exports.qbx_medical:getDeathTime() or 0
end

local function getLaststand()
    if not exports.qbx_medical or not exports.qbx_medical.getLaststand then return false end
    return exports.qbx_medical:getLaststand() or false
end

local function getLaststandTime()
    if not exports.qbx_medical or not exports.qbx_medical.getLaststandTime then return 0 end
    return exports.qbx_medical:getLaststandTime() or 0
end

local function getRespawnHoldTime()
    if not exports.qbx_medical or not exports.qbx_medical.getRespawnHoldTimeDeprecated then return 5 end
    return exports.qbx_medical:getRespawnHoldTimeDeprecated() or 5
end

-- ========================= UI blocks =========================

local function displayRespawnText()
    refreshDoctorCountIfNeeded()

    local deathTime = math.ceil(getDeathTime())
    if deathTime > 0 and doctorCount > 0 then
        qbx.drawText2d({
            text   = locale('info.respawn_txt', deathTime),
            coords = textLocation,
            scale  = 0.6
        })
    else
        qbx.drawText2d({
            text   = locale('info.respawn_revive', getRespawnHoldTime(), sharedConfig.checkInCost),
            coords = textLocation,
            scale  = 0.6
        })
    end
end

---@param ped number
local function handleDead(ped)
    if not IsInHospitalBed then
        displayRespawnText()
    end
end

---Player can ping EMS if any are on duty
local function handleRequestingEms()
    if not EmsNotified then
        qbx.drawText2d({
            text   = locale('info.request_help'),
            coords = textLocation - textRequestOffset,
            scale  = 0.6
        })
        if IsControlJustPressed(0, 47) then -- G
            TriggerServerEvent('cd_dispatch:AddNotification', {
                job_table = { 'sams' },
                coords    = GetEntityCoords(cache.ped),
                title     = 'Downed Individual',
                message   = 'Citizens reporting a downed individual.',
                flash     = 0,
                unique_id = tostring(math.random(0000000, 9999999)),
                blip      = {
                    sprite  = 280,
                    scale   = 1.2,
                    colour  = 1,
                    flashes = false,
                    text    = 'Downed Individual',
                    time    = (5 * 60 * 1000),
                    sound   = 1,
                }
            })
            -- TriggerServerEvent('hospital:server:ambulanceAlert', locale('info.civ_down'))
            EmsNotified = true
        end
    else
        qbx.drawText2d({
            text   = locale('info.help_requested'),
            coords = textLocation - textRequestOffset,
            scale  = 0.6
        })
    end
end

local function handleLastStand()
    refreshDoctorCountIfNeeded()

    local lastTime = math.ceil(getLaststandTime())
    if lastTime > (config.laststandTimer or 300) or doctorCount == 0 then
        qbx.drawText2d({
            text   = locale('info.bleed_out', lastTime),
            coords = textLocation,
            scale  = 0.6
        })
    else
        qbx.drawText2d({
            text   = locale('info.bleed_out_help', lastTime),
            coords = textLocation,
            scale  = 0.6
        })
        handleRequestingEms()
    end
end

-- ========================= main draw loop =========================

CreateThread(function()
    -- initialize doctor count once on first run
    doctorCount = getDoctorCount() or 0

    while true do
        local downed   = (exports.qbx_medical and exports.qbx_medical.isDead   and exports.qbx_medical:isDead()) or false
        local laststand = getLaststand()

        if downed or laststand then
            if downed then
                handleDead(cache.ped)
            else
                handleLastStand()
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)
