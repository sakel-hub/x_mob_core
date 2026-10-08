--[[
	x_mob_core - Lifecycle Step Pipeline
	Extensible middleware execution pipeline for per-step mob behaviors.
	Allows subsystems (shooter, swarm, customs) to register step logic
	without modifying the core step loop (Open/Closed Principle).
]]

---@class StepHook
---@field name string Unique identifier of the hook (e.g. "mymod:freeze_aura")
---@field priority integer Execution order (lower runs first; see priority schedule in documentation)
---@field handler StepHookHandler Middleware callback executed each step

---@class StepPipeline
local pipeline = {
	---@type StepHook[]
	hooks = {},
}

---Registers a step middleware hook executed during entity step lifecycle.
---Hooks execute sequentially in ascending priority order on every server tick.
---If the handler returns `true`, subsequent step handling is intercepted (early return).
---@param name string Unique hook identifier (namespaced, e.g. "mymod:freeze_aura")
---@param priority integer Execution order (lower runs first; e.g. < 18 for CC/stun, 18 melee, 20 shooter, 50+ aura)
---@param handler StepHookHandler Callback function. Return `true` to intercept, or `false`/`nil` to continue.
function pipeline.register_step_hook(name, priority, handler)
	for i = 1, #pipeline.hooks do
		if pipeline.hooks[i].name == name then
			pipeline.hooks[i].priority = priority
			pipeline.hooks[i].handler = handler
			table.sort(pipeline.hooks, function(a, b) return a.priority < b.priority end)
			return
		end
	end
	table.insert(pipeline.hooks, {
		name = name,
		priority = priority,
		handler = handler,
	})
	table.sort(pipeline.hooks, function(a, b) return a.priority < b.priority end)
end

---Unregisters a previously registered step hook by identifier name.
---@param name string Unique hook identifier to remove
function pipeline.unregister_step_hook(name)
	for i = #pipeline.hooks, 1, -1 do
		if pipeline.hooks[i].name == name then
			table.remove(pipeline.hooks, i)
			return
		end
	end
end

---Executes registered step hooks sequentially in priority order.
---If any hook handler returns `true`, pipeline execution halts immediately and returns `true`.
---@param self table Mob entity instance
---@param dtime number Step delta time in seconds
---@param def MobRegistrationDef|table Entity definition table
---@param moveresult? table Engine move result
---@return boolean handled True if intercepted by any hook, false otherwise
function pipeline.execute(self, dtime, def, moveresult)
	local hook_list = pipeline.hooks
	for i = 1, #hook_list do
		if hook_list[i].handler(self, dtime, def, moveresult) then
			return true
		end
	end
	return false
end

return pipeline
