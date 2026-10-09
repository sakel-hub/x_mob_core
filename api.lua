--[[
	x_mob_core - Core API Definitions & Subsystem Delegation
	Public namespace table and modular subsystem exports
]]

local modpath = core.get_modpath("x_mob_core")

-- Load type definitions for EmmyLua annotations and static analysis
dofile(modpath .. "/core/types.lua")

---@class x_mob_core
---@field registered_mobs table<string, MobRegistrationDef> Registry of registered mob definitions
---@field registered_spawns MobSpawnDef[] Registry of registered natural spawn rules
---@field utils UtilsSubsystem Core utilities subsystem
---@field events EventsSubsystem Pub-sub event dispatcher subsystem
---@field min_heap MinHeap Binary min-heap priority queue
---@field path_cache PathCacheSubsystem Content ID cache for pathfinding
---@field fast_pathfinder FastPathfinder Time-sliced coroutine A* pathfinding engine
---@field mob_memory MobMemoryState Short-term mob memory buffer
---@field motor MobMotorSubsystems Modular motor subsystems and navigation coordinator
---@field animator AnimatorSubsystem Skeletal animation player
---@field combat MobCombatSubsystems Combat calculation and feedback subsystems
---@field status_effects StatusEffectsSubsystem Status effects, buffs, and debuffs subsystem
---@field spawning SpawnerSubsystem Spawner engine and spawn rule registry
---@field pack MobPackSubsystems Multi-agent squad, coordination, and swarm subsystems
---@field sound SoundSubsystem Audio and sound feedback subsystem
---@field lifecycle MobLifecycleSubsystems Entity registration wrapper and state machine
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
	melee = dofile(modpath .. "/combat/melee.lua"),
	shooter = dofile(modpath .. "/combat/shooter.lua"),
	factions = dofile(modpath .. "/combat/factions.lua"),
	health_bar = dofile(modpath .. "/combat/health_bar.lua"),
	particles = dofile(modpath .. "/combat/particles.lua"),
	envelop = dofile(modpath .. "/combat/envelop.lua"),
	hunger_adapter = dofile(modpath .. "/combat/hunger_adapter.lua"),
	hud_effects = dofile(modpath .. "/combat/hud_effects.lua"),
	status_effects = dofile(modpath .. "/combat/status_effects.lua"),
}

---@type table Status effects, buffs, and debuffs subsystem
x_mob_core.status_effects = x_mob_core.combat.status_effects

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

---@type MobSpawnDef[] Registry of all active natural spawn configurations
x_mob_core.registered_spawns = x_mob_core.spawning.registry.spawns

-- =========================================================================
-- PUBLIC API METHODS
-- =========================================================================

-- Lifecycle & Registration

---Registers a mob definition with standardized physical properties and lifecycle integration.
---
---### Key Configuration Attributes & Mutual Exclusivity Rules:
---- **Locomotion Archetypes (`is_floating`, `is_aquatic`, `amphibious`)**:
---  - `is_floating = true`: Mob hovers in mid-air or liquid with zero gravity. Node step-up, ground clinging,
---    and fall damage are completely bypassed.
---  - `is_aquatic = true`: Mob is strictly aquatic. Submerged swimming is enabled, but dry-land pathfinding
---    is disabled and mob suffocates when beached (unless `amphibious = true`).
---  - `amphibious = true`: Mob breathes freely both in liquid and on dry land, disabling both drowning
---    and beach suffocation.
---  - `can_climb = true`: Allows ascending vertical climbable nodes (ladders, vines).
---  - `can_open_doors = true`: Mob automatically opens wooden doors obstructing its path.
---- **Combat Pipelines (`custom_step`, `melee`, `shooter`)**:
---  - `custom_step`: Priority 15 middleware hook. Returning `true` **intercepts** execution, completely skipping
---    declarative `melee` and `shooter` combat routines for custom spells, charges, or channeled actions.
---  - `melee = false`: Completely disables built-in melee attacks and reach calculations.
---  - `shooter = false`: Completely disables ranged attack targeting, aim prediction, kiting, and projectile firing.
---  - When `melee.aoe = true`: Targets all hostile entities within `attack_range`; single-target reach and aim
---    tolerances are ignored.
---- **Health, Fleeing & Regeneration**:
---  - `can_flee = false`: Completely suppresses low-HP fleeing regardless of `flee_threshold` or `flee_ratio`.
---  - `unlimited_flee = true`: Keeps mob permanently in retreat once triggered; passive health regeneration is
---    suppressed.
---  - `health_regen = false`: Disables passive health recovery out of combat.
---
---@param name string Technical entity name (e.g. "x_mobs:spider", "mymod:golem")
---@param def MobRegistrationDef Mob specification and callback configuration table
function x_mob_core.register_mob(name, def)
	return x_mob_core.lifecycle.entity_wrapper.register_mob(name, def)
end

---Transitions an entity to a new state machine state, invoking exit and enter hooks.
---@param self MobStateContext Mob instance context table
---@param new_state MobStateType Target state name
function x_mob_core.transition_to(self, new_state)
	return x_mob_core.lifecycle.state_machine.transition_to(self, new_state)
end

