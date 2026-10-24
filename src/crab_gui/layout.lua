local insert = table.insert
local min, max = math.min, math.max
local abs = math.abs
local huge = math.huge

---@alias Axis "horizontal"|"vertical"
---@alias Direction "right"|"down"|"left"|"up"
---@alias Side "right"|"bottom"|"left"|"top"

---@alias Relation "self"|"parent"|"prev_sibling"|"next_sibling"

---@class CachedProperty
---@field absolute number?
---@field relative number?
---@field root_rect GuiRect?
---@field root_key string?

---@alias Solver AbsoluteSolver|RelativeSolver

---@class AbsoluteSolver
---@field is_relative fun(rect: GuiRect): boolean
---@field fn fun(rect: GuiRect): position: number

---@class RelativeSolver
---@field is_relative fun(rect: GuiRect): boolean
---@field fn fun(rect: GuiRect): offset: number, source_rect: GuiRect, source_key: string

local AXIS_KEYS <const> = {
	horizontal = {min = "min_x", max = "max_x", size = "size_x"},
	vertical = {min = "min_y", max = "max_y", size = "size_y"},
}

local CROSS_KEYS <const> = {
	horizontal = {min = "min_y", max = "max_y", size = "size_y"},
	vertical = {min = "min_x", max = "max_x", size = "size_x"},
}

local AXIS_TO_SIZE <const> = {
	horizontal = "size_x",
	vertical = "size_y"
}

local DIRECTION_TO_AXIS <const> = {
	right = "horizontal",
	down = "vertical",
	left = "horizontal",
	up = "vertical"
}

local SIDE_TO_AXIS <const> = {
	right = "horizontal",
	bottom = "vertical",
	left = "horizontal",
	top = "vertical"
}

local POSITIVE_DIR <const> = {
	right = true,
	down = true,
	left = false,
	up = false
}

local POSITIVE_DIMENSION <const> = {
	min_x = false,
	max_x = true,
	min_y = false,
	max_y = true,
}

local VALID_RELATIONS <const> = {
	self = true,
	parent = true,
	prev_sibling = true,
	next_sibling = true
}

local YES = function() return true end
local NO = function() return false end

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

---An ephemeral rectangle with constraint solvers.
---@class GuiRect
local m_gui_rect = {}
m_gui_rect.__index = m_gui_rect

---@param key string
---@return number offset_from_root
---@return GuiRect root_rect
---@return string root_key
function m_gui_rect:find_root(key)
	local solver = self.solvers[key] ---@type Solver
	
	if not solver then
		error(("'%s' is not a valid property key."):format(key))
	end
	
	-- Absolute solver check before cache hit because if we're the root we return
	-- early anyway. Using the relative cache is extra work.
	if not solver.is_relative(self) then
		return 0, self, key
	end
	---@cast solver RelativeSolver
	
	local cached_prop = self.cache[key]
	if cached_prop and cached_prop.root_rect then
		return cached_prop.relative, cached_prop.root_rect, cached_prop.root_key
	end
	
	-- Dependency cycle detection
	if self.pending_relative[key] then
		error(("Dependency cycle detected in %s while trying to access property %s"):format(tostr(self), key))
	end
	
	-- Recursive root finding
	self.pending_relative[key] = true
	local offset, source_rect, source_key = solver.fn(self)
	
	local offset_from_root, root_rect, root_key = source_rect:find_root(source_key)
	self.pending_relative[key] = nil
	
	offset_from_root += offset
	
	-- Caching
	if not cached_prop then
		cached_prop = {}
		self.cache[key] = cached_prop
	end
	cached_prop.relative = offset_from_root
	cached_prop.root_rect = root_rect
	cached_prop.root_key = root_key
	
	return offset_from_root, root_rect, root_key
end

