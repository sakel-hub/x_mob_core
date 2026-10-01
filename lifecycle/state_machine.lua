--[[
	x_mob_core - Extensible State Machine
	Coordinates state transitions, custom states, and lifecycle callbacks
]]

---@class StateMachineSubsystem
local state_machine = {}

--- Transitions an entity to a new state, invoking exit and enter hooks
---@param self table Mob instance
---@param new_state string Target state name
function state_machine.transition_to(self, new_state)
	local old_state = self.state
	if old_state == new_state then return end

	-- Invoke exit hook on departing state
	if self.custom_states and self.custom_states[old_state] and self.custom_states[old_state].exit then
		self.custom_states[old_state].exit(self)
	end

	self.state = new_state

	-- Invoke enter hook on arriving state
	if self.custom_states and self.custom_states[new_state] and self.custom_states[new_state].enter then
		self.custom_states[new_state].enter(self)
	end
end

--- Updates the current custom state if one is active
---@param self table Mob instance
---@param dtime number Step delta time
---@return boolean handled True if handled by a custom state, false otherwise
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