---Sets or updates armor groups on a mob while maintaining engine immortal protection.
---Immortal = 1 is preserved internally so that x_mob_core manages combat and health.
---@param self MobEntity|ObjectRef Mob entity instance or ObjectRef
---@param groups ArmorGroups Armor groups rating percentage (e.g. { fleshy = 80, cracky = 70 })
function x_mob_core.set_armor_groups(self, groups)
	return x_mob_core.lifecycle.entity_wrapper.set_armor_groups(self, groups)
end

---Registers an extensible step middleware hook into the mob execution pipeline.
---Allows 3rd-party mods and core subsystems to inject custom step logic without
---modifying core engine loops or overriding mob `on_step` callbacks (Open/Closed Principle).
---
---### Lifecycle & Execution Order
---Step hooks execute sequentially on every server tick for all living `x_mob_core` entities
---during `on_step`, after core lifecycle routines (death countdown, buoyancy, timers, target validation)
---and custom state machines have run, but before fallback idle wandering or target pursuit.
---
---Hooks are evaluated in ascending order of `priority` (lower numerical values run first).
---
---### Early Return & Interception
---The return value of `handler` controls execution flow:
---- Return `true`: **Intercepts** the step. Halts subsequent pipeline hooks from firing on this tick,
---  and bypasses default idle wandering (`step_wander_or_idle`) and target pursuit (`step_move_or_idle`).
---  Ideal for crowd control effects (stun, freeze, sleep, fear, paralysis).
---- Return `false` or `nil`: Continues to the next hook in the pipeline and allows normal locomotion.
---
---### Priority Schedule & Reference Table
---| Priority | Subsystem / Recommended Usage | Description |
---|:---|:---|:---|
---| `< 15` | Crowd Control / Status Effects | Stuns, freezes, sleep. Returning `true` halts attacks & movement. |
---| `15` | Built-in `"custom_step"` | Pre-combat custom ability hook (spells, summons, tactical standoff). |
---| `18` | Built-in `"melee"` | Internal melee attack range validation and strikes. |
---| `20` | Built-in `"shooter"` | Internal projectile attack aiming and shooting. |
---| `25` | Built-in `"environment"` | Internal hazard checks (lava, fire, drowning, suffocation). |
---| `30` | Built-in `"pack_cluster"` | Internal pack and squad cluster spawning trigger. |
---| `40` | Built-in `"swarm_nav"` | Internal 3D aerial Boids swarm navigation and dive-bombing. |
---| `42` | Built-in `"shoal_nav"` | Internal aquatic schooling navigation and anchor steering. |
---| `50+` | Post-Combat / Passives | Periodic damage ticks, status aura updates, dynamic buffs, telemetry. |
---
---@param name string Unique hook identifier (namespaced, e.g. "mymod:freeze_aura")
---@param priority integer Execution order (lower runs first; see priority schedule)
---@param handler StepHookHandler Callback function. Return `true` to intercept, or `false`/`nil` to continue.
function x_mob_core.register_step_hook(name, priority, handler)
	return x_mob_core.lifecycle.entity_wrapper.pipeline.register_step_hook(name, priority, handler)
end

---Unregisters a previously registered step middleware hook by unique identifier name.
---@param name string Unique hook identifier to remove (e.g. "mymod:freeze_aura")
function x_mob_core.unregister_step_hook(name)
	return x_mob_core.lifecycle.entity_wrapper.pipeline.unregister_step_hook(name)
end

-- Spawner Engine

---Registers a mob definition for natural map generation and environment spawning.
---@param mob_name string Registered entity technical name (e.g. "x_mobs:spider")
---@param def MobSpawnDef Environmental spawning parameters and condition filters
function x_mob_core.register_spawn(mob_name, def)
	return x_mob_core.spawning.registry.register_spawn(mob_name, def)
end

---Spawns a cohesive group of mobs scattered safely around a center point according to a spawn definition.
---@param spawn_pos Vector World center position
---@param def MobSpawnDef|string Spawn definition table or entity technical name
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
---@param self MobEntity Mob entity instance
---@param puncher? ObjectRef Attacking entity or player
---@param time_from_last_punch? number Elapsed time in seconds since last punch
---@param tool_capabilities? ToolCapabilities Weapon capabilities and damage groups
---@param dir? Vector Punch impulse direction vector
---@param damage? number Base damage override (bypasses tool capability calculation if provided)
---@param def? MobRegistrationDef Entity definition table
---@return boolean handled True if punch was processed and registered
function x_mob_core.handle_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def)
	return x_mob_core.lifecycle.entity_wrapper.combat_handler.handle_punch(
		self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def
	)
end

---Calculates damage from tool capabilities and mob armor groups, and applies wear to weapon.
---@param self MobEntity Mob entity instance
---@param puncher? ObjectRef Punching entity or player
---@param time_from_last_punch? number Time since last punch in seconds
---@param tool_capabilities? ToolCapabilities Wielded tool capabilities
---@param dir? Vector Punch direction vector
---@param damage_override? number Direct damage override (ignores tool capabilities when > 0)
---@return number dmg Calculated damage integer
function x_mob_core.calculate_punch_damage(self, puncher, time_from_last_punch, tool_capabilities, dir, damage_override)
	return x_mob_core.combat.damage.calculate_punch_damage(
		self, puncher, time_from_last_punch, tool_capabilities, dir, damage_override
	)
