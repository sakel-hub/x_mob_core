--[[
	x_mob_core - Core API Definitions & Subsystem Delegation
	Public namespace table and modular subsystem exports
]]

local modpath = core.get_modpath("x_mob_core")

-- Load type definitions for EmmyLua annotations and static analysis
dofile(modpath .. "/core/types.lua")

---@class x_mob_core
---@field registered_mobs table<string, MobRegistrationDef> Registry of registered mob definitions
---@field registered_spawns SpawnDefinition[] Registry of registered natural spawn rules
---@field utils table Core utilities subsystem
---@field events table Pub-sub event dispatcher subsystem
---@field min_heap MinHeap Binary min-heap priority queue
---@field path_cache table Content ID cache for pathfinding
---@field mob_memory table Short-term mob memory buffer
---@field motor table<string, table> Modular motor subsystems and navigation coordinator
---@field animator table Skeletal animation player
---@field combat table<string, table> Combat calculation and feedback subsystems
---@field spawning table Spawner engine and spawn rule registry
---@field pack table<string, table> Multi-agent squad, coordination, and swarm subsystems
---@field sound SoundSubsystem Audio and sound feedback subsystem
---@field lifecycle table<string, table> Entity registration wrapper and state machine
x_mob_core = {
	registered_mobs = {},
	registered_spawns = {},
}

-- Core utilities and event dispatcher
---@type table Core utilities subsystem (UUID generation, line-of-sight, player vitality)
x_mob_core.utils = dofile(modpath .. "/core/utils.lua")

---@type table Pub-sub event dispatcher subsystem
x_mob_core.events = dofile(modpath .. "/core/events.lua")

-- Navigation & Pathfinding
---@type MinHeap Binary min-heap priority queue
x_mob_core.min_heap = dofile(modpath .. "/navigation/min_heap.lua")

---@type table Pre-cached node content ID registry for zero-overhead pathfinding
x_mob_core.path_cache = dofile(modpath .. "/navigation/path_cache.lua")

---@type table Time-sliced coroutine A* pathfinding engine
x_mob_core.fast_pathfinder = dofile(modpath .. "/navigation/fast_pathfinder.lua")

---@type table Short-term mob memory buffer
x_mob_core.mob_memory = dofile(modpath .. "/navigation/mob_memory.lua")

-- Motor Subsystems & Navigation Coordinator
---@type table<string, table> Modular motor subsystems and navigation coordinator
x_mob_core.motor = {
	node_cache = dofile(modpath .. "/motor/node_cache.lua"),
	doors = dofile(modpath .. "/motor/doors.lua"),
	surface = dofile(modpath .. "/motor/surface.lua"),
	safety = dofile(modpath .. "/motor/safety.lua"),
	locomotion = dofile(modpath .. "/motor/locomotion.lua"),
	ai = dofile(modpath .. "/motor/mob_ai.lua"),
}

-- Animation Subsystem
---@type table Skeletal animation player
x_mob_core.animator = dofile(modpath .. "/animation/animator.lua")

-- Combat Subsystems
---@type table<string, table> Combat calculation, knockback, damage effects, and child detachment subsystems
x_mob_core.combat = {
	damage = dofile(modpath .. "/combat/damage.lua"),
	knockback = dofile(modpath .. "/combat/knockback.lua"),
	effects = dofile(modpath .. "/combat/effects.lua"),
	detachment = dofile(modpath .. "/combat/detachment.lua"),
	loot = dofile(modpath .. "/combat/loot.lua"),
	shooter = dofile(modpath .. "/combat/shooter.lua"),
	factions = dofile(modpath .. "/combat/factions.lua"),
	health_bar = dofile(modpath .. "/combat/health_bar.lua"),
}

-- Spawner Engine
---@type table Natural spawning engine and spawn registry
x_mob_core.spawning = dofile(modpath .. "/spawning/engine.lua")

-- Multi-Agent Pack Coordination & Swarm Intelligence
---@type table<string, table> Multi-agent squad, coordination, and swarm subsystems
x_mob_core.pack = {
	squad = dofile(modpath .. "/pack/squad.lua"),
	coordination = dofile(modpath .. "/pack/coordination.lua"),
	swarm = dofile(modpath .. "/pack/swarm.lua"),
	shoal = dofile(modpath .. "/pack/shoal.lua"),
}

-- Audio & Sound Subsystem
---@type SoundSubsystem
x_mob_core.sound = dofile(modpath .. "/audio/sound.lua")

