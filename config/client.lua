return {
    useTarget = true,
    debugPoly = false,

    -- Ambulancejob-only timers (do not affect EF-Medical internals)
    painkillerInterval = 60,   -- minutes painkillers last (ambulancejob client effects)
    checkInHealTime    = 20,   -- seconds from check-in to healed (bed sequence timing)
    aiHealTimer        = 20,   -- seconds NPC/auto heal duration (if used separately from checkInHealTime)
    laststandTimer     = 300,  -- seconds for ambulancejob UI/logic; EF-Medical uses its own last-stand timer
}