end

---Dampens punch knockback when an entity is struck inside water.
---Reduces horizontal impulse to prevent unrealistic gliding through liquid.
---@param self MobEntity Mob entity instance
function x_mob_core.dampen_water_knockback(self)
	return x_mob_core.combat.knockback.dampen_water_knockback(self)
end

---Returns the effective knockback multiplier for an ObjectRef or LuaEntity.
---@param obj ObjectRef|MobEntity Target object or mob entity
---@return number multiplier (1.0 for players, mob-defined knockback_mult, or 1.0 default)
function x_mob_core.get_knockback_mult(obj)
	return x_mob_core.combat.knockback.get_multiplier(obj)
end

---Checks whether two entities or players are allies according to faction and pack rules.
---@param a ObjectRef|MobEntity First object, mob entity, or projectile
---@param b ObjectRef|MobEntity Second object, mob entity, or projectile
---@return boolean are_allies True if both entities share allegiance
function x_mob_core.are_allies(a, b)
	return x_mob_core.combat.factions.are_allies(a, b)
end

---Checks whether two entities or players are enemies according to faction rules.
---@param a ObjectRef|MobEntity First object, mob entity, or projectile
---@param b ObjectRef|MobEntity Second object, mob entity, or projectile
---@return boolean are_enemies True if entities are hostile to each other
function x_mob_core.are_enemies(a, b)
	return x_mob_core.combat.factions.are_enemies(a, b)
end

---Returns the active faction set for an entity or player.
---@param obj ObjectRef|MobEntity Target ObjectRef or mob entity
---@return table<string, boolean> factions Set of active faction identifiers
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
---@param color? ColorSpec Optional custom colorize string or RGBA spec (default: "^[colorize:#FFFFFF60")
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
---@param def? MobRegistrationDef Entity definition table
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
---@param source_or_proj ObjectRef|MobEntity Projectile entity instance, shooter mob, or ObjectRef
---@param obj ObjectRef Target object to test
---@param options? ProjectileTargetOptions Optional configuration table
---@return boolean is_valid True if target is attackable, false if ignored
function x_mob_core.is_valid_projectile_target(source_or_proj, obj, options)
	return x_mob_core.combat.shooter.is_valid_target(source_or_proj, obj, options)
end

---Processes a standard projectile flight step: ballistics rotation, lifetime expiry,
---continuous raycasting, proximity collision, and impact handling.
---@param self MobEntity Projectile LuaEntity instance
---@param dtime number Step delta time
---@param options? ProjectileStepOptions Projectile configuration options
---@return boolean hit True if the projectile impacted an object or solid node
---@return ObjectRef|nil hit_obj Direct object impacted, if any
---@return Vector|nil hit_pos World coordinate of the impact
function x_mob_core.step_projectile(self, dtime, options)
	return x_mob_core.combat.shooter.step_projectile(self, dtime, options)
end

---Agnostically checks whether a LuaEntity is classified as a projectile or arrow.
---@param ent MobEntity|LuaEntitySAO LuaEntity table
---@return boolean is_projectile True if entity has projectile markers
function x_mob_core.is_projectile(ent)
	return x_mob_core.combat.shooter.is_projectile(ent)
end

---Advances declarative melee combat for an entity during its step tick.
---Validates attack range, raycast line-of-sight, halts horizontal velocity, turns mob to face target,
---plays attack animation and sound, and schedules delayed punch execution with reach tolerance.
---@param self MobEntity Mob entity instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Entity definition table containing melee configuration
---@return boolean handled True if melee logic handled combat, halting movement
function x_mob_core.step_melee(self, dtime, def)
	return x_mob_core.combat.melee.step(self, dtime, def)
end

---Executes an instantaneous melee strike against a target entity.
---Applies fleshy punch damage and triggers the configured on_strike callback or custom perform_attack override.
---@param self MobEntity Mob entity instance
---@param target ObjectRef Target entity to punch
---@param dir Vector Strike impulse direction vector
---@param def? MobRegistrationDef Mob definition table
---@param m_cfg? MeleeConfigDef Melee configuration table override
function x_mob_core.perform_melee_attack(self, target, dir, def, m_cfg)
	return x_mob_core.combat.melee.perform_attack(self, target, dir, def or self._def or {}, m_cfg)
end

---Advances declarative ranged combat (shooter) for an entity during its step tick.
---Validates range distance, raycast line-of-sight, performs tactical kiting if target enters min_range,
---dispatches charge windup callbacks, calculates aim lead trajectory, and spawns projectile entities.
---@param self MobEntity Mob entity instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Entity definition table containing shooter configuration
---@return boolean handled True if shooter logic handled combat, halting or kiting movement
function x_mob_core.step_shooter(self, dtime, def)
	return x_mob_core.combat.shooter.step(self, dtime, def)
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
---@param self MobEntity Mob entity instance
---@param cur_hp? number Current health (defaults to self.hp)
---@param max_hp? number Maximum health (defaults to self.hp_max)
---@return boolean shown True if health bar is shown or updated
function x_mob_core.show_health_bar(self, cur_hp, max_hp)
	local hp = cur_hp or self.hp
	local max = max_hp or self.hp_max
	return x_mob_core.combat.health_bar.show(self, hp, max, self._def)