-- Lifecycle & Entity Registration
---@type table<string, table> Entity registration wrapper and state machine
x_mob_core.lifecycle = {
	state_machine = dofile(modpath .. "/lifecycle/state_machine.lua"),
	entity_wrapper = dofile(modpath .. "/lifecycle/entity_wrapper.lua"),
	environment = dofile(modpath .. "/lifecycle/environment.lua"),
}

---@type table<string, MobRegistrationDef> Registry of all active mob definitions
x_mob_core.registered_mobs = x_mob_core.lifecycle.entity_wrapper.registered_mobs

---@type SpawnDefinition[] Registry of all active natural spawn configurations
x_mob_core.registered_spawns = x_mob_core.spawning.registry.spawns

-- =========================================================================
-- PUBLIC API METHODS
-- =========================================================================

-- Lifecycle & Registration

---Registers a mob definition with standardized physical properties and lifecycle integration.
---@param name string Technical entity name (e.g. "x_mobs:spider")
---@param def MobRegistrationDef Mob specification and callback configuration table
function x_mob_core.register_mob(name, def)
	return x_mob_core.lifecycle.entity_wrapper.register_mob(name, def)
end

---Transitions an entity to a new state machine state, invoking exit and enter hooks.
---@param self table Mob instance
---@param new_state string Target state name
function x_mob_core.transition_to(self, new_state)
	return x_mob_core.lifecycle.state_machine.transition_to(self, new_state)
end

---Sets or updates armor groups on a mob while maintaining engine immortal protection.
---@param self table|ObjectRef Mob entity instance or ObjectRef
---@param groups table<string, number> Armor groups (e.g. { fleshy = 80 })
function x_mob_core.set_armor_groups(self, groups)
	return x_mob_core.lifecycle.entity_wrapper.set_armor_groups(self, groups)
end

---Registers an extensible step middleware hook into the mob execution pipeline.
---@param name string Unique hook identifier
---@param priority integer Execution order (lower runs first)
---@param handler fun(self: table, dtime: number, def: table, moveresult?: table): boolean|nil
function x_mob_core.register_step_hook(name, priority, handler)
	return x_mob_core.lifecycle.entity_wrapper.pipeline.register_step_hook(name, priority, handler)
end

---Unregisters a previously registered step middleware hook.
---@param name string
function x_mob_core.unregister_step_hook(name)
	return x_mob_core.lifecycle.entity_wrapper.pipeline.unregister_step_hook(name)
end

-- Spawner Engine

---Registers a mob definition for natural map generation and environment spawning.
---@param mob_name string Registered entity technical name (e.g. "x_mobs:spider")
---@param def SpawnConfig|SpawnDefinition Environmental spawning parameters and condition filters
function x_mob_core.register_spawn(mob_name, def)
	return x_mob_core.spawning.registry.register_spawn(mob_name, def)
end

---Spawns a cohesive group of mobs scattered safely around a center point according to a spawn definition.
---@param spawn_pos Vector World center position
---@param def SpawnDefinition|table|string Spawn definition table or entity technical name
---@param source? string Optional spawner mechanism identifier (default: "Custom Spawning")
---@return integer count Number of mobs successfully spawned
function x_mob_core.spawn_mob_group(spawn_pos, def, source)
	local spawn_def = def
	if type(def) == "string" then
		spawn_def = {mob_name = def, group_min = 1, group_max = 1}
	end
	return x_mob_core.spawning.spawn_mob_group(spawn_pos, spawn_def, source or "Custom Spawning")
end

---Spawns a single mob entity with action logging and returns the object reference.
---@param pos Vector Spawn world position
---@param mob_name string Registered mob technical name
---@param staticdata? string Optional serialized staticdata
---@return ObjectRef|nil obj Spawned entity ObjectRef or nil on failure
function x_mob_core.spawn_mob(pos, mob_name, staticdata)
	local obj = core.add_entity(pos, mob_name, staticdata)
	if obj then
		core.log("action", string.format("[x_mob_core] [Manual Spawning] Spawned 1 %s at %s",
			mob_name, core.pos_to_string(vector.round(pos))))
	end
	return obj
end


-- Animation Subsystem

---Dispatches skeletal animation to an object using glTF tracks with fallback to legacy frame ranges.
---@param obj ObjectRef Target entity ObjectRef
---@param track_name string Named glTF animation track identifier
---@param params? AnimationParams Playback options (speed, loop, blend, priority, force)
---@return boolean success Whether animation playback was successfully dispatched
function x_mob_core.play_animation(obj, track_name, params)
	return x_mob_core.animator.play(obj, track_name, params)
end

---Stops current animation tracks on an ObjectRef.
---@param obj ObjectRef Target entity ObjectRef
---@param track_name? string Optional specific track to stop
function x_mob_core.stop_animation(obj, track_name)
	return x_mob_core.animator.stop(obj, track_name)
