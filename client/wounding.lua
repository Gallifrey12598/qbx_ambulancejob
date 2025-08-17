local config = require 'config.client'

local painkillerAmount = 0            -- stacked doses (max 3)
local painkillerTimerActive = false   -- ensures only one timer loop runs
OnPainKillers = OnPainKillers or false

local function addHealth(amount)
    local max = GetEntityMaxHealth(cache.ped)
    local new = math.min(max, GetEntityHealth(cache.ped) + amount)
    SetEntityHealth(cache.ped, new)
end

-- IFAKs: small heal + stress relief + possible bleed reduction
lib.callback.register('hospital:client:UseIfaks', function()
    local ok = lib.progressCircle({
        duration = 3000,
        position = 'bottom',
        label = locale('progress.ifaks'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = false, car = false, combat = true, mouse = false },
        anim = { dict = 'mp_suicide', clip = 'pill' },
    })

    StopAnimTask(cache.ped, 'mp_suicide', 'pill', 1.0)

    if not ok then
        lib.notify({ title = locale('error.canceled'), type = 'error' })
        return false
    end

    TriggerServerEvent('hud:server:RelieveStress', math.random(12, 24))
    addHealth(10)

    OnPainKillers = true
    if exports.qbx_medical?.DisableDamageEffects then exports.qbx_medical:DisableDamageEffects() end

    if painkillerAmount < 3 then painkillerAmount = painkillerAmount + 1 end

    if math.random(1, 100) < 50 and exports.qbx_medical?.removeBleed then
        exports.qbx_medical:removeBleed(1)
    end

    return true
end)

-- Bandage: small heal + bleed chance + small chance to clear minor injuries
lib.callback.register('hospital:client:UseBandage', function()
    local dict, clip = 'missmic4', 'michael_tux_fidget'

    local ok = lib.progressCircle({
        duration = 4000,
        position = 'bottom',
        label = locale('progress.bandage'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = false, car = false, combat = true, mouse = false },
        anim = { dict = dict, clip = clip },
    })

    StopAnimTask(cache.ped, dict, clip, 1.0)

    if not ok then
        lib.notify({ title = locale('error.canceled'), type = 'error' })
        return false
    end

    addHealth(10)

    if math.random(1, 100) < 50 and exports.qbx_medical?.removeBleed then
        exports.qbx_medical:removeBleed(1)
    end
    if math.random(1, 100) < 7 and exports.qbx_medical?.resetMinorInjuries then
        exports.qbx_medical:resetMinorInjuries()
    end

    return true
end)

-- Painkillers: disable damage effects for a duration; stacking up to 3
lib.callback.register('hospital:client:UsePainkillers', function()
    local ok = lib.progressCircle({
        duration = 3000,
        position = 'bottom',
        label = locale('progress.painkillers'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = false, car = false, combat = true, mouse = false },
        anim = { dict = 'mp_suicide', clip = 'pill' },
    })

    StopAnimTask(cache.ped, 'mp_suicide', 'pill', 1.0)

    if not ok then
        lib.notify({ title = locale('error.canceled'), type = 'error' })
        return false
    end

    OnPainKillers = true
    if exports.qbx_medical?.DisableDamageEffects then exports.qbx_medical:DisableDamageEffects() end
    if painkillerAmount < 3 then painkillerAmount = painkillerAmount + 1 end

    return true
end)

-- Single timer loop to consume stacked painkiller doses
local function painkillerTimerLoop()
    if painkillerTimerActive then return end
    painkillerTimerActive = true

    CreateThread(function()
        while OnPainKillers or painkillerAmount > 0 do
            if painkillerAmount > 0 then
                -- consume one stack after configured minutes
                local minutes = tonumber(config.painkillerInterval) or 60
                Wait(minutes * 60 * 1000)
                painkillerAmount = math.max(0, painkillerAmount - 1)
            else
                -- no stacks left
                OnPainKillers = false
                if exports.qbx_medical?.EnableDamageEffects then exports.qbx_medical:EnableDamageEffects() end
            end
            Wait(0)
        end
        painkillerTimerActive = false
    end)
end

-- Monitor state and start timer when needed (cheap loop)
CreateThread(function()
    while true do
        if OnPainKillers and painkillerAmount > 0 then
            painkillerTimerLoop()
            Wait(1000)
        else
            Wait(2000)
        end
    end
end)