end

---Hides or removes the dynamic overhead health bar on a mob entity.
---@param self MobEntity Mob entity instance
---@param remove_completely? boolean If true, destroys child entity; otherwise sets is_visible = false
function x_mob_core.hide_health_bar(self, remove_completely)
	if remove_completely then
		x_mob_core.combat.health_bar.remove(self)
	else
		x_mob_core.combat.health_bar.hide(self)
	end
end

---Forces an update of the health bar based on current mob HP.
---@param self MobEntity Mob entity instance
---@return boolean shown True if health bar was updated
function x_mob_core.update_health_bar(self)
	return x_mob_core.show_health_bar(self)
end

-- Envelop & Status Visual Subsystem

---Applies or updates a visual sleeve envelop and status effect on target.
---@param target ObjectRef Target player or entity to envelop
---@param effect_def EnvelopEffectDef Configuration: { id: string, duration: number, texture: string }
---@return ObjectRef? Envelop entity object
function x_mob_core.apply_envelop(target, effect_def)
	return x_mob_core.combat.envelop.apply_envelop(target, effect_def)
end

---Removes all active effects and detaches/removes envelop entity from target.
---@param target ObjectRef Target player or entity
function x_mob_core.remove_envelop(target)
	return x_mob_core.combat.envelop.remove_envelop(target)
end

---Removes a specific active effect from target's envelop, preserving remaining effects.
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID to remove
function x_mob_core.remove_envelop_effect(target, effect_id)
	return x_mob_core.combat.envelop.remove_envelop_effect(target, effect_id)
end

---Checks if target currently has an active envelop or a specific active effect.
---@param target ObjectRef Target player or entity
---@param effect_id? string Optional specific effect ID to query
---@return boolean is_enveloped True if active envelop/effect exists
function x_mob_core.is_enveloped(target, effect_id)
	return x_mob_core.combat.envelop.is_enveloped(target, effect_id)
end

---Convenience alias for `is_enveloped`. Checks if target currently has an active envelop or a specific active effect.
---@param target ObjectRef Target player or entity
---@param effect_id? string Optional specific effect ID to query
---@return boolean is_enveloped True if active envelop/effect exists
function x_mob_core.has_envelop(target, effect_id)
	return x_mob_core.is_enveloped(target, effect_id)
end

---Returns active envelop data record for target if present.
---@param target ObjectRef Target player or entity
---@return EnvelopTargetRecord? data Active envelop metadata
function x_mob_core.get_envelop_data(target)
	return x_mob_core.combat.envelop.get_envelop_data(target)
end

-- Status Effect Subsystem

---Applies or refreshes a status effect on target (player or mob entity).
---@param target ObjectRef Target player or entity
---@param effect_def StatusEffectDef Status effect definition table
---@return ObjectRef|boolean result Envelop object if envelop attached, or true on success
function x_mob_core.apply_status_effect(target, effect_def)
	return x_mob_core.combat.status_effects.apply_effect(target, effect_def)
end

---Removes an active status effect from target.
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID to remove
---@return boolean success True if effect was removed
function x_mob_core.remove_status_effect(target, effect_id)
	return x_mob_core.combat.status_effects.remove_effect(target, effect_id)
end

---Checks if target currently has an active status effect.
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID
---@return boolean has_effect True if effect is active
function x_mob_core.has_status_effect(target, effect_id)
	return x_mob_core.combat.status_effects.has_effect(target, effect_id)
end

---Checks if target is currently rooted / immobilized.
---@param target ObjectRef Target player or entity
---@return boolean is_rooted True if target has an active root status effect or speed_factor <= 0
function x_mob_core.is_rooted(target)
	return x_mob_core.combat.status_effects.is_rooted(target)
end

---Retrieves all active status effects for a target.
---@param target ObjectRef Target player or entity
---@return table<string, ActiveEffectRecord>? effects Active status effects map
function x_mob_core.get_status_effects(target)
	return x_mob_core.combat.status_effects.get_effects(target)
end

---Clears all active status effects and restores baseline physics on target.
---@param target ObjectRef Target player or entity
function x_mob_core.clear_status_effects(target)
	return x_mob_core.combat.status_effects.clear_effects(target)
end

---Registers a reusable status effect preset configuration (buff or debuff).
---@param id string Unique preset name (e.g. "frenzy", "ironhide", "haste")
---@param def StatusEffectDef Preset configuration table
function x_mob_core.register_status_effect_preset(id, def)
	return x_mob_core.combat.status_effects.register_preset(id, def)
end

---Convenience alias for `register_status_effect_preset`. Registers a reusable status effect preset configuration.
---@param id string Unique preset name (e.g. "frenzy", "ironhide", "haste")
---@param def StatusEffectDef Preset configuration table
function x_mob_core.register_status_preset(id, def)
	return x_mob_core.register_status_effect_preset(id, def)
end

---Retrieves a registered status effect preset configuration by ID.
---@param id string Preset name
---@return StatusEffectDef? def Preset definition table or nil
function x_mob_core.get_status_effect_preset(id)
	return x_mob_core.combat.status_effects.get_preset(id)
