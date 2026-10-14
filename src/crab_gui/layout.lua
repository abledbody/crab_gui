local insert = table.insert

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

---@class GuiRect
local m_gui_rect = {}
m_gui_rect.__index = m_gui_rect

---@param key string
---@param default any
function m_gui_rect:lock_key(key, default)
	if self.pending[key] then
		printh(("Dependency cycle detected on %s while trying to fetch %s"):format(tostr(self), key))
		return default
	end
	
	self.pending[key] = true
end

---@generic T
---@param key string
---@param default T
---@return T
function m_gui_rect:get_value(key, default)
	if self[key] then return self[key] end
	
	local fallback = self:lock_key(key, default)
	if fallback then return fallback end
	
	self[key] = self.constraints[key](self)
	self.pending[key] = nil
	
	return self[key]
end

---@return Bounds
function m_gui_rect:get_bounds()
	if self.bounds then return self.bounds end
	local min = vec(self:get_value("x_min", 0), self:get_value("y_min", 0))
	local max = vec(self:get_value("x_max", 16), self:get_value("y_max", 16))
	
	self.bounds = new_bounds(min, max)
	return self.bounds
end

---@param parent GuiRect? Defaults to self. Only use nil for the top level.
---@param constraints Constraints
---@return GuiRect
local function new_rect(parent, constraints)
	---@class GuiRect
	---@field parent GuiRect
	---@field x_min number?
	---@field y_min number?
	---@field x_max number?
	---@field y_max number?
	local rect = {
		children = {}, ---@type GuiRect[]
		pending = {}, ---@type table<string, true?>
		constraints = constraints,
	}
	
	if parent then
		insert(parent.children, rect)
	end
	
	rect.parent = parent or rect
	
	return setmetatable(rect, m_gui_rect)
end

---@class Constraints
local m_constraints = {}
m_constraints.__index = m_constraints

function m_constraints:x_min() return 0 end
function m_constraints:y_min() return 0 end
function m_constraints:x_max() return 16 end
function m_constraints:y_max() return 16 end

---@param x_min? fun(self: GuiRect): number
---@param y_min? fun(self: GuiRect): number
---@param x_max? fun(self: GuiRect): number
---@param y_max? fun(self: GuiRect): number
---@return Constraints
local function new_constraints(x_min, y_min, x_max, y_max)
	---@class Constraints
	local constraints = {
		x_min = x_min,
		y_min = y_min,
		x_max = x_max,
		y_max = y_max,
	}
	
	return setmetatable(constraints, m_constraints)
end

---@param offset_min number
---@param offset_max number
---@param anchor_min number
---@param anchor_max number
local function solve_offset_anchor(parent_min, parent_max, offset_min, offset_max, anchor_min, anchor_max)
	local parent_size = parent_max - parent_min
	return offset_min + parent_min + parent_size * anchor_min,
		offset_max + parent_min + parent_size * anchor_max
end

---Applies the constraints of an anchored rectangle
---@param offset_min userdata? The position of the low corner relative to the low anchor. Defaults to `0, 0`
---@param offset_max userdata? The position of the high corner relative to the high anchor. Defaults to `0, 0`
---@param anchor_min userdata? How far from the parent bounds' low corner to its high corner the minimum anchor of the UiRect is as a perunitage. Defaults to `0, 0`
---@param anchor_max userdata? How far from the parent bounds' low corner to its high corner the maximum anchor of the UiRect is as a perunitage. Defaults to `1, 1`
local function anchors_and_offsets(offset_min, offset_max, anchor_min, anchor_max)
	offset_min = offset_min or vec(0, 0)
	offset_max = offset_max or vec(0, 0)
	anchor_min = anchor_min or vec(0, 0)
	anchor_max = anchor_max or vec(1, 1)
	
	local ox0, oy0 = offset_min.x, offset_min.y
	local ox1, oy1 = offset_max.x, offset_max.y
	local ax0, ay0 = anchor_min.x, anchor_min.y
	local ax1, ay1 = anchor_max.x, anchor_max.y
	
	return new_constraints(
		function(rect)
			local parent_min = rect.parent:get_value("x_min", 0)
			local parent_max = rect.parent:get_value("x_max", 16)
			
			rect.x_min, rect.x_max =
				solve_offset_anchor(parent_min, parent_max, ox0, ox1, ax0, ax1)
			return rect.x_min
		end,
	
		function(rect)
			local parent_min = rect.parent:get_value("y_min", 0)
			local parent_max = rect.parent:get_value("y_max", 16)
			
			rect.y_min, rect.y_max =
				solve_offset_anchor(parent_min, parent_max, oy0, oy1, ay0, ay1)
			return rect.y_min
		end,
	
		function(rect)
			local parent_min = rect.parent:get_value("x_min", 0)
			local parent_max = rect.parent:get_value("x_max", 16)
			
			rect.x_min, rect.x_max =
				solve_offset_anchor(parent_min, parent_max, ox0, ox1, ax0, ax1)
			return rect.x_max
		end,
	
		function(rect)
			local parent_min = rect.parent:get_value("y_min", 0)
			local parent_max = rect.parent:get_value("y_max", 16)
			
			rect.y_min, rect.y_max =
				solve_offset_anchor(parent_min, parent_max, oy0, oy1, ay0, ay1)
			return rect.y_max
		end
	)
end

---Creates a new UiRect with a fixed size, assuming that the minimum and maximum
---anchors are the same.
---
---The anchor is both where on the parent bounds the UiRect will be positioned
---relative to, and also the fraction of the size that will extend past the low corner.
---
---An anchor of `0, 0` will put the anchor on the top left corner of the UiRect.
---
---An anchor of `1, 1` will put the anchor on the bottom right corner of the UiRect.
---
---An anchor of `0.5, 0.5` will put the anchor in the center of the UiRect.
---@param anchor userdata How far from the parent bounds' low corner to its high corner both anchors of the UiRect are as a perunitage.
---@param size userdata The width and height of the UiRect.
---@param offset userdata? How far the UiRect will be shifted relative to the anchor position.
local function anchor_and_size(anchor, size, offset)
	offset = offset or vec(0, 0)
	
	return anchors_and_offsets(
		offset - size * anchor,
		offset + size * (1 - anchor),
		anchor,
		anchor
	)
end

---@param target userdata
---@return Constraints
local function constraints_of_target(target)
	local width, height = target:attribs()
	return new_constraints(nil, nil,
		function() return width end,
		function() return height end
	)
end

return {
	new_rect = new_rect,
	new_constraints = new_constraints,
	constraints_of_target = constraints_of_target,
	new_bounds = new_bounds,
	anchors_and_offsets = anchors_and_offsets,
	anchor_and_size = anchor_and_size,
}