---@param key string
---@return number
function m_gui_rect:get_value(key)
	-- Cache usage
	local cached_prop = self.cache[key]
	if cached_prop then
		if not cached_prop.absolute then
			cached_prop.absolute =
				cached_prop.root_rect:get_value(cached_prop.root_key)
				+ cached_prop.relative
		end
		return cached_prop.absolute
	end
	
	-- Dependency cycle detection
	if self.pending_absolute[key] then
		error(("Dependency cycle detected in %s while trying to access property %s"):format(tostr(self), key))
	end
	
	-- Absolute position solving
	local solver = self.solvers[key]
	
	if not solver then
		error(("'%s' is not a valid property key."):format(key))
	end
	
	local value
	if solver.is_relative(self) then
		local offset, root_rect, root_key = self:find_root(key)
		
		-- We know cached_prop is nil at this point, and we know find_root has populated
		-- it, so we should grab it.
		cached_prop = self.cache[key]
		value = root_rect:get_value(root_key) + offset
	else
		self.pending_absolute[key] = true
		value = solver.fn(self)
		self.pending_absolute[key] = nil
		
		-- And of course if we're not using find_root we need to make it manually.
		cached_prop = {}
		self.cache[key] = cached_prop
	end
	
	cached_prop.absolute = value
	
	return value
end

---@param from_key string
---@param to_rect GuiRect
---@param to_key string
---@return number
function m_gui_rect:get_span(from_key, to_rect, to_key)
	local from_offset, from_root, from_root_key = self:find_root(from_key)
	local to_offset, to_root, to_root_key = to_rect:find_root(to_key)
	
	-- If they don't share a root, fall back to absolute evaluation. If the layout is
	-- properly built, these dependencies are not themselves dependent on this span.
	if from_root != to_root or from_root_key != to_root_key then
		return to_rect:get_value(to_key) - self:get_value(from_key)
	end
	
	return to_offset - from_offset
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

