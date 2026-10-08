--[[
	x_mob_core - Centralized Hunger & Stamina Compatibility Adapter
	Dynamically integrates stamina, hbhunger, hunger_ng, and provides
	anti-heal suppression and graceful zero-dependency fallback.

	Author: SaKeL
	License: MIT
]]

---@class HungerAdapterSubsystem
local hunger_adapter = {}

--- Active anti-heal suppression trackers
--- Key: player_name string -> remaining_duration number
---@type table<string, number>
local healing_suppression = {}

-- Cached mod environment detection
local has_stamina = core.get_modpath("stamina") ~= nil
local has_hbhunger = core.get_modpath("hbhunger") ~= nil
local has_hunger_ng = core.get_modpath("hunger_ng") ~= nil

-- ============================================================================
-- 1. PUBLIC HUNGER & STAMINA API
-- ============================================================================

--- Checks if any supported hunger or stamina mod is loaded in the active world
---@return boolean available True if any hunger/stamina engine is active
function hunger_adapter.is_available()
	return (has_stamina and rawget(_G, "stamina") ~= nil)
		or (has_hbhunger and rawget(_G, "hbhunger") ~= nil)
		or (has_hunger_ng and rawget(_G, "hunger_ng") ~= nil)
end

--- Drains hunger or stamina from a target player
---@param player ObjectRef Target player
---@param amount number Saturation or hunger units to drain
---@param reason? string Contextual reason tag (e.g. "x_mob_core:spores")
---@return boolean success True if a hunger/stamina modification occurred
function hunger_adapter.drain(player, amount, reason)
	if not player or not player:is_player() then return false end
	local pname = player:get_player_name()
	if not pname or pname == "" then return false end

	local amt = amount or 1.0
	local tag = reason or "x_mob_core"

	-- 1. stamina mod integration
	local stamina_mod = rawget(_G, "stamina")
	if stamina_mod then
		if stamina_mod.exhaust_player then
			stamina_mod.exhaust_player(player, amt * 20, tag)
		end
		if stamina_mod.change_saturation then
			stamina_mod.change_saturation(player, -math.max(1, math.floor(amt)))
		end
		return true
	end

	-- 2. hbhunger mod integration
	local hbhunger_mod = rawget(_G, "hbhunger")
	if hbhunger_mod and hbhunger_mod.hunger then
		local cur = tonumber(hbhunger_mod.hunger[pname]) or 20
		local next_val = math.max(0, cur - math.max(1, math.floor(amt)))
		hbhunger_mod.hunger[pname] = next_val
		if hbhunger_mod.set_hunger_raw then
			hbhunger_mod.set_hunger_raw(player)
		end
		return true
	end

	-- 3. hunger_ng mod integration
	local hunger_ng_mod = rawget(_G, "hunger_ng")
	if hunger_ng_mod and hunger_ng_mod.alter_hunger then
		hunger_ng_mod.alter_hunger(player, -amt)
		return true
	end

	return false
end

--- Helper to get current monotonic time in seconds
local function get_current_time()
	return core.get_us_time() / 1000000
end

--- Suppresses health regeneration for a player for a specified duration
---@param player ObjectRef Target player
---@param duration number Duration in seconds
function hunger_adapter.suppress_healing(player, duration)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local dur = duration or 3.0
	local expire_time = get_current_time() + dur
	local cur_expire = healing_suppression[pname] or 0
	healing_suppression[pname] = math.max(cur_expire, expire_time)
end

--- Checks if health regeneration is currently suppressed on a player
---@param player ObjectRef Target player
---@return boolean is_suppressed True if anti-heal is actively preventing recovery
function hunger_adapter.is_suppressed(player)
	if not player or not player:is_player() then return false end
	local pname = player:get_player_name()
	if not pname or pname == "" then return false end

	local expire_time = healing_suppression[pname]
	if not expire_time then return false end

	if get_current_time() >= expire_time then
		healing_suppression[pname] = nil
		return false
	end
	return true
end

hunger_adapter.is_healing_suppressed = hunger_adapter.is_suppressed

--- Clears healing suppression for a player
---@param player ObjectRef Target player
function hunger_adapter.clear_suppression(player)
	if not player then return end
	local pname = player:is_player() and player:get_player_name()
	if pname and pname ~= "" then
		healing_suppression[pname] = nil
	end
end

-- ============================================================================
-- 2. COMBAT HP HOOK & LIFECYCLE LISTENERS
-- ============================================================================

-- Intercept and negate positive HP recovery (healing / regeneration) while anti-heal is active
core.register_on_player_hpchange(function(player, hp_change, _reason)
	if hp_change > 0 and hunger_adapter.is_suppressed(player) then
		return 0, true
	end
	return hp_change
end, true)

core.register_on_leaveplayer(function(player)
	hunger_adapter.clear_suppression(player)
end)

core.register_on_dieplayer(function(player)
	hunger_adapter.clear_suppression(player)
end)

core.register_on_respawnplayer(function(player)
	hunger_adapter.clear_suppression(player)
end)

core.register_on_shutdown(function()
	healing_suppression = {}
end)

x_mob_core.hunger_adapter = hunger_adapter

return hunger_adapter
