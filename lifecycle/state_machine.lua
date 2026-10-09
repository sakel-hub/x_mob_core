--[[
	x_mob_core - Extensible State Machine
	Coordinates state transitions, custom states, and lifecycle callbacks
]]

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