end

---Applies a buff (positive status effect) by preset name or definition.
---@param target ObjectRef Target player or mob entity
---@param preset_or_def string|StatusEffectDef Preset name or custom effect definition
---@param overrides? StatusEffectOverrideDef Optional field overrides (duration, level, etc.)
---@return ObjectRef|boolean result Envelop object if envelop attached, or true on success
function x_mob_core.apply_buff(target, preset_or_def, overrides)
	return x_mob_core.combat.status_effects.apply_buff(target, preset_or_def, overrides)
end

---Calculates current speed multiplier for target across all active status effects.
---@param target ObjectRef Target player or entity
---@return number multiplier Compound speed multiplier (default: 1.0)
function x_mob_core.get_speed_multiplier(target)
	return x_mob_core.combat.status_effects.get_speed_multiplier(target)
end

---Calculates current attack power multiplier for target across all active status effects.
---@param target ObjectRef Target player or entity
---@return number multiplier Compound attack multiplier (default: 1.0)
function x_mob_core.get_attack_multiplier(target)
	return x_mob_core.combat.status_effects.get_attack_multiplier(target)
end

---Calculates current incoming damage multiplier for target across all active status effects.
---@param target ObjectRef Target player or entity
---@return number multiplier Compound damage multiplier (default: 1.0)
function x_mob_core.get_damage_multiplier(target)
	return x_mob_core.combat.status_effects.get_damage_multiplier(target)
end

---Calculates total knockback resilience ratio [0.0, 1.0] for target.
---@param target ObjectRef Target player or entity
---@return number resilience Knockback resilience ratio (0.0 = full knockback, 1.0 = immune)
function x_mob_core.get_knockback_resilience(target)
	return x_mob_core.combat.status_effects.get_knockback_resilience(target)
end

---Retrieves active thorns configuration on target if any.
---@param target ObjectRef Target player or entity
---@return ThornsDef? thorns Thorns definition { damage: number, damage_type?: string, chance?: number }
function x_mob_core.get_thorns(target)
	return x_mob_core.combat.status_effects.get_thorns(target)
end

---Cleanses all negative debuffs from target.
---@param target ObjectRef Target player or entity
---@return integer count Number of cleansed debuffs
function x_mob_core.cleanse_debuffs(target)
	return x_mob_core.combat.status_effects.cleanse_debuffs(target)
end

---Dispels all positive buffs from target.
---@param target ObjectRef Target player or entity
---@return integer count Number of dispelled buffs
function x_mob_core.dispel_buffs(target)
	return x_mob_core.combat.status_effects.dispel_buffs(target)
end

---Scales damage groups by an attack multiplier.
---@param damage_groups DamageGroups Damage group table
---@param multiplier number Attack power multiplier
---@return DamageGroups scaled Scaled copy of damage groups
function x_mob_core.scale_damage_groups(damage_groups, multiplier)
	return x_mob_core.combat.status_effects.scale_damage_groups(damage_groups, multiplier)
end

x_mob_core.effects = x_mob_core.combat.effects
x_mob_core.hud_effects = x_mob_core.combat.hud_effects
x_mob_core.hunger_adapter = x_mob_core.combat.hunger_adapter
x_mob_core.particles = x_mob_core.combat.particles

---Applies or updates a fullscreen responsive screen vignette on a target player.
---@param player ObjectRef Target player
---@param effect_id string Unique status effect identifier
---@param config? VignetteConfig|string Vignette configuration table or texture modifier
---@return integer? hud_id Numerical HUD element ID or nil
function x_mob_core.apply_vignette(player, effect_id, config)
	return x_mob_core.hud_effects.apply(player, effect_id, config)
end

---Removes an active vignette effect for a player, restoring or updating composite overlays.
---@param player ObjectRef Target player
---@param effect_id string Unique status effect identifier
---@return boolean removed True if vignette was found and removed
function x_mob_core.remove_vignette(player, effect_id)
	return x_mob_core.hud_effects.remove(player, effect_id)
end

---Clears all active vignettes and destroys the HUD element for a player.
---@param player ObjectRef Target player
function x_mob_core.clear_vignettes(player)
	return x_mob_core.hud_effects.clear(player)
end

---Checks if a player currently has an active screen vignette.
---@param player ObjectRef Target player
---@param effect_id? string Optional specific effect ID
---@return boolean has_vignette True if active
function x_mob_core.has_vignette(player, effect_id)
	return x_mob_core.hud_effects.has_vignette(player, effect_id)
end

---Registers or overrides a custom vignette texture or config for an effect ID.
---@param effect_id string Unique status effect ID
---@param texture_spec VignetteConfig|string Configuration table or texture modifier string
function x_mob_core.register_vignette(effect_id, texture_spec)
	return x_mob_core.hud_effects.register_vignette(effect_id, texture_spec)
end

---Sets the global default base vignette texture asset.
---@param texture_name string Texture asset filename
function x_mob_core.set_default_vignette(texture_name)
	return x_mob_core.hud_effects.set_default_vignette(texture_name)
end

---Sets the global vignette prominence / opacity scaling multiplier.
---@param multiplier number Prominence multiplier (e.g. 1.0 = standard, 1.5 = high contrast)
function x_mob_core.set_vignette_prominence_multiplier(multiplier)
	return x_mob_core.hud_effects.set_prominence_multiplier(multiplier)