end

-- Combat Subsystems

---Universal combat punch intake handler applying damage, threat, knockback, and death callbacks.
---@param self table Mob entity instance
---@param puncher? ObjectRef Attacking entity
---@param time_from_last_punch? number Elapsed time in seconds
---@param tool_capabilities? table Weapon capabilities
---@param dir? Vector Punch impulse direction
---@param damage? number Base damage override
---@param def? table Entity definition table
---@return boolean handled
function x_mob_core.handle_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def)
	return x_mob_core.lifecycle.entity_wrapper.combat_handler.handle_punch(
		self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def
	)
end

---Calculates damage from tool capabilities and mob armor groups, and applies wear to weapon.
---@param self table Mob entity instance
---@param puncher? ObjectRef Punching entity
---@param time_from_last_punch? number Time since last punch in seconds
---@param tool_capabilities? table Wielded tool capabilities
---@param dir? Vector Punch direction vector
---@param damage_override? number Direct damage override
---@return number dmg Calculated damage integer
function x_mob_core.calculate_punch_damage(self, puncher, time_from_last_punch, tool_capabilities, dir, damage_override)
	return x_mob_core.combat.damage.calculate_punch_damage(
		self, puncher, time_from_last_punch, tool_capabilities, dir, damage_override
	)
end

---Dampens punch knockback when an entity is struck inside water.
---@param self table Mob entity instance
function x_mob_core.dampen_water_knockback(self)
	return x_mob_core.combat.knockback.dampen_water_knockback(self)
end

---Returns the effective knockback multiplier for an ObjectRef or LuaEntity.
---@param obj ObjectRef|table Target object or mob entity
---@return number multiplier (1.0 for players, mob-defined knockback_mult, or 1.0 default)
function x_mob_core.get_knockback_mult(obj)
	return x_mob_core.combat.knockback.get_multiplier(obj)
end

---Checks whether two entities or players are allies according to faction and pack rules.
---@param a any First object, entity, or projectile
---@param b any Second object, entity, or projectile
---@return boolean are_allies True if both entities share allegiance
function x_mob_core.are_allies(a, b)
	return x_mob_core.combat.factions.are_allies(a, b)
end

---Checks whether two entities or players are enemies.
---@param a any First object, entity, or projectile
---@param b any Second object, entity, or projectile
---@return boolean are_enemies True if enemies
function x_mob_core.are_enemies(a, b)
	return x_mob_core.combat.factions.are_enemies(a, b)
end

---Returns the active faction set for an entity or player.
---@param obj any ObjectRef or mob entity
---@return table<string, boolean> factions Set of active factions
function x_mob_core.get_factions(obj)
	return x_mob_core.combat.factions.get_factions(obj)
end

---Flashes the entity red briefly upon taking damage for visual feedback.
---@param obj ObjectRef Entity object to flash
function x_mob_core.indicate_damage(obj)
	return x_mob_core.combat.effects.indicate_damage(obj)
end

---Clears any active damage flash on an entity, restoring its clean base texture modifier.
---@param obj ObjectRef Entity object
function x_mob_core.clear_damage(obj)
	return x_mob_core.combat.effects.clear_damage(obj)
end

---Strips transient damage flash colorize modifiers from a texture modifier string.
---@param mod? string Original texture modifier string
---@return string clean_mod Texture modifier without damage colorize
function x_mob_core.strip_damage_mod(mod)
	return x_mob_core.combat.effects.strip_damage_mod(mod)
end

---Flashes the entity with a visible texture overlay (white by default) upon health regeneration.
---@param obj ObjectRef Entity object to flash
---@param color? string Optional custom colorize string (default: "^[colorize:#FFFFFF60")
---@param duration? number Optional duration in seconds (default: 0.25)
function x_mob_core.indicate_regen(obj, color, duration)
	return x_mob_core.combat.effects.indicate_regen(obj, color, duration)
end

---Clears any active health regeneration flash on an entity, restoring its clean base texture modifier.
---@param obj ObjectRef Entity object
function x_mob_core.clear_regen(obj)
	return x_mob_core.combat.effects.clear_regen(obj)
end

---Strips transient health regeneration flash colorize modifiers from a texture modifier string.
---@param mod? string Original texture modifier string
---@return string clean_mod Texture modifier without regen colorize
function x_mob_core.strip_regen_mod(mod)
	return x_mob_core.combat.effects.strip_regen_mod(mod)
end

