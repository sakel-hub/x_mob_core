--[[
	x_mob_core - Extensible State Machine
	Coordinates state transitions, custom states, and lifecycle callbacks
]]

---Canonical state machine states coordinating mob behavior, animation, and locomotion.
---@alias MobStateType
---| '"idle"'        # Entity is stationary, resting, or scanning for nearby targets
---| '"wandering"'   # Entity is passively exploring local terrain within wander_radius
---| '"walk"'        # Entity is traversing toward an objective, waypoint, or squad position
---| '"combat"'      # Entity has acquired a hostile target and is actively maneuvering/pursuing
---| '"attacking"'   # Entity is executing an active melee attack animation or combat ability
---| '"shooting"'    # Entity is executing a ranged attack windup, casting, or projectile launch
---| '"fleeing"'     # Entity is executing a tactical retreat due to low HP or threat level
---| '"regrouping"'  # Entity is returning to its squad leader or shoal anchor position
---| '"flinching"'   # Entity is in hit-stun recoil from taking damage (hyper-armor checked)
---| '"dying"'       # Entity has reached zero HP and is playing its defeat animation before removal
---| string          # Custom user-defined state registered in custom_states

---@class MobMemoryTargetRecord
---@field name string Entity name of remembered target
---@field lkp Vector Last known 3D position vector
---@field last_seen number Timestamp of last target sighting
---@field has_record boolean Whether target memory slot is populated

---@class MobMemoryDangerRecord
---@field x number Danger position X coordinate
---@field y number Danger position Y coordinate
---@field z number Danger position Z coordinate
---@field threat number Threat intensity score
---@field expire number Expiration timestamp
---@field active boolean Whether danger slot is populated

---@class MobMemoryState
---@field target MobMemoryTargetRecord Single predictive target pursuit record (8-second LKP)
---@field dangers MobMemoryDangerRecord[] Pre-allocated circular buffer of active pain/danger positions
---@field trail table[] Pre-allocated circular buffer of recent positions for anti-oscillation
---@field blocked_spots table[] Obstruction memory for deadlock evasion
---@field regen_timer number Elapsed time during low-HP passive health regeneration
---@field flee_state boolean Whether entity is currently in low-HP tactical retreat
---@field fight table Combat location memory for return-to-fight logic

---Mob entity execution context passed as `self` across state machine callbacks and hooks.
---Provides developers direct access to engine references, state variables, timers, memory, and locomotion.
---@class MobStateContext
---@field object ObjectRef Luanti engine C++ userdata pointer representing the active entity
---@field name string Technical registered entity name (e.g. "x_mobs:golem")
---@field state MobStateType Current active state identifier
---@field target? ObjectRef Currently acquired hostile or pursuit target
---@field is_dead boolean Flag indicating whether the entity is dead or dying
---@field custom_states? table<string, CustomStateDef> Map of registered custom states
---@field memory? MobMemoryState Short-term tactical memory buffer (LKP, threats, repulsion, trail)
---@field action_timer? number Duration remaining for uninterruptible action; locks standard locomotion while > 0
---@field attack_cooldown? number Global melee/combat attack cooldown timer
---@field panic_timer? number Duration remaining for panic flee state
---@field scan_timer? number Throttle timer for periodic target scanning
---@field lost_sight_timer? number Seconds elapsed since losing direct line of sight to target
---@field cooldowns? table<string, number> Named ability cooldown timers
---@field set_cooldown fun(self: MobStateContext, key: string, duration: number) Helper to set ability cooldown
---@field path_state? table Pathfinding waypoints and traversal state
---@field mob_height? number Mob height in nodes
---@field eye_offset? number Vertical offset from base to eye level in nodes
---@field half_width? number Half-width bounding box dimension in nodes
---@field walk_speed? number Standard walking velocity
---@field pursuit_speed? number Combat chase velocity
---@field wander_speed? number Ambient wandering velocity
---@field flee_speed? number Panic escape velocity
---@field wander_radius? number Maximum radius from anchor for wandering
---@field can_wander? boolean Whether mob is permitted to wander autonomously
---@field can_swim? boolean Whether mob can traverse liquid nodes
---@field can_climb? boolean Whether mob can climb ladders/vines
---@field can_open_doors? boolean Whether mob can open wooden doors
---@field can_crawl? boolean Whether mob can crawl through 1-node high spaces
---@field is_floating? boolean Whether gravity is disabled (flying/swimming)
---@field hover_offset? number Target elevation offset above ground or water
---@field combat_hover_offset? number Target elevation offset above ground during combat
---@field combat_standoff? number Desired horizontal standoff distance in combat
---@field attack_range? number Maximum distance to initiate melee attack
---@field aggro_radius? number Maximum distance to detect hostile targets
---@field damage? number Base melee attack damage dealt
---@field knockback_mult? number Resistance multiplier to incoming kinetic knockback
---@field factions? table<string, boolean> Set of faction identifiers
---@field faction_list? string[] Ordered list of faction names
---@field friendly_fire? boolean Whether entity attacks/damages friendly faction members
---@field pack_id? string UUID of the squad/pack if participating in pack coordination
---@field pack_leader? ObjectRef Reference to the squad leader entity
---@field sounds? string|MobSoundDef Sound configuration or sound group name
---@field _def? MobRegistrationDef Original registration definition table
---@field _moveresult? table Physics step collision result (touching_ground, collisions)
---@field _killer? ObjectRef ObjectRef of killer if entity died
---@field on_action_end? fun(self: MobStateContext) Invoked when action_timer reaches 0
---@field on_return_to_fight? fun(self: MobStateContext) Invoked when recovering from flee state
---@field can_flinch? fun(self: MobStateContext): boolean Custom hyper-armor/poise predicate

