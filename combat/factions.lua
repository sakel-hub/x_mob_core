--[[
	x_mob_core - Factions & Allegiance Subsystem
	Multi-faction membership, alliance checking, and friendly fire prevention
]]

---@class FactionsSubsystem
local factions = {}

--- Normalizes faction input into a fast O(1) set table and array list
---@param input? string|string[] Faction string or array of faction strings
---@return table<string, boolean> set Lookup set of factions
---@return string[] list Ordered list of faction strings
function factions.normalize_factions(input)
	local set = {}
	local list = {}
	if type(input) == "string" and input ~= "" then
		set[input] = true
		list[#list + 1] = input
	elseif type(input) == "table" then
		for _, v in ipairs(input) do
			if type(v) == "string" and v ~= "" and not set[v] then
				set[v] = true
				list[#list + 1] = v
			end
		end
	end
	-- Default to "monsters" if no faction was specified
	if #list == 0 then
		set["monsters"] = true
		list[1] = "monsters"
	end
	return set, list
end

--- Resolves the source entity or player behind an ObjectRef, projectile, or mob table
---@param obj any ObjectRef, entity table, or projectile
---@return ObjectRef|table|nil resolved
local function resolve_source(obj)
	if not obj then return nil end
	-- If it's a Lua entity table
	if type(obj) == "table" then
		if obj._shooter and obj._shooter.is_valid and obj._shooter:is_valid() then
			return obj._shooter:get_luaentity() or obj._shooter
		end
		if obj.object and obj.object.is_valid and obj.object:is_valid() then
			return obj
		end
		return obj
	end
	-- If it's userdata ObjectRef
	if type(obj) == "userdata" then
		if not obj.is_valid or not obj:is_valid() then return nil end
		if obj.is_player and obj:is_player() then
			return obj
		end
		local ent = obj.get_luaentity and obj:get_luaentity()
		if ent then
			if ent._shooter and ent._shooter.is_valid and ent._shooter:is_valid() then
				return ent._shooter:get_luaentity() or ent._shooter
			end
			return ent
		end
		return obj
	end
	return nil
end

--- Checks if an object or entity reference represents a human player
---@param obj any
---@return boolean
local function is_player_ref(obj)
	return (type(obj) == "userdata" or type(obj) == "table") and obj.is_player and obj:is_player() == true
end

--- Returns the faction set for an entity or player
---@param obj any ObjectRef or mob entity
---@return table<string, boolean> factions Set of active factions
function factions.get_factions(obj)
	local resolved = resolve_source(obj)
	if not resolved then return {} end

	-- Check if player
	if is_player_ref(resolved) then
		return { ["players"] = true }
	end

	-- Lua entity
	if type(resolved) == "table" then
		if resolved.factions then
			return resolved.factions
		end
		if resolved._def and (resolved._def.factions or resolved._def.faction) then
			local set = factions.normalize_factions(resolved._def.factions or resolved._def.faction)
			return set
		end
		-- Fallback to "monsters"
		return { ["monsters"] = true }
	end

	return { ["monsters"] = true }
end

--- Checks whether two entities or players are allies
---@param a any First object, entity, or projectile
---@param b any Second object, entity, or projectile
---@return boolean are_allies True if both entities share allegiance
function factions.are_allies(a, b)
	if not a or not b then return false end
	if a == b then return true end

	local src_a = resolve_source(a)
	local src_b = resolve_source(b)
	if not src_a or not src_b then return false end
	if src_a == src_b then return true end

	local is_player_a = is_player_ref(src_a)
	local is_player_b = is_player_ref(src_b)

	-- Players vs Players
	if is_player_a and is_player_b then
		-- Cooperative alliance between human players
		return true
	end

	-- Player vs Mob
	if is_player_a ~= is_player_b then
		local player_obj = is_player_a and src_a or src_b
		local mob_ent = is_player_a and src_b or src_a
		if type(mob_ent) == "table" then
			-- Tamed / Pet mob check
			if mob_ent.owner and player_obj.get_player_name and mob_ent.owner == player_obj:get_player_name() then
				return true
			end
			if mob_ent.factions and mob_ent.factions["players"] then
				return true
			end
		end
		return false
	end

	-- Mob vs Mob
	local ent_a = src_a
	local ent_b = src_b

	-- 1. Same squad / pack UUID match
	if ent_a.pack_id and ent_b.pack_id and ent_a.pack_id == ent_b.pack_id then
		return true
	end

	-- 2. Same player owner
	if ent_a.owner and ent_b.owner and ent_a.owner == ent_b.owner then
		return true
	end

	-- 3. Intersecting faction tags
	local def_a = ent_a._def
	local def_b = ent_b._def
	local facts_a = ent_a.factions or (def_a and (def_a.factions or def_a.faction) and factions.get_factions(ent_a))
	local facts_b = ent_b.factions or (def_b and (def_b.factions or def_b.faction) and factions.get_factions(ent_b))

	if facts_a and facts_b then
		for f in pairs(facts_a) do
			if facts_b[f] then
				return true
			end
		end
	end

	return false
end

--- Checks whether two entities or players are enemies
---@param a any First object, entity, or projectile
---@param b any Second object, entity, or projectile
---@return boolean are_enemies True if enemies
function factions.are_enemies(a, b)
	return not factions.are_allies(a, b)
end

return factions
