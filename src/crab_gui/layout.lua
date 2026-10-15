local insert = table.insert

---Solves constraints for a value on a GuiRect.
---@alias ConstraintSolver fun(rect: GuiRect): number
---@alias Direction "right"|"down"|"left"|"up"
---@alias Side "right"|"bottom"|"left"|"top"

---A rectangle defined by two 2D points.
---@class Bounds
---@field size userdata?
local m_bounds = {}
m_bounds.__index = m_bounds

---@return userdata
function m_bounds:get_size()
	if self.size then return self.size end
	
	self.size = self.max // 1 - self.min // 1
	return self.size
end

---Creates a set of bounds from the low and high corners.
---@param min userdata
---@param max userdata
---@return Bounds
local function new_bounds(min, max)
	---@class Bounds
	local bounds = {
		min = min,
		max = max,
	}
	
	return setmetatable(bounds, m_bounds)
end

---An ephemeral rectangle with values and constraint solvers.
---@class GuiRect
local m_gui_rect = {}
m_gui_rect.__index = m_gui_rect

---Fetches a value from the rectangle. Will attempt to solve the value if it's not
---already solved.
---
---A newly solved key is cached on the GuiRect under the same key as the solver.
---
---Errors if there is a dependency cycle.
---@param key string
---@return any
function m_gui_rect:get_value(key)
	if self[key] then return self[key] end
	
	if self.pending[key] then
		error(("Dependency cycle detected on %s while trying to fetch %s"):format(tostr(self), key))
	end
	
	local solver = self.constraints[key]
	if not solver then
		error(("Failed to find solver for key \"%s\""):format(key))
	end
	self.pending[key] = true
	self[key] = solver(self)
	self.pending[key] = nil
	
	return self[key]
end

---Forces all four edges to be solved, and returns their bounds.
---@return Bounds
function m_gui_rect:get_bounds()
	if self.bounds then return self.bounds end
	local min = vec(self:get_value("min_x"), self:get_value("min_y"))
	local max = vec(self:get_value("max_x"), self:get_value("max_y"))
	
	self.bounds = new_bounds(min, max)
	return self.bounds
end

