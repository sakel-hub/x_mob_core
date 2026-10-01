--[[
	x_mob_core - High-Performance Luanti Mob & Spawner Framework
	Mod Initialization Entrypoint
]]

local modpath = core.get_modpath("x_mob_core")

-- Load core API first
dofile(modpath .. "/api.lua")

-- Seed pseudo-random generator with high-resolution clock entropy
local seed = (core and core.get_us_time and core.get_us_time()) or os.time()
math.randomseed(tonumber(tostring(seed):reverse():sub(1, 9)) or seed)
for _ = 1, 3 do math.random() end

core.log("action", "[x_mob_core] S.O.L.I.D. mob and spawner framework " ..
	"loaded successfully with zero external dependencies.")