---@class StateMachineSubsystem
local state_machine = {}

---Transitions an entity to a new state, invoking exit and enter hooks.
---
---### How States Are Set & Transition Mechanisms:
---1. **Canonical Transition API (`x_mob_core.transition_to` / `state_machine.transition_to`)**:
---   The standard method to transition between states. It checks whether `old_state == new_state`
---   (preventing redundant cycles), calls `custom_states[old_state].exit(self)` if available,
---   updates `self.state = new_state`, and calls `custom_states[new_state].enter(self)`.
---2. **Custom State Step Tick Return**:
---   Inside `custom_states[state].step(self, dtime)`, return a target state name string
---   (e.g., `return "idle"` or `return "fleeing"`) to trigger an automatic call to
---   `state_machine.transition_to(self, next_state)`. Returning `nil` or `true` retains current state.
---3. **Declarative State Transitions (`transitions = { ... }`)**:
---   Evaluated every tick in the lifecycle step pipeline. When `condition(self)` evaluates to `true`,
---   `self.state` transitions from `from` (or wildcard `"*"`) to `to`, and `on_transition(self)` runs.
---4. **Core AI / Subsystem Direct Assignment (`self.state = "..."`)**:
---   Core internal routines (`mob_ai.step_wander_or_idle`, `combat_handler`, `shoal`, `coordination`)
---   set `self.state` directly during built-in behaviors. Note: direct assignment does not trigger
---   `custom_states` `exit` or `enter` hooks; use `transition_to` when custom state hooks are needed.
---5. **Action Timer Completion**:
---   When `self.action_timer` completes, `self:on_action_end()` is invoked and `self.state` resets to `"idle"`.
---
---### What Is Available on `self` for Developers:
---Inside state callbacks (`enter`, `step`, `exit`), developers have full access to `self` (`MobStateContext`):
---- **Engine Object**: `self.object` (`ObjectRef`), `self.name`, `self._moveresult`.
---- **Timers & Cooldowns**: `self.action_timer`, `self.attack_cooldown`, `self.panic_timer`, `self.cooldowns`,
----   and helper `self:set_cooldown(key, duration)`.
---- **Tactical Memory**: `self.memory` (`MobMemoryState`: target LKP, danger repulsion, flee state).
---- **Locomotion Attributes**: `self.walk_speed`, `self.pursuit_speed`, `self.wander_speed`, `self.flee_speed`,
----   `self.wander_radius`, and `self.path_state`.
---- **Combat & Defense**: `self.damage`, `self.attack_range`, `self.aggro_radius`, `self.knockback_mult`,
----   and `self.factions`.
---- **Animation & Audio**: `x_mob_core.animator.play(self.object, anim_name, opts)` and
----   `x_mob_core.sound.play(self, sound_type)`.
---
---@param self MobStateContext Mob instance context table
---@param new_state MobStateType Target state name to transition to
function state_machine.transition_to(self, new_state)
	local old_state = self.state
	if old_state == new_state then return end

	-- Invoke exit hook on departing state
	if self.custom_states and self.custom_states[old_state] and self.custom_states[old_state].exit then
		self.custom_states[old_state].exit(self)
	end

	-- Core state assignment: departing state has cleaned up, assign new state before entry hook
	---@type MobStateType
	self.state = new_state

	-- Invoke enter hook on arriving state
	if self.custom_states and self.custom_states[new_state] and self.custom_states[new_state].enter then
		self.custom_states[new_state].enter(self)
	end
end

---Updates the current custom state if one is active.
---Invoked every server tick during the mob's step pipeline. If `self.state` matches a registered
---entry in `self.custom_states`, executes its `step(self, dtime)` callback. If that callback returns
---a different state name, triggers `state_machine.transition_to(self, next_state)`.
---@param self MobStateContext Mob instance context table
---@param dtime number Step delta time in seconds
---@return boolean handled True if handled by an active custom state, false otherwise
function state_machine.update(self, dtime)
	if not self.state then return false end

	local custom = self.custom_states and self.custom_states[self.state]
	if custom and custom.step then
		local next_state = custom.step(self, dtime)
		if next_state and next_state ~= self.state then
			state_machine.transition_to(self, next_state)
		end
		return true
	end

	return false
end

return state_machine
