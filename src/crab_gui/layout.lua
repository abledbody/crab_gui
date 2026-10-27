local insert = table.insert
local min, max = math.min, math.max
local abs = math.abs
local huge = math.huge

local nan = ("f"):unpack("\1\0\128\127")

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

local DIRECTION_TO_EDGE <const> = {
	right = "max_x",
	down = "max_y",
	left = "min_x",
	up = "min_y"
}

local OPPOSITE_EDGE <const> = {
	min_x = "max_x",
	max_x = "min_x",
	min_y = "max_y",
	max_y = "min_y"
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

local cycle_rect_register ---@type GuiRect?
local cycle_key_register ---@type string?

local function notify_cycle()
	local rect = cycle_rect_register
	if rect then
		notify(("Key %s of rect generated on line %i of %s is self-dependent"):format(
			cycle_key_register,
			rect.source_info.currentline,
			-- + 1 because inclusive index,
			-- + 1 because pwd doesn't have a trailing slash.
			rect.source_info.short_src:sub(#pwd() + 2)
		))
		cycle_rect_register = nil
		cycle_key_register = nil
		return true
	end
	return false
end

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

---Finds the root and offset of a chain of relative solvers.
---@param key string
---@return number offset_from_root
---@return GuiRect root_rect
---@return string root_key
function m_gui_rect:find_root(key)
		local solver = self.solvers[key] or error(("'%s' is not a valid property key."):format(key))
	
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
		cycle_rect_register = self
		cycle_key_register = key
		return nan, self, key
	end
	
	-- Recursive root finding
	
	self.pending_relative[key] = true
	local offset, source_rect, source_key = solver.fn(self)
	
	local offset_from_root, root_rect, root_key = source_rect:find_root(source_key)
	self.pending_relative[key] = nil
	
	offset_from_root += offset
	
	-- Caching
	
	-- To prevent caching NaNs.
	if offset_from_root == offset_from_root then
		if not cached_prop then
			cached_prop = {}
			self.cache[key] = cached_prop
		end
		cached_prop.relative = offset_from_root
		cached_prop.root_rect = root_rect
		cached_prop.root_key = root_key
	end
	
	return offset_from_root, root_rect, root_key
end

---Safely solves a dimension of a rect.
---@param key string
---@return number
function m_gui_rect:get_value(key)
	-- Cache usage
	local cached_prop = self.cache[key]
	if cached_prop then
		if not cached_prop.absolute then
			local value =
				cached_prop.root_rect:get_value(cached_prop.root_key)
				+ cached_prop.relative
			if value != value then return value end
			cached_prop.absolute = value
		end
		return cached_prop.absolute
	end
	
	-- Dependency cycle detection
	if self.pending_absolute[key] then
		if not cycle_rect_register then
			cycle_rect_register = self
			cycle_key_register = key
		end
		return nan
	end
	
	-- Absolute position solving
	local solver = self.solvers[key] or error(("'%s' is not a valid property key."):format(key))
	
	local value
	if solver.is_relative(self) then
		local offset, root_rect, root_key = self:find_root(key)
		if offset == offset then
			value = root_rect:get_value(root_key) + offset
		else
			value = nan
		end
		cached_prop = self.cache[key]
	else
		self.pending_absolute[key] = true
		value = solver.fn(self)
		self.pending_absolute[key] = nil
	end
	
	-- Caching
	
	-- To prevent caching NaNs.
	if value == value then
		if not cached_prop then
			cached_prop = {}
			self.cache[key] = cached_prop
		end
		cached_prop.absolute = value
	end
	
	return value
end

---Safely gets the relative distance between two rect edges, even if they haven't been
---fully solved yet.
---@param from_rect GuiRect
---@param from_key string
---@param to_rect GuiRect
---@param to_key string
---@return number
function m_gui_rect.get_span(from_rect, from_key, to_rect, to_key)
	local from_offset, from_root, from_root_key = from_rect:find_root(from_key)
	local to_offset, to_root, to_root_key = to_rect:find_root(to_key)
	
	-- If they don't share a root, fall back to absolute evaluation. If the layout is
	-- properly built, these dependencies are not themselves dependent on this span.
	if from_root != to_root or from_root_key != to_root_key then
		return to_rect:get_value(to_key) - from_rect:get_value(from_key)
	end
	
	return to_offset - from_offset
end

---Forces all four edges to be solved, and returns their bounds.
---@return Bounds
function m_gui_rect:get_bounds()
	if self.bounds then return self.bounds end
	
	local min = vec(self:get_value("min_x"), self:get_value("min_y"))
	local max = vec(self:get_value("max_x"), self:get_value("max_y"))
	
	notify_cycle()
	
	self.bounds = new_bounds(min, max)
	return self.bounds
end

---@param solvers Solvers
---@param parent GuiRect? Defaults to self. Only use nil for the top level.
---@param source_info debuginfo? Defaults to the call site.
---@return GuiRect
local function new_rect(solvers, parent, source_info)
	---@class GuiRect
	---@field next_sibling GuiRect?
	---@field prev_sibling GuiRect?
	local rect = {
		children = {}, ---@type GuiRect[]
		pending_absolute = {}, ---@type table<string, true>
		pending_relative = {}, ---@type table<string, true>
		cache = {}, ---@type table<string, CachedProperty>
		solvers = solvers,
		source_info = source_info or debug.getinfo(2, "Sl")
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

---A set of solvers for one axis. Two are provided, and a third is inferred.
---@class AxisSolvers
---@field min Solver?
---@field max Solver?
---@field size Solver?

---Infers size from min and max.
---@param min_solver Solver
---@param max_solver Solver
---@return AxisSolvers
local function axis_min_max(min_solver, max_solver)
	return {
		min = min_solver,
		max = max_solver,
	}
end

---Infers max from size and min.
---@param size_solver Solver
---@param min_solver Solver
---@return AxisSolvers
local function axis_size_min(size_solver, min_solver)
	return {
		size = size_solver,
		min = min_solver,
	}
end

---Infers min from size and max.
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

---Returns an absolute value. Can never cause a cycle.
---@param value number
---@return AbsoluteSolver
local function fixed(value)
	return {
		is_relative = NO,
		fn = function() return value end
	}
end

---Switches between two solvers depending on whether the rect has the specified
---sibling.
---@param relation Relation
---@param present_solver Solver
---@param absent_solver Solver
---@return Solver
local function switch_on_sibling(relation, present_solver, absent_solver)
	return {
		is_relative = function(rect)
			if rect[relation] then
				return present_solver.is_relative(rect)
			else
				return absent_solver.is_relative(rect)
			end
		end,
		fn = function(rect)
			if rect[relation] then
				return present_solver.fn(rect)
			else
				return absent_solver.fn(rect)
			end
		end
	}
end

---Places the edge at an offset from a certain perunitage across the rect's parent.
---@param anchor number The relative position of the edge to the parent before the offset is applied.
---@param offset number The absolute offset from the anchor.
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

---Constructs an axis solver where both edges are anchor_offset.
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

---Constructs a set of solvers where every edge is anchor_offset.
---@param anchor_min userdata? Defaults to vec(0, 0)
---@param anchor_max userdata? Defaults to vec(1, 1)
---@param offset_min userdata? Defaults to vec(0, 0)
---@param offset_max userdata? Defaults to vec(0, 0)
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

---Creates a minimum edge where the child is a fixed size, growing from its anchor
---as a perunitage, which is collocated with the parent's anchor as a perunitage.
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

---Creates a maximum edge where the child is a fixed size, growing from its anchor
---as a perunitage, which is collocated with the parent's anchor as a perunitage.
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

---Constructs an axis solver where the child is a fixed size, growing from its anchor
---as a perunitage, which is collocated with the parent's anchor as a perunitage.
---@param parent_anchor number
---@param child_anchor number
---@param size number
---@param axis_key Axis
---@return AxisSolvers
local function anchor_size_axis(parent_anchor, child_anchor, size, axis_key)
	return axis_size_min(
		fixed(size),
		anchor_offset(parent_anchor, -size * child_anchor, axis_key)
	)
end

---Constructs a set of solvers where the child is a fixed size, growing from its anchor
---as a perunitage, which is collocated with the parent's anchor as a perunitage.
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

---Offsets the edge from another edge on the rect or one of its relatives.
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

---Creates a size which is some ratio of the cross axis's size.
---@param ratio number
---@param is_vertical boolean Whether the solver operates on the vertical axis.
---@return AbsoluteSolver
local function aspect_ratio(ratio, is_vertical)
	if is_vertical then
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

---Places the edge a certain distance from an edge on the rect's previous sibling, or
---a certain distance from an edge of the parent if no previous sibling exists.
---@param sibling_offset number
---@param parent_offset number
---@param sibling_key string
---@param parent_key string
---@return AbsoluteSolver|RelativeSolver
local function after_sibling(sibling_offset, parent_offset, sibling_key, parent_key)
	---@type RelativeSolver
	return switch_on_sibling(
		"prev_sibling",
		offset_from_edge("prev_sibling", sibling_offset, sibling_key),
		offset_from_edge("parent", parent_offset, parent_key)
	)
end

---Faster alternative to fit_to_children which only works on children which are
---strictly arrayed in a sequence.
---@param grow number How much additional size to add.
---@param direction Direction Which direction the array grows in.
---@return AbsoluteSolver
local function fit_child_array(grow, direction)
	local high_key = DIRECTION_TO_EDGE[direction]
	local low_key = OPPOSITE_EDGE[high_key]
	
	---@type AbsoluteSolver
	return {
		is_relative = NO,
		fn = function(rect)
			local children = rect.children
			if #children == 0 then return grow end
			
			return abs(children[1]:get_span(low_key, children[#children], high_key)) + grow
		end
	}
end

---Creates a size from the extremes of all children which do not depend on this size.
---@param grow number How much additional size to add.
---@param axis_key Axis
---@return AbsoluteSolver
local function fit_to_children(grow, axis_key)
	local axis = AXIS_KEYS[axis_key]
	local min_key, max_key = axis.min, axis.max
	local size_key = AXIS_TO_SIZE[axis_key]
	
	---@type AbsoluteSolver
	return {
		is_relative = NO,
		fn = function(rect)
			local min_extremum = huge
			local max_extremum = -huge
			for _, child in ipairs(rect.children) do
				local min_offset = rect:get_span(min_key, child, min_key)
				if cycle_rect_register == rect and cycle_key_register == size_key then
					cycle_rect_register = nil
					cycle_key_register = nil
				elseif not cycle_rect_register then
					min_extremum = min(min_extremum, min_offset)
				end
				
				local max_offset = rect:get_span(min_key, child, max_key)
				if cycle_rect_register == rect and cycle_key_register == size_key then
					cycle_rect_register = nil
					cycle_key_register = nil
				elseif not cycle_rect_register then
					max_extremum = max(max_extremum, max_offset)
				end
			end
			
			if min_extremum == huge or max_extremum == -huge then
				return grow
			end
			
			return max_extremum - min_extremum + grow
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
	YES = YES,
	NO = NO, -- What part of NO() don't you understand?
	
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
	fit_to_children = fit_to_children,
	
	solvers_from_target = solvers_from_target,
}