---@param solvers Solvers
---@param parent GuiRect? Defaults to self. Only use nil for the top level.
---@return GuiRect
local function new_rect(solvers, parent)
	---@class GuiRect
	---@field next_sibling GuiRect?
	---@field prev_sibling GuiRect?
	local rect = {
		children = {}, ---@type GuiRect[]
		pending_absolute = {}, ---@type table<string, true>
		pending_relative = {}, ---@type table<string, true>
		cache = {}, ---@type table<string, CachedProperty>
		solvers = solvers,
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

---@class AxisSolvers
---@field min Solver?
---@field max Solver?
---@field size Solver?

---@param min_solver Solver
---@param max_solver Solver
---@return AxisSolvers
local function axis_min_max(min_solver, max_solver)
	return {
		min = min_solver,
		max = max_solver,
	}
end

---@param size_solver Solver
---@param min_solver Solver
---@return AxisSolvers
local function axis_size_min(size_solver, min_solver)
	return {
		size = size_solver,
		min = min_solver,
	}
end

---@param size_solver Solver
---@param max_solver Solver
---@return AxisSolvers
local function axis_size_max(size_solver, max_solver)
	return {
		size = size_solver,
		max = max_solver,
	}
end

---A set of solvers for satisfying the constraints of a rectangle.
---@class Solvers
local m_solvers = {}
m_solvers.__index = m_solvers

---@type RelativeSolver
m_solvers.min_x = {
	is_relative = YES,
	fn = function(rect)
		return -rect:get_value("size_x"), rect, "max_x"
	end
}

---@type RelativeSolver
m_solvers.max_x = {
	is_relative = YES,
	fn = function(rect)
		return rect:get_value("size_x"), rect, "min_x"
	end
}

---@type AbsoluteSolver
m_solvers.size_x = {
	is_relative = NO,
	fn = function(rect)
		return rect:get_span("min_x", rect, "max_x")
	end
}

---@type RelativeSolver
m_solvers.min_y = {
	is_relative = YES,
	fn = function(rect)
		return -rect:get_value("size_y"), rect, "max_y"
	end
}

---@type RelativeSolver
m_solvers.max_y = {
	is_relative = YES,
	fn = function(rect)
		return rect:get_value("size_y"), rect, "min_y"
	end
}

---@type AbsoluteSolver
m_solvers.size_y = {
	is_relative = NO,
	fn = function(rect)
		return rect:get_span("min_y", rect, "max_y")
	end
}

---Creates a new set of solvers from the solvers for each axis.
---@param h_solvers AxisSolvers
---@param v_solvers AxisSolvers
---@return Solvers
local function new_solvers(h_solvers, v_solvers)
	---@class Solvers
	---@field min_x Solver
	---@field max_x Solver
	---@field size_x Solver
	---@field min_y Solver
	---@field max_y Solver
	---@field size_y Solver
	local solvers = {
		min_x = h_solvers.min,
		max_x = h_solvers.max,
		size_x = h_solvers.size,
		min_y = v_solvers.min,
		max_y = v_solvers.max,
		size_y = v_solvers.size,
	}
	
	return setmetatable(solvers, m_solvers)
end

---@param value number
---@return AbsoluteSolver
local function fixed(value)
	return {
		is_relative = NO,
		fn = function() return value end
	}
end

---@param relation Relation
---@param true_solver Solver
---@param false_solver Solver
---@return Solver
local function switch_on_sibling(relation, true_solver, false_solver)
	return {
		is_relative = function(rect)
			return rect[relation]
				and true_solver.is_relative(rect)
				or false_solver.is_relative(rect)
		end,
		fn = function(rect)
			if rect[relation] then
				return true_solver.fn(rect)
			else
				return false_solver.fn(rect)
			end
		end
	}
end

---@param anchor number
---@param offset number
---@param axis_key Axis
---@return AbsoluteSolver
local function anchor_offset(anchor, offset, axis_key)
	local axis = AXIS_KEYS[axis_key]
	local min_key, max_key = axis.min, axis.max
	return {
		is_relative = NO,
		fn = function(rect)
			local parent_min = rect.parent:get_value(min_key)
			local parent_max = rect.parent:get_value(max_key)
			
			return (parent_max - parent_min) * anchor + parent_min + offset
		end
	}
end

---@param anchor_min number
---@param anchor_max number
---@param offset_min number
---@param offset_max number
---@param axis_key Axis
---@return AxisSolvers
local function anchor_offset_axis(anchor_min, anchor_max, offset_min, offset_max, axis_key)
	
	return axis_min_max(
		anchor_offset(anchor_min, offset_min, axis_key),
		anchor_offset(anchor_max, offset_max, axis_key)
	)
end

---@param anchor_min userdata?
---@param anchor_max userdata?
---@param offset_min userdata?
---@param offset_max userdata?
---@return Solvers
local function anchor_offset_all(anchor_min, anchor_max, offset_min, offset_max)
	anchor_min = anchor_min or vec(0, 0)
	anchor_max = anchor_max or vec(1, 1)
	offset_min = offset_min or vec(0, 0)
	offset_max = offset_max or vec(0, 0)
	
	return new_solvers(
		anchor_offset_axis(anchor_min.x, anchor_max.x, offset_min.x, offset_max.x, "horizontal"),
		anchor_offset_axis(anchor_min.y, anchor_max.y, offset_min.y, offset_max.y, "vertical")
	)
end

---@param parent_anchor number
---@param child_anchor number
---@param axis_key Axis
---@return AbsoluteSolver
local function anchor_size_min(parent_anchor, child_anchor, axis_key)
	local size_key = AXIS_TO_SIZE[axis_key]
	local axis = AXIS_KEYS[axis_key]
	local min_key, max_key = axis.min, axis.max
	
	return {
		is_relative = NO,
		fn = function(rect)
			local parent_min = rect.parent:get_value(min_key)
			local parent_max = rect.parent:get_value(max_key)
			local size = rect:get_value(size_key)
			
			return (parent_max - parent_min) * parent_anchor + parent_min
				- size * child_anchor
		end
	}
end

---@param parent_anchor number
---@param child_anchor number
---@param axis_key Axis
---@return AbsoluteSolver
local function anchor_size_max(parent_anchor, child_anchor, axis_key)
	local size_key = AXIS_TO_SIZE[axis_key]
	local axis = AXIS_KEYS[axis_key]
	local min_key, max_key = axis.min, axis.max
	
	return {
		is_relative = NO,
		fn = function(rect)
			local parent_min = rect.parent:get_value(min_key)
			local parent_max = rect.parent:get_value(max_key)
			local size = rect:get_value(size_key)
			
			return (parent_max - parent_min) * parent_anchor + parent_min
				+ size * (1 - child_anchor)
		end
	}
end

---@param parent_anchor number
---@param child_anchor number
---@param size number
---@param axis_key Axis
---@return AxisSolvers
local function anchor_size_axis(parent_anchor, child_anchor, size, axis_key)
	return axis_min_max(
		anchor_offset(parent_anchor, -size * child_anchor, axis_key),
		anchor_offset(parent_anchor, size * (1 - child_anchor), axis_key)
	)
end

---@param parent_anchor userdata
---@param child_anchor userdata
---@param size userdata
---@return Solvers
local function anchor_size_all(parent_anchor, child_anchor, size)
	return new_solvers(
		anchor_size_axis(parent_anchor.x, child_anchor.x, size.x, "horizontal"),
		anchor_size_axis(parent_anchor.y, child_anchor.y, size.y, "vertical")
	)
end

---@param relative Relation
---@param offset number
---@param key string
---@return RelativeSolver
local function offset_from_edge(relative, offset, key)
	if relative == "self" then
		return {
			is_relative = YES,
			fn = function(rect)
				return offset, rect, key
			end
		}
	else
		return {
			is_relative = YES,
			fn = function(rect)
				return offset, rect[relative], key
			end
		}
	end
end

---@param ratio number
---@param vertical boolean
---@return AbsoluteSolver
local function aspect_ratio(ratio, vertical)
	if vertical then
		return {
			is_relative = NO,
			fn = function(rect)
				return rect:get_value("size_x") * ratio
			end
		}
	else
		return {
			is_relative = NO,
			fn = function(rect)
				return rect:get_value("size_y") * ratio
			end
		}
	end
end

local function after_sibling(sibling_offset, parent_offset, sibling_key, parent_key)
	---@type RelativeSolver
	return switch_on_sibling(
		"prev_sibling",
		offset_from_edge("prev_sibling", sibling_offset, sibling_key),
		offset_from_edge("parent", parent_offset, parent_key)
	)
end

---@param grow number
---@param low_key string
---@param high_key string
---@return AbsoluteSolver
local function fit_child_array(grow, low_key, high_key)
	return {
		is_relative = NO,
		fn = function(rect)
			local children = rect.children
			if not children then return 0 end
			
			return abs(children[1]:get_span(low_key, children[#children], high_key)) + grow
		end
	}
end

---Creates a set of constraints which fills the provided draw target.
---@param target userdata
---@return Solvers
local function solvers_from_target(target)
	local width, height = target:attribs()
	return new_solvers(
		axis_min_max(fixed(0), fixed(width)),
		axis_min_max(fixed(0), fixed(height))
	)
end

return {
	new_rect = new_rect,
	new_bounds = new_bounds,
	new_solvers = new_solvers,
	
	axis_min_max = axis_min_max,
	axis_size_min = axis_size_min,
	axis_size_max = axis_size_max,
	
	fixed = fixed,
	
	anchor_offset = anchor_offset,
	anchor_offset_axis = anchor_offset_axis,
	anchor_offset_all = anchor_offset_all,
	anchor_size_min = anchor_size_min,
	anchor_size_max = anchor_size_max,
	anchor_size_axis = anchor_size_axis,
	anchor_size_all = anchor_size_all,
	
	offset_from_edge = offset_from_edge,
	after_sibling = after_sibling,
	aspect_ratio = aspect_ratio,
	fit_child_array = fit_child_array,
	
	solvers_from_target = solvers_from_target,
}