--[[
	x_mob_core - Lifecycle Step Pipeline
	Extensible middleware execution pipeline for per-step mob behaviors.
	Allows subsystems (shooter, swarm, customs) to register step logic
	without modifying the core step loop (Open/Closed Principle).
]]

---@class StepHook
---@field name string Identifier of the hook
---@field priority integer Execution order (lower runs first)
---@field handler fun(self: table, dtime: number, def: table, moveresult?: table): boolean|nil

---@class StepPipeline
local pipeline = {
	---@type StepHook[]
	hooks = {},
}

---Registers a step middleware hook executed during handle_core_step.
---If the handler returns `true`, subsequent step handling is intercepted (early return).
---@param name string Unique hook identifier
---@param priority integer Execution order (e.g. 10 for pre-combat, 50 for combat, 100 for post)
---@param handler fun(self: table, dtime: number, def: table, moveresult?: table): boolean|nil
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

---Unregisters a previously registered step hook.
---@param name string
function pipeline.unregister_step_hook(name)
	for i = #pipeline.hooks, 1, -1 do
		if pipeline.hooks[i].name == name then
			table.remove(pipeline.hooks, i)
			return
		end
	end
end

---Executes registered step hooks sequentially in priority order.
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param def table Entity definition table
---@param moveresult? table Engine move result
---@return boolean handled True if intercepted by any hook
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