---Strips all transient combat damage and health regeneration flash colorize modifiers.
---@param mod? string Original texture modifier string
---@return string clean_mod Texture modifier without damage or regen colorize
function x_mob_core.strip_flash_mod(mod)
	return x_mob_core.combat.effects.strip_flash_mod(mod)
end

---Spawns directional combat damage particles according to mob settings or global preferences.
---@param obj ObjectRef Entity receiving damage
---@param puncher? ObjectRef Attacker ObjectRef
---@param dir? Vector Strike/knockback direction vector
---@param damage? number Damage dealt
---@param def? table Entity definition table
function x_mob_core.spawn_damage_particles(obj, puncher, dir, damage, def)
	return x_mob_core.combat.effects.spawn_damage_particles(obj, puncher, dir, damage, def)
end

---Detaches and drops all attached child objects (arrows, passengers, accessories) from a mob when it dies.
---@param mob_obj ObjectRef The mob entity ObjectRef
function x_mob_core.detach_attached_children(mob_obj)
	return x_mob_core.combat.detachment.detach_attached_children(mob_obj)
end

---Predicts target intercept position and direction based on target velocity and projectile speed.
---@param origin Vector Projectile launch origin
---@param tgt_pos Vector Current target position
---@param tgt_vel? Vector Target velocity vector
---@param proj_speed number Projectile travel speed
---@return Vector predicted_pos Predicted intercept position
---@return Vector dir Normalized direction vector towards predicted position
function x_mob_core.predict_aim(origin, tgt_pos, tgt_vel, proj_speed)
	return x_mob_core.combat.shooter.predict_aim(origin, tgt_pos, tgt_vel, proj_speed)
end

---Validates whether an object is a targetable enemy for a projectile or shooter mob.
---Filters out dropped items (__builtin:item), falling nodes, utility entities, shooter self-hits, and allies.
---@param source_or_proj ObjectRef|table Projectile entity instance, shooter mob, or ObjectRef
---@param obj ObjectRef Target object to test
---@param options? ProjectileTargetOptions Optional configuration table
---@return boolean is_valid True if target is attackable, false if ignored
function x_mob_core.is_valid_projectile_target(source_or_proj, obj, options)
	return x_mob_core.combat.shooter.is_valid_target(source_or_proj, obj, options)
end

---Processes a standard projectile flight step: ballistics rotation, lifetime expiry,
---continuous raycasting, proximity collision, and impact handling.
---@param self table Projectile LuaEntity instance
---@param dtime number Step delta time
---@param options? ProjectileStepOptions Projectile configuration options
---@return boolean hit True if the projectile impacted an object or solid node
---@return ObjectRef|nil hit_obj Direct object impacted, if any
---@return Vector|nil hit_pos World coordinate of the impact
function x_mob_core.step_projectile(self, dtime, options)
	return x_mob_core.combat.shooter.step_projectile(self, dtime, options)
end

---Agnostically checks whether a LuaEntity is classified as a projectile or arrow.
---@param ent table LuaEntity table
---@return boolean is_projectile
function x_mob_core.is_projectile(ent)
	return x_mob_core.combat.shooter.is_projectile(ent)
end

-- Loot & Item Drops

---Spawns a single item with a physical parabolic launch arc.
---@param origin Vector World coordinate of spawn origin
---@param itemstack ItemStack|string Item or ItemStack to drop
---@param angle? number Launch azimuth in radians
---@param options? DropOptions Physics and effect overrides
---@return ObjectRef|nil item_obj Spawned item entity or nil
function x_mob_core.drop_item(origin, itemstack, angle, options)
	return x_mob_core.combat.loot.drop_item(origin, itemstack, angle, options)
end

---Evaluates a declarative drop table and launches all dropped items in a radial fountain.
---@param origin Vector World coordinate of spawn origin
---@param drops (DropEntryDef|string)[] List of drop table entries
---@param options? DropOptions Physics, particle, and sound overrides
---@return ObjectRef[] spawned_objects List of successfully spawned item ObjectRefs
function x_mob_core.drop_items(origin, drops, options)
	return x_mob_core.combat.loot.drop_items(origin, drops, options)
end

-- Combat Health Bar Subsystem

---Displays or updates the dynamic overhead health bar on a mob entity.
---@param self table Mob entity instance
---@param cur_hp? number Current health (defaults to self.hp)
---@param max_hp? number Maximum health (defaults to self.hp_max)
---@return boolean shown True if health bar is shown or updated
function x_mob_core.show_health_bar(self, cur_hp, max_hp)
	local hp = cur_hp or self.hp
	local max = max_hp or self.hp_max
	return x_mob_core.combat.health_bar.show(self, hp, max, self._def)
end