---@param constraints Constraints
---@param parent GuiRect? Defaults to self. Only use nil for the top level.
---@return GuiRect
local function new_rect(constraints, parent)
	---@class GuiRect
	---@field next_sibling GuiRect?
	---@field prev_sibling GuiRect?
	---@field min_x number?
	---@field min_y number?
	---@field max_x number?
	---@field max_y number?
	local rect = {
		children = {}, ---@type GuiRect[]
		pending = {}, ---@type table<string, true?>
		constraints = constraints,
	}
	
	if parent then
		rect.prev_sibling = parent.children[#parent.children]
		insert(parent.children, rect)
		if rect.prev_sibling then
			rect.prev_sibling.next_sibling = rect
		end
	end
	
	rect.parent = parent or rect
	
	return setmetatable(rect, m_gui_rect)
end

---A set of solvers for satisfying the constraints of a rectangle.
---@class Constraints
local m_constraints = {}
m_constraints.__index = m_constraints

---Creates a new set of constraints from solvers for each edge.
---@param min_x ConstraintSolver
---@param min_y ConstraintSolver
---@param max_x ConstraintSolver
---@param max_y ConstraintSolver
---@return Constraints
local function new_constraints(min_x, min_y, max_x, max_y)
	---@class Constraints
	local constraints = {
		min_x = min_x,
		min_y = min_y,
		max_x = max_x,
		max_y = max_y,
	}
	
	return setmetatable(constraints, m_constraints)
end

---Composites a solver that checks if the rect contains a key. If it does,
---`solve_true` is called. Otherwise, `solve_false` is called.
---@param predicate_key string
---@param solve_true ConstraintSolver
---@param solve_false ConstraintSolver
---@return ConstraintSolver
local function switch(predicate_key, solve_true, solve_false)
	return function(rect)
		return rect[predicate_key] and solve_true(rect) or solve_false(rect)
	end
end

---Composites multiple solvers into one that sums each result.
---@param ... ConstraintSolver
---@return ConstraintSolver
local function sum(...)
	local solvers = {...}
	
	return function(rect)
		local value = 0
		for i = 1, #solvers do
			value += solvers[i](rect)
		end
		return value
	end
end

---Creates a solver that places the edge offset from an edge on a related rect.
---@param relationship_key string
---@param source_key string
---@param offset number
---@return ConstraintSolver
local function align(relationship_key, source_key, offset)
	return function(rect)
		return rect[relationship_key]:get_value(source_key) + offset
	end
end

---Creates a solver that places the edge offset from an anchor on the parent rect.
---@param anchor number The normalized position of the anchor relative to the parent's minimum and maximum edges.
---@param offset number The offset from the anchor.
---@param min_key string The parent's minimum key on this axis.
---@param max_key string The parent's maximum key on this axis.
---@return ConstraintSolver
local function anchor_offset(anchor, offset, min_key, max_key)
	return function(rect)
		local parent_min = rect.parent:get_value(min_key)
		local parent_max = rect.parent:get_value(max_key)
		
		return (parent_max - parent_min) * anchor + parent_min + offset
	end
end

---Creates a solver that places the edge offset from the previous sibling, or the
---parent, if there is no previous sibling.
---@param parent_offset number The offset to use when there's no previous sibling.
---@param sibling_offset number The offset to use relative to a previous sibling.
---@param parent_key string The key to the edge of the parent to start from.
---@param sibling_key string The key to the edge of the sibling to continue from.
---@return ConstraintSolver
local function after_sibling(parent_offset, sibling_offset, parent_key, sibling_key)
	return switch(
		"prev_sibling",
		align("prev_sibling", sibling_key, sibling_offset),
		align("parent", parent_key, parent_offset)
	)
end

---Creates a solver that places the edge offset from another edge on the same rect.
---@param offset number The offset from the reference edge.
---@param reference_key string The key to the reference edge.
---@return ConstraintSolver
local function size_from_edge(offset, reference_key)
	return function(rect)
		return rect:get_value(reference_key) + offset
	end
end

---Creates a set of constraints in which a series of items will be arrayed in a
---specified direction.
---@param margin_start number The margin from the parent at the beginning of the array.
---@param margin_cross_min number The margin from the parent on the parent's low side.
---@param margin_cross_max number The margin from the parent on the parent's high side.
---@param spacing number The space in between two sibling rects.
---@param direction Direction The direction from which the array expands.
---@param size_solver ConstraintSolver The solver for the far edge of the item. If you want a fixed size, use `size_from_edge`.
---@return Constraints
local function array(margin_start, margin_cross_min, margin_cross_max, spacing, direction, size_solver)
	if direction == "right" then
		return new_constraints(
			after_sibling(margin_start, spacing, "min_x", "max_x"),
			align("parent", "min_y", margin_cross_min),
			size_solver,
			align("parent", "max_y", -margin_cross_max)
		)
	elseif direction == "down" then
		return new_constraints(
			align("parent", "min_x", margin_cross_min),
			after_sibling(margin_start, spacing, "min_y", "max_y"),
			align("parent", "max_x", -margin_cross_max),
			size_solver
		)
	elseif direction == "left" then
		return new_constraints(
			size_solver,
			align("parent", "min_y", margin_cross_min),
			after_sibling(-margin_start, -spacing, "max_x", "min_x"),
			align("parent", "max_y", -margin_cross_max)
		)
	elseif direction == "up" then
		return new_constraints(
			align("parent", "min_x", margin_cross_min),
			size_solver,
			align("parent", "max_x", -margin_cross_max),
			after_sibling(-margin_start, -spacing, "max_y", "min_y")
		)
	else
		error(("\"%s\" is not a valid direction to array elements."):format(tostr(direction)))
	end
end

---Creates a solver which produces a size which is a ratio of the distance between cross_min_key and cross_max_key.
---
---Intended to be used in a `sum` composite solver.
---@param ratio number
---@param cross_min_key string
---@param cross_max_key string
---@return ConstraintSolver
local function cross_ratio(ratio, cross_min_key, cross_max_key)
	return function(rect)
		local size = rect:get_value(cross_max_key) - rect:get_value(cross_min_key)
		return size * ratio
	end
end

---Creates a solver that places the edge offset from an anchor on the parent rect,
---plus some offset which is a ratio of the size of the opposing axis.
---@param anchor number
---@param offset number
---@param ratio number
---@param side Side
---@return ConstraintSolver
local function aspect_ratio(anchor, offset, ratio, side)
	if side == "right" then
		return sum(
			anchor_offset(anchor, offset, "min_x", "max_x"),
			cross_ratio(ratio, "min_y", "max_y")
		)
	elseif side == "bottom" then
		return sum(
			anchor_offset(anchor, offset, "min_y", "max_y"),
			cross_ratio(ratio, "min_x", "max_x")
		)
	elseif side == "left" then
		return sum(
			anchor_offset(anchor, offset, "min_x", "max_x"),
			cross_ratio(-ratio, "min_y", "max_y")
		)
	elseif side == "top" then
		return sum(
			anchor_offset(anchor, offset, "min_y", "max_y"),
			cross_ratio(-ratio, "min_x", "max_x")
		)
	else
		error(("\"%s\" is not a valid side of a rect."):format(tostr(side)))
	end
end

---Creates a set of constraints in which all four edges are offset from an anchor
---relative to the parent.
---@param anchor_min userdata? How far from the parent bounds' low corner to its high corner the minimum anchor of the GuiRect is as a perunitage. Defaults to `0, 0`
---@param anchor_max userdata? How far from the parent bounds' low corner to its high corner the maximum anchor of the GuiRect is as a perunitage. Defaults to `1, 1`
---@param offset_min userdata? The position of the low corner relative to the low anchor. Defaults to `0, 0`
---@param offset_max userdata? The position of the high corner relative to the high anchor. Defaults to `0, 0`
---@return Constraints
local function anchor_offset_all(anchor_min, anchor_max, offset_min, offset_max)
	anchor_min = anchor_min or vec(0, 0)
	anchor_max = anchor_max or vec(1, 1)
	offset_min = offset_min or vec(0, 0)
	offset_max = offset_max or vec(0, 0)
	
	return new_constraints(
		anchor_offset(anchor_min.x, offset_min.x, "min_x", "max_x"),
		anchor_offset(anchor_min.y, offset_min.y, "min_y", "max_y"),
		anchor_offset(anchor_max.x, offset_max.x, "min_x", "max_x"),
		anchor_offset(anchor_max.y, offset_max.y, "min_y", "max_y")
	)
end

---Creates a new GuiRect with a fixed size, assuming that the minimum and maximum
---anchors are the same.
---
---The anchor is both where on the parent bounds the GuiRect will be positioned
---relative to, and also the fraction of the size that will extend past the low corner.
---
---An anchor of `0, 0` will put the anchor on the top left corner of the GuiRect.
---
---An anchor of `1, 1` will put the anchor on the bottom right corner of the GuiRect.
---
---An anchor of `0.5, 0.5` will put the anchor in the center of the GuiRect.
---@param anchor userdata How far from the parent bounds' low corner to its high corner both anchors of the GuiRect are as a perunitage.
---@param size userdata The width and height of the GuiRect.
---@param offset userdata? How far the GuiRect will be shifted relative to the anchor position.
---@return Constraints
local function anchor_size_all(anchor, size, offset)
	offset = offset or vec(0, 0)
	
	return anchor_offset_all(
		anchor,
		anchor,
		offset - size * anchor,
		offset + size * (1 - anchor)
	)
end

---Creates a set of constraints which fills the provided draw target.
---@param target userdata
---@return Constraints
local function constraints_of_target(target)
	local width, height = target:attribs()
	return new_constraints(
		function() return 0 end,
		function() return 0 end,
		function() return width end,
		function() return height end
	)
end

return {
	new_rect = new_rect,
	new_bounds = new_bounds,
	new_constraints = new_constraints,
	
	constraints_of_target = constraints_of_target,
	anchor_offset_all = anchor_offset_all,
	anchor_size_all = anchor_size_all,
	
	switch = switch,
	sum = sum,
	align = align,
	
	anchor_offset = anchor_offset,
	after_sibling = after_sibling,
	size_from_edge = size_from_edge,
	cross_ratio = cross_ratio,
	aspect_ratio = aspect_ratio,
	array = array,
}