end

---Gets the global vignette prominence / opacity scaling multiplier.
---@return number multiplier Current vignette prominence multiplier
function x_mob_core.get_vignette_prominence_multiplier()
	return x_mob_core.hud_effects.get_prominence_multiplier()
end

-- Attached Particles Subsystem

---Attaches an ongoing or burst particle spawner to a target ObjectRef.
---@param target ObjectRef Target player or entity
---@param def ParticleSpawnerDef Particle spawner definition table
---@param playername? string Optional player name for selective packet scoping
---@return integer? spawner_id Particle spawner identifier
function x_mob_core.attach_particles(target, def, playername)
	return x_mob_core.combat.particles.attach(target, def, playername)
end

---Safely deletes an active particle spawner for a target.
---@param target ObjectRef Target player or entity
---@param spawner_id integer Particle spawner identifier
---@param playername? string Optional player name if spawner was scoped
---@return boolean success True if spawner was found and deleted
function x_mob_core.delete_particles(target, spawner_id, playername)
	return x_mob_core.combat.particles.delete(target, spawner_id, playername)
end

---Clears and deletes all active particle spawners for a given target.
---@param target ObjectRef Target player or entity
function x_mob_core.clear_target_particles(target)
	return x_mob_core.combat.particles.clear_target(target)
end

-- Motor & Steering Controller

---Executes tactical retreat steering away from a target position.
---@param self MobEntity Entity instance
---@param target_pos Vector World position to flee from
---@param speed? number Movement speed multiplier
---@return boolean is_retreating Whether retreat movement is actively executing
function x_mob_core.retreat_from(self, target_pos, speed)
	return x_mob_core.motor.locomotion.retreat_from(self, target_pos, speed)
end

---Advances tactical retreat, standoff kiting, and close-quarters retaliation for fleeing mobs.
---@param self MobEntity Entity instance
---@param dtime number Step delta time
---@param def? MobRegistrationDef Entity definition table
---@param moveresult? EngineMoveResult Engine move result
---@return boolean handled Whether tactical retreat intercepted the step
function x_mob_core.step_tactical_retreat(self, dtime, def, moveresult)
	return x_mob_core.motor.locomotion.step_tactical_retreat(self, dtime, def, moveresult)
end

---Scans for living players within radius using field of view and raycast line-of-sight checks.
---@param self MobEntity Entity instance
---@param scan_radius? number Detection radius in nodes (default: mob aggro_radius or 16.0)
---@param eye_height? number Vertical eye offset in nodes
---@return ObjectRef|nil player Nearest visible living player or nil
function x_mob_core.scan_for_player(self, scan_radius, eye_height)
	return x_mob_core.motor.ai.scan_for_player(self, scan_radius, eye_height)
end

---Advances ambient idle or wandering locomotion state for an entity.
---@param self MobEntity Entity instance
---@param dtime number Step delta time
---@param walk_anim? string Walking animation track name
---@param idle_anim? string Idle animation track name
---@return boolean is_moving Whether the mob is currently walking
function x_mob_core.step_wander_or_idle(self, dtime, walk_anim, idle_anim)
	return x_mob_core.motor.ai.step_wander_or_idle(self, dtime, walk_anim, idle_anim)
end

---Advances directional steering locomotion towards destination or target entity.
---@param self MobEntity Entity instance
---@param dtime number Step delta time
---@param move_anim? string Movement animation track name
---@param anim_speed? number Animation speed multiplier
---@param idle_anim? string Idle animation track name
---@return boolean is_moving Whether the mob is actively moving
function x_mob_core.step_move_or_idle(self, dtime, move_anim, anim_speed, idle_anim)
	return x_mob_core.motor.ai.step_move_or_idle(self, dtime, move_anim, anim_speed, idle_anim)
end

---Halts horizontal velocity of a mob entity while preserving vertical motion/gravity and liquid buoyancy.
---@param self MobEntity Entity instance
function x_mob_core.halt_horizontal_velocity(self)
	return x_mob_core.motor.locomotion.halt_horizontal_velocity(self)
end

---Sets horizontal velocity of a mob entity along a given yaw while preserving vertical motion/gravity.
---@param self MobEntity Entity instance
---@param speed number Horizontal movement speed in nodes/sec
---@param yaw number Orientation angle in radians
function x_mob_core.set_horizontal_velocity(self, speed, yaw)
	return x_mob_core.motor.locomotion.set_horizontal_velocity(self, speed, yaw)
end

---Detects if entity has collided with a wall/solid obstacle or is physically stagnant against one.
---@param self MobEntity Mob entity instance
---@param current_pos Vector Current world position
---@param dtime number Delta time
---@return boolean is_colliding Whether the mob is colliding with a wall
---@return Vector|nil wall_normal Estimated normal pointing away from the wall
---@return Vector|nil node_pos Position of collided node if known
function x_mob_core.has_wall_collision(self, current_pos, dtime)
	return x_mob_core.motor.locomotion.has_wall_collision(self, current_pos, dtime)
end