---Hides or removes the dynamic overhead health bar on a mob entity.
---@param self table Mob entity instance
---@param remove_completely? boolean If true, destroys child entity; otherwise sets is_visible = false
function x_mob_core.hide_health_bar(self, remove_completely)
	if remove_completely then
		x_mob_core.combat.health_bar.remove(self)
	else
		x_mob_core.combat.health_bar.hide(self)
	end
end

---Forces an update of the health bar based on current mob HP.
---@param self table Mob entity instance
---@return boolean shown True if health bar was updated
function x_mob_core.update_health_bar(self)
	return x_mob_core.show_health_bar(self)
end

-- Motor & Steering Controller

---Executes tactical retreat steering away from a target position.
---@param self table Entity instance
---@param target_pos Vector World position to flee from
---@param speed? number Movement speed multiplier
---@return boolean is_retreating Whether retreat movement is actively executing
function x_mob_core.retreat_from(self, target_pos, speed)
	return x_mob_core.motor.locomotion.retreat_from(self, target_pos, speed)
end

---Scans for living players within radius using field of view and raycast line-of-sight checks.
---@param self table Entity instance
---@param scan_radius? number Detection radius in nodes
---@param eye_height? number Vertical eye offset
---@return ObjectRef|nil player Nearest visible living player or nil
function x_mob_core.scan_for_player(self, scan_radius, eye_height)
	return x_mob_core.motor.ai.scan_for_player(self, scan_radius, eye_height)
end

---Advances ambient idle or wandering locomotion state for an entity.
---@param self table Entity instance
---@param dtime number Step delta time
---@param walk_anim? string Walking animation track name
---@param idle_anim? string Idle animation track name
---@return boolean is_moving Whether the mob is currently walking
function x_mob_core.step_wander_or_idle(self, dtime, walk_anim, idle_anim)
	return x_mob_core.motor.ai.step_wander_or_idle(self, dtime, walk_anim, idle_anim)
end

---Advances directional steering locomotion towards destination or target entity.
---@param self table Entity instance
---@param dtime number Step delta time
---@param move_anim? string Movement animation track name
---@param anim_speed? number Animation speed multiplier
---@param idle_anim? string Idle animation track name
---@return boolean is_moving Whether the mob is actively moving
function x_mob_core.step_move_or_idle(self, dtime, move_anim, anim_speed, idle_anim)
	return x_mob_core.motor.ai.step_move_or_idle(self, dtime, move_anim, anim_speed, idle_anim)
end

---Halts horizontal velocity of a mob entity while preserving vertical motion/gravity and liquid buoyancy.
---@param self table Entity instance
function x_mob_core.halt_horizontal_velocity(self)
	return x_mob_core.motor.locomotion.halt_horizontal_velocity(self)
end

---Checks if an entity is an aquatic mob (fish, shoal, etc.) that swims freely in liquid.
---@param self table Entity instance
---@return boolean is_aquatic
function x_mob_core.is_aquatic_mob(self)
	return x_mob_core.motor.safety.is_aquatic_mob(self)
end

---Finds the nearest dry walkable shoreline node adjacent to water within max_radius.
---@param pos Vector Starting position (usually in water)
---@param max_radius? number Maximum search radius in blocks (default: 16)
---@return Vector|nil shore_pos Nearest dry shore coordinate, or nil if none found
function x_mob_core.find_nearest_shore_pos(pos, max_radius)
	return x_mob_core.motor.safety.find_nearest_shore_pos(pos, max_radius)
end


-- Navigation & Pathfinding

---Queues an asynchronous time-sliced coroutine A* path search with a strict 1.5ms per-tick CPU budget.
---@param start_pos Vector Starting world position
---@param target_pos Vector Target world position
---@param abilities? MobMovementDef Locomotion and traversal abilities (swim, climb, doors)
---@param callback PathfindingCallback Function invoked when path search completes
---@param mob_height? number Vertical clearance in nodes (default: 2)
function x_mob_core.find_path(start_pos, target_pos, abilities, callback, mob_height)
	return x_mob_core.fast_pathfinder.find_path(start_pos, target_pos, abilities, callback, mob_height)
end

---Executes a synchronous A* path search.
---@param start_pos Vector Starting world position
---@param target_pos Vector Target world position
---@param abilities? MobMovementDef Locomotion and traversal abilities (swim, climb, doors)
---@param mob_height? number Vertical clearance in nodes (default: 2)
---@return Vector[]|nil path Solved waypoint path array or nil if unreachable
function x_mob_core.find_path_sync(start_pos, target_pos, abilities, mob_height)
	return x_mob_core.fast_pathfinder.find_path_sync(start_pos, target_pos, abilities, mob_height)
