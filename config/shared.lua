-- config/shared.lua

-- Safely pull government pricing from ef_nexus (optional dependency)
local GovernmentData = (function()
    local ok, data = pcall(function()
        return exports.ef_nexus and exports.ef_nexus:GetGovernmentData("EFEmergency")
    end)
    return ok and data or {}
end)()

return {
    reviveCost   = GovernmentData.ReviveCost        or 2500,  -- Price patient pays when revived
    checkInCost  = GovernmentData.HospitalBillCost  or 1500,  -- Price for using hospital check-in
    minForCheckIn = 20,                                      -- Min on-duty EMS to disable self check-in

    locations = {
        -- On/Off duty points
        duty = {
            vector3(-260.31, 6319.41, 32.45),  -- Paleto Medical
            vector3(1109.17, 2729.65, 39.27),  -- Rt68
            vector3(-432.69, -318.04, 35.13),  -- Mount Zonah Timeclock
            vector3(349.26, -1429.4, 32.43),   -- Central LS
            vector3(351.31, -1405.04, 32.53),  -- Central LS
        },

        -- Ox Inventory shop registration (server/main.lua → registerArmory)
        armory = {
            {
                shopType = 'AmbulanceArmory',
                name = 'Armory',
                groups = { fire = 0 }, -- adjust to your ACL/groups
                inventory = {
                    { name = "radio",                   price = 0, count = 50 },
                    { name = "bandage",                 price = 0, count = 50 },
                    { name = "painkillers",             price = 0, count = 50 },
                    { name = "firstaid",                price = 0, count = 50 },
                    { name = "splint",                  price = 0, count = 50 },
                    { name = "tourniquet",              price = 0, count = 50 },
                    { name = "suturekit",               price = 0, count = 50 },
                    { name = "WEAPON_FLASHLIGHT",       price = 0, count = 50 },
                    { name = "WEAPON_FIREEXTINGUISHER", price = 0, count = 50 },
                    { name = "WEAPON_FLARE",            price = 0 },
                },
                locations = {
                    vector3(-262.46, 6323.93, 32.50), -- Paleto
                    vector3(1115.32, 2741.76, 38.52), -- Rt68
                    vector3(-453.65, -308.06, 35.32), -- Mount Zonah Closet
                    vector3(381.11, -1409.68, 33.21), -- Central LS
                }
            }
        },

        ---@class Bed
        ---@field coords vector4
        ---@field model number

        ---@type table<string, {coords: vector3, checkIn?: vector3, beds: Bed[]}>
        hospitals = {
            pillbox_upper = {
                coords  = vector3(311.81, -583.92, 43.48),
                checkIn = vector3(311.81, -583.92, 43.48),
                beds = {
                    { coords = vector4(344.39, -590.36, 42.95, 60.0),  model = -119016924 },
                    { coords = vector4(342.95, -593.54, 42.94, 60.0),  model = -119016924 },
                    { coords = vector4(341.93, -596.66, 42.94, 330.0), model = -119016924 },
                    { coords = vector4(338.26, -595.48, 42.94, 330.0), model = -119016924 },
                    { coords = vector4(334.96, -594.18, 42.94, 330.0), model = -119016924 },
                    { coords = vector4(331.28, -592.73, 42.94, 330.0), model = -119016924 },
                    { coords = vector4(332.52, -589.43, 42.94, 240.0), model = -119016924 },
                },
            },
            pillbox_lower = {
                coords  = vector3(342.53, -589.58, 29.0),
                checkIn = vector3(342.53, -589.58, 29.0),
                beds = {
                    { coords = vector4(319.46, -592.4, 28.46, 340.0),  model = -119016924 },
                    { coords = vector4(315.21, -590.81, 28.46, 340.0), model = -119016924 },
                    { coords = vector4(310.93, -589.35, 28.46, 340.0), model = -119016924 },
                    { coords = vector4(314.82, -578.54, 28.46, 160.0), model = -119016924 },
                    { coords = vector4(319.06, -580.12, 28.46, 160.0), model = -119016924 },
                    { coords = vector4(323.36, -581.74, 28.46, 160.0), model = -119016924 },
                },
            },
            paleto = {
                coords  = vector3(-250.97, 6336.20, 32.25),
                checkIn = vector3(-250.97, 6336.20, 32.25),
                beds = {
                    { coords = vector4(-255.21, 6307.02, 32.45, 45.73), model = 1004440924 },
                    { coords = vector4(-251.46, 6310.49, 33.45, 45.29), model = 1004440924 },
                    { coords = vector4(-247.79, 6314.32, 33.45, 46.13), model = 1004440924 },
                    { coords = vector4(-244.54, 6317.94, 33.45, 45.66), model = 1004440924 },
                },
            },
            rt68 = {
                coords  = vector3(1100.19, 2724.6, 38.79),
                checkIn = vector3(1100.19, 2724.6, 38.79),
                beds = {
                    { coords = vector4(1102.67, 2741.12, 38.39, 180), model = 955845118 },
                    { coords = vector4(1105.74, 2740.98, 38.39, 180), model = 955845118 },
                    { coords = vector4(1108.73, 2740.95, 38.39, 180), model = 955845118 },
                    { coords = vector4(1107.08, 2733.39, 38.39, 0),   model = 955845118 },
                    { coords = vector4(1102.58, 2733.6, 38.39, 0),    model = 955845118 },
                    { coords = vector4(1122.95, 2738.02, 38.39, 90),  model = 955845118 },
                    { coords = vector4(1122.79, 2733.71, 38.39, 90),  model = 955845118 },
                    { coords = vector4(1122.47, 2729.3, 38.39, 90),   model = 955845118 },
                },
            },
            jail = {
                coords = vector3(1761.0, 2600.0, 46.0), -- changed from vec3 → vector3 for compatibility
                beds = {
                    { coords = vector4(1761.96, 2597.74, 45.66, 270.14), model = 2117668672 },
                    { coords = vector4(1761.96, 2591.51, 45.66, 269.8),  model = 2117668672 },
                    { coords = vector4(1771.8,  2598.02, 45.66, 89.05),  model = 2117668672 },
                    { coords = vector4(1771.85, 2591.85, 45.66, 91.51),  model = 2117668672 },
                },
            },
        },

        -- Station blips/labels (if used by client)
        stations = {
            { label = "Medical Center", coords = vector3(-251.03, 6321.97, 37.62) }, -- Paleto Medical
            { label = "Medical Center", coords = vector3(1100.19, 2724.6, 38.79) },  -- RT68
            { label = "Medical Center", coords = vector3(311.81, -583.92, 43.48) },  -- Pillbox
        }
    },

    treatments = {
        fracture = { item = 'splint',     progress = 'progress.splint' },
        gunshot  = { item = 'suturekit',  progress = 'progress.suture' },
        bleed    = { item = 'tourniquet', progress = 'progress.tourniquet' },
        head     = { item = 'painkillers', progress = 'progress.head' },
    }
}