---Checks if an entity is an aquatic mob (fish, shoal, etc.) that swims freely in liquid.
---@param self MobEntity Entity instance
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
---@param self MobEntity Follower mob instance
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
---@return integer count Number of allies alerted
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
---@param follower_self MobEntity Follower mob instance
---@return boolean is_leashed True if within leash limit, false if leashed/separated
---@return Vector|nil leader_pos Position of leader if valid
---@return number dist Distance to leader
function x_mob_core.check_leash(follower_self)
	return x_mob_core.pack.coordination.check_leash(follower_self)
end

---Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy.
---Directly assigns `ent.target = target` and switches unengaged allies to `"combat"`.
---Note: This is an imperative one-shot function requiring a valid living `ObjectRef`.
---For automated damage and death rallying with spatial memory investigation (navigating
---to disturbance coordinates even without line of sight), use declarative `swarm_alert`
---in the mob definition instead.
---@param self MobEntity Mob instance
---@param target ObjectRef Threat target
---@param radius? number Alert radius in nodes (default: 16.0)
---@param max_allies? integer Max allies to alert (default: 4)
---@return integer count Number of allies alerted
function x_mob_core.broadcast_threat(self, target, radius, max_allies)
	return x_mob_core.pack.coordination.broadcast_threat(self, target, radius, max_allies)
end

---Rallies all pack followers to attack a shared target.
---@param leader_self MobEntity Leader mob instance
---@param target ObjectRef Target entity
---@return integer count Number of followers rallied
function x_mob_core.rally_followers(leader_self, target)
	return x_mob_core.pack.coordination.rally_followers(leader_self, target)
end

---Cleans invalid or dead follower objects from a leader's roster and returns alive count.
---@param leader_self MobEntity Leader mob instance
---@return integer count Alive follower count
---@return ObjectRef[] alive_followers Array of living follower ObjectRefs
function x_mob_core.clean_followers(leader_self)
	return x_mob_core.pack.squad.clean_followers(leader_self)
end

---Searches nearby area to adopt orphans or re-link separated followers.
---@param leader_self MobEntity Leader mob instance
---@param search_radius? number Radius to search in nodes (default: 32.0)
---@return integer count Number of orphans adopted
function x_mob_core.adopt_nearby_orphans(leader_self, search_radius)
	return x_mob_core.pack.squad.adopt_nearby_orphans(leader_self, search_radius)
end

---Registers a follower under a pack leader.
---@param leader_self MobEntity Leader mob instance
---@param follower_obj ObjectRef Follower entity object
---@param force? boolean If true, bypasses max_followers capacity limit (default: false)
---@return boolean added True if follower was newly registered, false if already present, full, or invalid
function x_mob_core.add_follower(leader_self, follower_obj, force)
	return x_mob_core.pack.squad.add_follower(leader_self, follower_obj, force)
end

---Removes a follower object from a leader's roster.
---@param leader_self MobEntity Leader mob instance
---@param follower_obj ObjectRef Follower entity object
---@return boolean removed True if follower was found and removed
function x_mob_core.remove_follower(leader_self, follower_obj)
	return x_mob_core.pack.squad.remove_follower(leader_self, follower_obj)
end

---Disbands the pack and notifies all followers when the leader dies.
---@param leader_self MobEntity Leader mob instance
function x_mob_core.handle_leader_death(leader_self)
	return x_mob_core.pack.squad.handle_leader_death(leader_self)
end

---Adopts nearby orphans and spawns missing followers radially around the leader.
---@param leader_self MobEntity Leader mob instance
---@param follower_type? string Entity technical name (default: leader_self.pack_follower_type)
---@param max_count? integer Target follower count (default: leader_self.pack_max_followers or 3)
---@param spawn_radius? number Radial spawn distance (default: 1.5)
---@return integer spawned Number of followers spawned
function x_mob_core.spawn_initial_followers(leader_self, follower_type, max_count, spawn_radius)
	return x_mob_core.pack.squad.spawn_initial_followers(leader_self, follower_type, max_count, spawn_radius)
end

---Follower searches nearby area to re-link with its pack leader if separated.
---@param follower_self MobEntity Follower mob instance
---@param search_radius? number Radius to search in nodes (default: 32.0)
---@return boolean relinked True if leader was found and re-linked
function x_mob_core.relink_follower(follower_self, search_radius)
	return x_mob_core.pack.squad.relink_follower(follower_self, search_radius)
end

-- Swarm Intelligence & Flocking

---Calculates 3D Boids spatial separation with horizontal anti-stacking bias.
---@param self MobEntity Mob instance
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
---@param self MobEntity Mob instance
---@param search_radius? number Radius to search for surviving mates (default: 24.0)
---@return boolean success True if a new leader was established
function x_mob_core.elect_successor(self, search_radius)
	return x_mob_core.pack.squad.elect_successor(self, search_radius)
end

---Applies a status effect or buff preset to all active living followers in a leader's pack.
---@param leader_self MobEntity Leader mob entity instance
---@param buff_def string|StatusEffectDef Buff preset identifier or status effect definition table
---@param options? PackBuffOptions Configuration options (include_leader, max_targets, sound, vfx)
---@return integer count Number of pack entities successfully buffed
function x_mob_core.apply_pack_buff(leader_self, buff_def, options)
	return x_mob_core.pack.coordination.apply_pack_buff(leader_self, buff_def, options)