end

-- Multi-Agent Pack Coordination

---Handles locomotion for a follower returning to assemble with its pack leader.
---@param self table Follower mob instance
---@param dtime number Step delta time
---@param move_anim? string Movement animation (default: "walk")
---@param speed_mult? number Speed multiplier (default: 1.25)
---@return boolean is_regrouping True if still actively regrouping, false if reached leader or leader lost
function x_mob_core.step_regroup(self, dtime, move_anim, speed_mult)
	return x_mob_core.pack.coordination.step_regroup(self, dtime, move_anim, speed_mult)
end

---Broadcasts threat alert to nearby pack members or allies within radius.
---@param pos Vector Center position to broadcast threat from
---@param radius? number Alert radius in nodes (default: 16.0)
---@param target ObjectRef Threat target to engage
---@param max_allies? integer Max allies to alert (default: 4)
function x_mob_core.alert_nearby_allies(pos, radius, target, max_allies)
	local fake_self = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return pos end,
		},
		name = "generic_caller",
	}
	return x_mob_core.pack.coordination.broadcast_threat(fake_self, target, radius, max_allies)
end

---Checks if a follower has exceeded its leash distance from its leader.
---@param follower_self table Follower mob instance
---@return boolean is_leashed True if within leash limit, false if leashed/separated
---@return Vector|nil leader_pos Position of leader if valid
---@return number dist Distance to leader
function x_mob_core.check_leash(follower_self)
	return x_mob_core.pack.coordination.check_leash(follower_self)
end

---Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy.
---@param self table Mob instance
---@param target ObjectRef Threat target
---@param radius? number Alert radius in nodes (default: 16.0)
---@param max_allies? integer Max allies to alert (default: 4)
function x_mob_core.broadcast_threat(self, target, radius, max_allies)
	return x_mob_core.pack.coordination.broadcast_threat(self, target, radius, max_allies)
end

---Rallies all pack followers to attack a shared target.
---@param leader_self table Leader mob instance
---@param target ObjectRef Target entity
function x_mob_core.rally_followers(leader_self, target)
	return x_mob_core.pack.coordination.rally_followers(leader_self, target)
end

---Cleans invalid or dead follower objects from a leader's roster and returns alive count.
---@param leader_self table Leader mob instance
---@return integer count Alive follower count
---@return table alive_followers Array of living follower ObjectRefs
function x_mob_core.clean_followers(leader_self)
	return x_mob_core.pack.squad.clean_followers(leader_self)
end

---Searches nearby area to adopt orphans or re-link separated followers.
---@param leader_self table Leader mob instance
---@param search_radius? number Radius to search in nodes (default: 32.0)
function x_mob_core.adopt_nearby_orphans(leader_self, search_radius)
	return x_mob_core.pack.squad.adopt_nearby_orphans(leader_self, search_radius)
end

---Registers a follower under a pack leader.
---@param leader_self table Leader mob instance
---@param follower_obj ObjectRef Follower entity object
---@param force? boolean If true, bypasses max_followers capacity limit (default: false)
---@return boolean added True if follower was newly registered, false if already present, full, or invalid
function x_mob_core.add_follower(leader_self, follower_obj, force)
	return x_mob_core.pack.squad.add_follower(leader_self, follower_obj, force)
end

---Removes a follower object from a leader's roster.
---@param leader_self table Leader mob instance
---@param follower_obj ObjectRef Follower entity object
function x_mob_core.remove_follower(leader_self, follower_obj)
	return x_mob_core.pack.squad.remove_follower(leader_self, follower_obj)
end

---Disbands the pack and notifies all followers when the leader dies.
---@param leader_self table Leader mob instance
function x_mob_core.handle_leader_death(leader_self)
	return x_mob_core.pack.squad.handle_leader_death(leader_self)
end

---Adopts nearby orphans and spawns missing followers radially around the leader.
---@param leader_self table Leader mob instance
---@param follower_type? string Entity technical name (default: leader_self.pack_follower_type)
---@param max_count? integer Target follower count (default: leader_self.pack_max_followers or 3)
---@param spawn_radius? number Radial spawn distance (default: 1.5)
function x_mob_core.spawn_initial_followers(leader_self, follower_type, max_count, spawn_radius)
	return x_mob_core.pack.squad.spawn_initial_followers(leader_self, follower_type, max_count, spawn_radius)
end

---Follower searches nearby area to re-link with its pack leader if separated.
---@param follower_self table Follower mob instance
---@param search_radius? number Radius to search in nodes (default: 32.0)
function x_mob_core.relink_follower(follower_self, search_radius)
	return x_mob_core.pack.squad.relink_follower(follower_self, search_radius)
