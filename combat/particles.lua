--[[
	x_mob_core - Combat & Visual FX Particles Subsystem
	Attached particle spawner lifecycle management, in-memory session tracking,
	selective packet scoping, and disconnect/death cleanup.
]]

---@class ParticlesSubsystem
local particles = {}

local modpath = core.get_modpath("x_mob_core")
local utils = dofile(modpath .. "/core/utils.lua")

-- In-memory session registry: key -> map<spawner_id, { id: integer, playername?: string }>
local active_spawners = {}

--- Resolves stable in-memory session key for a target ObjectRef
---@param target ObjectRef Target player or entity
---@return string? key Unique session key
local function get_target_key(target)
	if not target or not target:is_valid() then return nil end
	if target:is_player() then
		return "player:" .. target:get_player_name()
	end
	local ent = target:get_luaentity()
	if ent then
		if not ent._x_mob_id then
			ent._x_mob_id = "entity:" .. utils.generate_uuid()
		end
		return ent._x_mob_id
	end
	return nil
end

--- Attaches an ongoing or burst particle spawner to a target ObjectRef
---@param target ObjectRef Target player or entity to attach particles to
---@param def table Particle spawner definition table
---@param playername? string Optional player name for selective packet scoping
---@return integer|nil spawner_id Numerical particle spawner identifier, or nil
function particles.attach(target, def, playername)
	if not target or not target:is_valid() or type(def) ~= "table" then
		return nil
	end

	local key = get_target_key(target)
	if not key then return nil end

	local spawner_def = utils.shallow_copy(def)
	spawner_def.attached = target
	spawner_def.time = def.time or 0 -- 0 = infinite continuous spawner

	-- Disable expensive client-side voxel raycasting by default for aura/attached FX
	if spawner_def.collisiondetection == nil then
		spawner_def.collisiondetection = false
	end

	-- Apply selective packet scoping if requested
	local scoped_player = playername or def.playername
	if scoped_player and scoped_player ~= "" then
		spawner_def.playername = scoped_player
	end

	local spawner_id = core.add_particlespawner(spawner_def)
	if spawner_id then
		active_spawners[key] = active_spawners[key] or {}
		active_spawners[key][spawner_id] = {
			id = spawner_id,
			playername = spawner_def.playername,
		}
	end

	return spawner_id
end

--- Safely deletes an active particle spawner for a target
---@param target ObjectRef Target player or entity
---@param spawner_id integer Particle spawner identifier
---@param playername? string Optional player name if spawner was scoped
---@return boolean success True if spawner was tracked and deleted
function particles.delete(target, spawner_id, playername)
	if not spawner_id then return false end

	local key = target and get_target_key(target)
	local scoped_name = playername

	if key and active_spawners[key] and active_spawners[key][spawner_id] then
		scoped_name = scoped_name or active_spawners[key][spawner_id].playername
		active_spawners[key][spawner_id] = nil
		if not next(active_spawners[key]) then
			active_spawners[key] = nil
		end
	end

	if scoped_name and scoped_name ~= "" then
		core.delete_particlespawner(spawner_id, scoped_name)
	else
		core.delete_particlespawner(spawner_id)
	end
	return true
end

--- Clears and deletes all active particle spawners for a given target
---@param target ObjectRef Target player or entity
function particles.clear_target(target)
	if not target then return end
	local key = get_target_key(target)
	if not key or not active_spawners[key] then return end

	for spawner_id, record in pairs(active_spawners[key]) do
		if record.playername and record.playername ~= "" then
			core.delete_particlespawner(spawner_id, record.playername)
		else
			core.delete_particlespawner(spawner_id)
		end
	end
	active_spawners[key] = nil
end

--- Retrieves all active spawner records for a given target
---@param target ObjectRef Target player or entity
---@return table<integer, { id: integer, playername?: string }>? spawners
function particles.get_target_spawners(target)
	if not target then return nil end
	local key = get_target_key(target)
	if not key then return nil end
	return active_spawners[key]
end

-- ============================================================================
-- LIFECYCLE LISTENERS
-- ============================================================================

core.register_on_leaveplayer(function(player)
	particles.clear_target(player)
end)

core.register_on_dieplayer(function(player)
	particles.clear_target(player)
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		particles.clear_target(player)
	end
end)

x_mob_core.particles = particles

return particles
