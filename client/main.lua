local sharedConfig = require 'config.shared'

-- ========= defaults (don’t clobber if defined elsewhere) =========
InBedDict        = InBedDict        or 'anim@gangops@morgue@table@'
InBedAnim        = InBedAnim        or 'ko_front'            -- align with hospital client
HealAnimDict     = HealAnimDict     or 'mini@cpr@char_a@cpr_str'
HealAnim         = HealAnim         or 'cpr_pumpchest'
IsInHospitalBed  = IsInHospitalBed  or false
EmsNotified      = EmsNotified      or false
CanLeaveBed      = CanLeaveBed      or true
OnPainKillers    = OnPainKillers    or false

---Revives player, healing all injuries
---Intended to be called from client or server.
RegisterNetEvent('hospital:client:Revive', function()
    lib.print.info('hospital:client:Revive', 'IsInHospitalBed', IsInHospitalBed)

    if IsInHospitalBed then
        lib.requestAnimDict(InBedDict, 5000)
        TaskPlayAnim(cache.ped, InBedDict, InBedAnim, 8.0, 1.0, -1, 1, 0.0, false, false, false)

        -- Hand off to EF-Medical to do the actual revive & cleanup
        TriggerEvent('qbx_medical:client:playerRevived')

        -- Top up needs on the server (safe if your medical server registered it)
        lib.callback.await('qbx_medical:server:resetHungerAndThirst')

        CanLeaveBed = true
        lib.print.info("Healed in hospital, we are clear to leave the bed now.")
    end

    EmsNotified = false
end)

RegisterNetEvent('qbx_medical:client:playerRevived', function()
    EmsNotified = false
end)

---Sends player phone email with hospital bill.
---@param amount number
RegisterNetEvent('hospital:client:SendBillEmail', function(amount)
    if GetInvokingResource() then return end
    SetTimeout(math.random(2500, 4000), function()
        local pd = QBX and QBX.PlayerData
        if not (pd and pd.charinfo) then return end

        local charInfo = pd.charinfo
        local gender   = (charInfo.gender == 1) and (locale('info.mrs') or 'Mrs.') or (locale('info.mr') or 'Mr.')
        local lastname = charInfo.lastname or ''

        -- Your phone resource expects this payload; if your locale needs a table, adapt accordingly.
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender  = locale('mail.sender'),
            subject = locale('mail.subject'),
            message = locale('mail.message', gender, lastname, amount),
            button  = {}
        })
    end)
end)

---Sets blips for stations on map
CreateThread(function()
    for i, station in ipairs(sharedConfig.locations.stations or {}) do
        local blip = AddBlipForCoord(station.coords.x, station.coords.y, station.coords.z)
        SetBlipSprite(blip, 61)
        SetBlipAsShortRange(blip, true)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 25)

        -- Proper name assignment
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(station.label or 'Medical Center')
        EndTextCommandSetBlipName(blip)
    end
end)

-- Small helper used by other client files
function OnKeyPress(cb)
    if IsControlJustPressed(0, 38) then -- E
        lib.hideTextUI()
        cb()
    end
end