end

---Pulses a radius aura applying a positive or neutral effect to allies or pack followers.
---@param caster_self MobEntity Caster mob entity instance
---@param aura_def AuraPulseDef Aura specification table (id, effect, radius, target, sound, vfx, max_targets)
---@return integer count Number of entities affected
function x_mob_core.pulse_aura(caster_self, aura_def)
	return x_mob_core.pack.coordination.pulse_aura(caster_self, aura_def)
end

---Triggers cowardice panic in nearby fellow mobs when a pack member dies.
---Causes eligible mobs within radius to enter the flee state and record danger memory.
---@param death_pos Vector Position of the deceased mob
---@param mob_name string Name of the entity to match (e.g. "x_mobs:fallen_minion")
---@param radius? number Search radius (default: 12.0)
---@param panic_duration? number Duration in seconds for flee state (default: 4.0)
---@param danger_dmg? number Perceived damage recorded in memory (default: 10)
---@return integer count Number of panicked mobs
function x_mob_core.trigger_cowardice_panic(death_pos, mob_name, radius, panic_duration, danger_dmg)
	return x_mob_core.pack.coordination.trigger_cowardice_panic(death_pos, mob_name, radius, panic_duration, danger_dmg)
end

---Advances master swarm AI step (flocking when idle, vortex and dive-bombs in combat).
---@param self MobEntity Mob instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Mob definition table
---@return boolean is_handled True if swarm logic handled step
function x_mob_core.step_swarm(self, dtime, def)
	return x_mob_core.pack.swarm.step(self, dtime, def)
end

---Advances ambient swarm flocking locomotion.
---@param self MobEntity Mob instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Mob definition table
---@return boolean is_handled True if flocking logic handled step
function x_mob_core.step_flock(self, dtime, def)
	return x_mob_core.pack.swarm.step_flock(self, dtime, def)
end

---Advances coordinated swarm combat locomotion (vortex holding pattern and dive-bomb runs).
---@param self MobEntity Mob instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Mob definition table
---@return boolean is_handled True if swarm combat handled step
function x_mob_core.step_swarm_combat(self, dtime, def)
	return x_mob_core.pack.swarm.step_combat(self, dtime, def)
end

---Advances fish schooling and shoal formation steering during an aquatic mob's step tick.
---Coordinates leader-follower anchor swimming, 3D water boundary avoidance, and school panic.
---@param self MobEntity Mob instance
---@param dtime number Step delta time
---@param def MobRegistrationDef Mob definition table containing shoal configuration
---@return boolean is_handled True if shoal logic handled locomotion
function x_mob_core.step_shoal(self, dtime, def)
	return x_mob_core.pack.shoal.step(self, dtime, def)
end

-- Audio & Sound

---Plays a configured sound type for a mob instance with positional audio and pitch variation.
---@param self MobEntity|ObjectRef Mob entity instance or ObjectRef
---@param sound_type string Category ("hurt", "death", "random", "attack", "alert") or technical sound name
---@param overrides? SoundOverrides Optional overrides (gain, distance, pitch, pos, object, to_player, loop)
---@return integer? sound_handle Luanti sound handle or nil if not played
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

---Shallow copies a table.
---@generic T : table
---@param tbl T
---@return T
function x_mob_core.shallow_copy(tbl)
	return x_mob_core.utils.shallow_copy(tbl)
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
---@return number? ground_y Top surface height of highest ground node, or nil
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
---@return Vector? waypoint Ground-anchored target position or nil
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
---@return number? ground_y Top surface Y of solid node, or nil if none found
function x_mob_core.find_ground_level(x, start_y, z, max_down)
	return x_mob_core.utils.find_ground_level(x, start_y, z, max_down)
end

---Schedules an action to be executed in the future on the mob's timer.
---Unlike `core.after`, scheduled actions are automatically tied to the mob's existence
---and will safely cancel if the mob dies, despawns, or transitions into a flinching state.
---@param self MobEntity Mob entity reference
---@param delay number Time in seconds
---@param tag string Identifier string, useful for cancellation or debugging
---@param callback fun(self: MobEntity) The function to execute, taking `self` as argument
function x_mob_core.schedule(self, delay, tag, callback)
	if not self._scheduled_actions then self._scheduled_actions = {} end
	table.insert(self._scheduled_actions, {
		timer = delay,
		tag = tag,
		callback = callback
	})
end

---Cancels scheduled actions by tag.
---@param self MobEntity Mob entity reference
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
---@param self MobEntity Mob entity reference
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
---@param self MobEntity Mob entity instance
---@param target ObjectRef|nil Target entity or player
---@return boolean changed True if target changed
function x_mob_core.set_target(self, target)
	return x_mob_core.lifecycle.entity_wrapper.set_target(self, target)
end

---Sets a mob's active texture variation by index.
---@param self MobEntity|ObjectRef Mob entity instance or ObjectRef
---@param id integer Texture variation index
---@param variations? string[][] Optional explicit variations list
---@return string[]? applied The applied textures array
function x_mob_core.set_texture(self, id, variations)
	return x_mob_core.lifecycle.entity_wrapper.set_texture(self, id, variations)
end

return x_mob_core