end

-- Swarm Intelligence & Flocking

---Calculates 3D Boids spatial separation with horizontal anti-stacking bias.
---@param self table Mob instance
---@param pos Vector World position
---@param radius? number Repulsion radius (default: 2.2)
---@param strength? number Push force multiplier (default: 2.8)
---@param horizontal_bias? boolean If true, prevents vertical totem pole stacking (default: true)
---@return number sep_x
---@return number sep_y
---@return number sep_z
function x_mob_core.calculate_repulsion(self, pos, radius, strength, horizontal_bias)
	return x_mob_core.pack.coordination.calculate_repulsion(self, pos, radius, strength, nil, nil, nil, horizontal_bias)
end

---Democratic leader election: surviving pack, swarm, or shoal members elect the first surviving peer as new leader.
---@param self table Mob instance
---@param search_radius? number Radius to search for surviving mates (default: 24.0)
---@return boolean success True if a new leader was established
function x_mob_core.elect_successor(self, search_radius)
	return x_mob_core.pack.squad.elect_successor(self, search_radius)
end

---Advances master swarm AI step (flocking when idle, vortex and dive-bombs in combat).
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function x_mob_core.step_swarm(self, dtime, def)
	return x_mob_core.pack.swarm.step(self, dtime, def)
end

---Advances ambient swarm flocking locomotion.
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function x_mob_core.step_flock(self, dtime, def)
	return x_mob_core.pack.swarm.step_flock(self, dtime, def)
end

---Advances coordinated swarm combat locomotion (vortex holding pattern and dive-bomb runs).
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function x_mob_core.step_swarm_combat(self, dtime, def)
	return x_mob_core.pack.swarm.step_combat(self, dtime, def)
end

-- Audio & Sound

---Plays a configured sound type for a mob instance with positional audio and pitch variation.
---@param self table|userdata Mob entity instance or ObjectRef
---@param sound_type string Category ("hurt", "death", "random", "attack", "alert") or technical sound name
---@param overrides? table Optional overrides (gain, distance, pitch, pos, object, to_player, loop)
---@return integer|nil sound_handle Luanti sound handle or nil if not played
function x_mob_core.play_sound(self, sound_type, overrides)
	return x_mob_core.sound.play(self, sound_type, overrides)
end

---Stops a playing sound handle.
---@param handle? integer Luanti sound handle returned by play_sound or core.sound_play
function x_mob_core.stop_sound(handle)
	x_mob_core.sound.stop(handle)
end

-- Core Utilities & Event Bus

---Generates an RFC 4122 Version 4 compliant UUID.
---Uses Luanti OS-backed SecureRandom for guaranteed uniqueness, with math.random fallback.
---@return string uuid
function x_mob_core.generate_uuid()
	return x_mob_core.utils.generate_uuid()
end

---Performs an unobstructed line of sight check between two points using Raycast.
---@param p1 Vector Starting position
---@param p2 Vector Ending position
---@return boolean is_clear True if ray has no solid node obstruction
function x_mob_core.line_of_sight(p1, p2)
	return x_mob_core.utils.line_of_sight(p1, p2)
end

---Checks if an ObjectRef is a connected living player or valid entity with HP > 0.
---@param target ObjectRef Target entity or player ObjectRef
---@return boolean is_alive True if reference is valid and alive
function x_mob_core.is_player_alive(target)
	return x_mob_core.utils.is_player_alive(target)
end

---Finds the topmost solid ground surface near a given coordinate.
---@param pos Vector Position to check
---@param max_down? number Maximum distance to search downwards (default: 8)
---@param max_up? number Maximum distance to search upwards (default: 3)
---@param walkable_only? boolean If true, requires walkable non-liquid node with headroom (default: true)
---@return number|nil ground_y Top surface height of highest ground node, or nil
function x_mob_core.get_ground_y(pos, max_down, max_up, walkable_only)
	return x_mob_core.utils.get_ground_y(pos, max_down, max_up, walkable_only)
end

---Picks a ground-anchored wander waypoint near current position over solid walkable nodes.
---@param current_pos Vector Current mob world position
---@param origin? Vector Center origin of wander boundary (default: current_pos)
---@param radius? number Maximum wander radius from origin (default: 10.0)
---@param min_dist? number Minimum step distance from current position (default: 3.0)
---@param max_dist? number Maximum step distance from current position (default: 7.5)
---@param hover_offset? number Vertical offset above detected ground (default: 1.4)
---@return Vector|nil waypoint Ground-anchored target position or nil
function x_mob_core.pick_ground_waypoint(current_pos, origin, radius, min_dist, max_dist, hover_offset)
	return x_mob_core.utils.pick_ground_waypoint(current_pos, origin, radius, min_dist, max_dist, hover_offset)
