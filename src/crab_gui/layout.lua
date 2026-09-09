---@class UiRect
local m_rect = {}
m_rect.__index = m_rect

---@class Bounds
---@field min userdata
---@field max userdata

---@param parent_bounds Bounds?
---@return Bounds
function m_rect:bounds(parent_bounds)
	if not parent_bounds then
		local draw_target = get_draw_target()
		parent_bounds = {
			min = vec(0, 0),
			max = vec(draw_target:width(), draw_target:height())
		}
	end
	
	local parent_size = parent_bounds.max - parent_bounds.min
	local min_pos = parent_bounds.min + parent_size * self.anchor_min
	local max_pos = parent_bounds.min + parent_size * self.anchor_max
	
	return {
		min = min_pos + self.offset_min,
		max = max_pos + self.offset_max,
	}
end

local function new_rect_raw(offset_min, offset_max, anchor_min, anchor_max)
	---@class UiRect
	local rect = {
		offset_min = offset_min,
		offset_max = offset_max,
		anchor_min = anchor_min,
		anchor_max = anchor_max,
	}
	
	return setmetatable(rect, m_rect)
end

---@class UiRectArguments
---@field offset_min userdata?
---@field offset_max userdata?
---@field anchor_min userdata?
---@field anchor_max userdata?
---@field offset userdata?
---@field size userdata?

---@param arguments UiRectArguments
---@return UiRect
local function new_rect(arguments)
	local anchor_min = arguments.anchor_min
		or vec(0, 0)
	
	local anchor_max = arguments.anchor_max
		or arguments.offset and anchor_min
		or vec(1, 1)
	
	local offset_min = arguments.offset_min
		or arguments.offset
		or vec(0, 0)
	
	local offset_max = arguments.offset_max
		or arguments.offset and offset_min
		or vec(0, 0)
	
	if arguments.size then
		offset_min -= arguments.size * anchor_min
		offset_max += arguments.size * (1 - anchor_max)
	end
	
	return new_rect_raw(
		offset_min,
		offset_max,
		anchor_min,
		anchor_max
	)
end

return {
	new_rect = new_rect,
	new_rect_raw = new_rect_raw,
}