--[[
	x_mob_core - Event Dispatcher Subsystem
	Observer / Pub-Sub pattern for decoupling mob lifecycle and external hooks
]]

---@class EventsSubsystem
---@field listeners table<string, fun(...)[]>
local events = {
	listeners = {},
}

--- Registers an event listener
---@param event_name string Event identifier (e.g. "on_mob_death", "on_pack_spawn")
---@param callback fun(...) Function invoked when event is emitted
---@return integer id Listener registration token
function events.listen(event_name, callback)
	if not events.listeners[event_name] then
		events.listeners[event_name] = {}
	end
	table.insert(events.listeners[event_name], callback)
	return #events.listeners[event_name]
end

--- Unregisters an event listener by token
---@param event_name string Event identifier
---@param id integer Listener registration token returned by listen()
---@return boolean success True if listener was found and removed
function events.unlisten(event_name, id)
	local list = events.listeners[event_name]
	if list and list[id] then
		list[id] = nil
		return true
	end
	return false
end

--- Emits an event to all registered listeners
---@param event_name string
---@param ... any Arguments passed to listeners
function events.emit(event_name, ...)
	local list = events.listeners[event_name]
	if not list then return end
	for i = 1, #list do
		local cb = list[i]
		if cb then
			cb(...)
		end
	end
end

return events
