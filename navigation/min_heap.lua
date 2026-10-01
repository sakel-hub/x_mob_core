--[[
	x_mob_core - Binary Min-Heap Priority Queue for LuaJIT A*
	- Zero table allocation during push / pop operations
	- Flat numeric priorities and flat integer values
	- O(log N) push and pop using single-hole sift algorithms
	- Fully compatible with LuaJIT Trace Compiler (no trace aborts)
]]

---@class MinHeap
---@field values number[] Flat array of stored integer values / IDs
---@field priorities number[] Flat array of numeric priorities (e.g. f_score)
---@field size integer Current number of elements in the heap
local MinHeap = {}
MinHeap.__index = MinHeap

--- Creates a new reusable binary min-heap
---@param initial_capacity integer|nil Optional hint for pre-allocating heap slots
---@return MinHeap
function MinHeap.new(initial_capacity)
	local cap = initial_capacity or 256
	local values = {}
	local priorities = {}

	-- Pre-allocate arrays to avoid reallocation churn
	for i = 1, cap do
		values[i] = 0
		priorities[i] = 0.0
	end

	local instance = {
		values = values,
		priorities = priorities,
		size = 0,
	}
	return setmetatable(instance, MinHeap)
end

--- Inserts a value with a numeric priority into the heap in O(log N)
--- Single-hole bubble up avoids intermediate swap assignments
---@param val integer Flat node index or identifier
---@param priority number Priority key (lower value has higher priority)
function MinHeap:push(val, priority)
	local size = self.size + 1
	self.size = size

	local values = self.values
	local priorities = self.priorities

	local i = size
	while i > 1 do
		local parent = math.floor(i * 0.5)
		if priorities[parent] <= priority then
			break
		end
		values[i] = values[parent]
		priorities[i] = priorities[parent]
		i = parent
	end

	values[i] = val
	priorities[i] = priority
end

--- Removes and returns the minimum priority element in O(log N)
--- Single-hole trickle down avoids intermediate swap assignments
---@return integer|nil val The popped value, or nil if heap is empty
---@return number|nil priority The popped priority, or nil if heap is empty
function MinHeap:pop()
	local size = self.size
	if size == 0 then
		return nil, nil
	end

	local values = self.values
	local priorities = self.priorities

	local min_val = values[1]
	local min_priority = priorities[1]

	local last_val = values[size]
	local last_priority = priorities[size]

	-- Clear slot to prevent retention of dead references
	values[size] = 0
	priorities[size] = 0.0
	size = size - 1
	self.size = size

	if size > 0 then
		local i = 1
		local half = math.floor(size * 0.5)
		while i <= half do
			local left = i * 2
			local right = left + 1
			local smallest = left

			if right <= size and priorities[right] < priorities[left] then
				smallest = right
			end

			if last_priority <= priorities[smallest] then
				break
			end

			values[i] = values[smallest]
			priorities[i] = priorities[smallest]
			i = smallest
		end
		values[i] = last_val
		priorities[i] = last_priority
	end

	return min_val, min_priority
end

--- Peeks at the lowest priority element without removing it in O(1)
---@return integer|nil val
---@return number|nil priority
function MinHeap:peek()
	if self.size == 0 then
		return nil, nil
	end
	return self.values[1], self.priorities[1]
end

--- Returns true if the heap contains no elements in O(1)
---@return boolean
function MinHeap:is_empty()
	return self.size == 0
end

--- Resets the heap for reuse in O(1) without reallocating arrays
function MinHeap:clear()
	self.size = 0
end

--- Returns the current number of elements in the heap
---@return integer
function MinHeap:get_size()
	return self.size
end

return MinHeap