end

---Scans vertically upwards from origin to check distance to the first solid ceiling node.
---@param origin Vector Base position (e.g. foot or center coordinate)
---@param max_check? number Maximum nodes to scan upward (default: 4.0)
---@return number headroom Distance to first walkable ceiling node, or max_check if open sky
function x_mob_core.get_headroom(origin, max_check)
	return x_mob_core.utils.get_headroom(origin, max_check)
end

---Verifies if a target coordinate is safely in passable air; if blocked, returns an adjusted clear position.
---@param target_pos Vector Desired 3D coordinate
---@param safe_origin Vector Known safe origin or anchor (e.g. player or mob origin)
---@param look_dir? Vector Optional directional vector to tuck behind if in tight enclosure
---@return Vector clear_pos Adjusted safe 3D coordinate
function x_mob_core.avoid_solid_nodes(target_pos, safe_origin, look_dir)
	return x_mob_core.utils.avoid_solid_nodes(target_pos, safe_origin, look_dir)
end

---Finds the top surface Y coordinate of the solid walkable ground below a given 3D position.
---@param x number X world coordinate
---@param start_y number Y world coordinate
---@param z number Z world coordinate
---@param max_down? number Maximum distance to search downwards (default: 36)
---@return number|nil ground_y Top surface Y of solid node, or nil if none found
function x_mob_core.find_ground_level(x, start_y, z, max_down)
	return x_mob_core.utils.find_ground_level(x, start_y, z, max_down)
end

---Schedules an action to be executed in the future on the mob's timer.
---Unlike `core.after`, scheduled actions are automatically tied to the mob's existence
---and will safely cancel if the mob dies, despawns, or transitions into a flinching state.
---@param self table Mob entity reference
---@param delay number Time in seconds
---@param tag string Identifier string, useful for cancellation or debugging
---@param callback function The function to execute, taking `self` as argument
function x_mob_core.schedule(self, delay, tag, callback)
	if not self._scheduled_actions then self._scheduled_actions = {} end
	table.insert(self._scheduled_actions, {
		timer = delay,
		tag = tag,
		callback = callback
	})
end

---Cancels scheduled actions by tag.
---@param self table Mob entity reference
---@param tag string The tag to cancel
function x_mob_core.cancel_scheduled(self, tag)
	if not self._scheduled_actions then return end
	for i = #self._scheduled_actions, 1, -1 do
		if self._scheduled_actions[i].tag == tag then
			table.remove(self._scheduled_actions, i)
		end
	end
end

---Clears all scheduled actions for the mob.
---@param self table Mob entity reference
function x_mob_core.clear_scheduled(self)
	self._scheduled_actions = {}
end

---Registers an event listener callback on the x_mob_core pub-sub event bus.
---@param event_name CoreEventName|string Event identifier (e.g. "on_mob_death", "on_mob_spawn", "on_mob_target")
---@param callback EventListenerCallback Callback function invoked when event is emitted
---@return integer id Listener registration token
function x_mob_core.listen(event_name, callback)
	return x_mob_core.events.listen(event_name, callback)
end

---Unregisters an event listener from the x_mob_core pub-sub event bus.
---@param event_name CoreEventName|string Event identifier
---@param id integer Listener registration token returned by listen()
---@return boolean success True if listener was found and removed
function x_mob_core.unlisten(event_name, id)
	return x_mob_core.events.unlisten(event_name, id)
end

---Emits an event to all registered listeners on the x_mob_core pub-sub event bus.
---@param event_name CoreEventName|string Event identifier
---@param ... any Arguments passed to listeners
function x_mob_core.emit(event_name, ...)
	return x_mob_core.events.emit(event_name, ...)
end

---Sets a mob's target and emits the on_mob_target event if changed.
---@param self table Mob entity instance
---@param target ObjectRef|nil Target entity or player
---@return boolean changed True if target changed
function x_mob_core.set_target(self, target)
	return x_mob_core.lifecycle.entity_wrapper.set_target(self, target)
end

---Sets a mob's active texture variation by index.
---@param self table|ObjectRef Mob entity instance or ObjectRef
---@param id integer Texture variation index
---@param variations? table[] Optional explicit variations list
---@return string[]|nil applied The applied textures array
function x_mob_core.set_texture(self, id, variations)
	return x_mob_core.lifecycle.entity_wrapper.set_texture(self, id, variations)
end

return x_mob_core
