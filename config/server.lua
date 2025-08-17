-- config/server.lua

-- Try to fetch webhooks from ef_nexus, but don't explode if it's not running.
local webhooks = nil
do
    local ok, val = pcall(function()
        return exports.ef_nexus and exports.ef_nexus:GetWebhooks()
    end)
    if ok then webhooks = val end
end

-- Safe wrapper around fd_banking:AddMoney
local function safeDepositSociety(society, amount, reason, metadata)
    local ok = pcall(function()
        if exports.fd_banking then
            exports.fd_banking:AddMoney(society, amount, reason, metadata)
        end
    end)
    if not ok then
        -- optional: print once in console; comment out if you want it silent
        -- lib.print.warn(('[ambulancejob] depositSociety failed for %s (%s)'):format(society, tostring(reason)))
    end
end

return {
    doctorCallCooldown = 1,    -- minutes between doctor call alerts
    wipeInvOnRespawn   = false, -- if true, remove all items on respawn (ambulance job flow)

    -- Banking deposit used by hospital billing (server/hospital.lua)
    depositSociety = safeDepositSociety,

    -- Webhook used by EMS Timeclock events (server/main.lua)
    logWebhook = webhooks
        and webhooks.Logging
        and webhooks.Logging.EMSDuty
        or nil, -- leave nil to disable if ef_nexus isn’t present
}
