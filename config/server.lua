local webhooks = exports.ef_nexus:GetWebhooks()

return {
    doctorCallCooldown = 1,   -- Time in minutes for cooldown between doctors calls
    wipeInvOnRespawn = false, -- Enable to disable removing all items from player on respawn
    depositSociety = function(society, amount)
        exports['qb-management']:AddMoney(society, amount)
    end,
    logWebhook = webhooks.Logging.EMSDuty
}