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

---@param offset_min userdata?
---@param offset_max userdata?
---@param anchor_min userdata?
---@param anchor_max userdata?
---@return UiRect
local function new_rect(offset_min, offset_max, anchor_min, anchor_max)
	---@class UiRect
	local rect = {
		offset_min = offset_min or vec(0, 0),
		offset_max = offset_max or vec(0, 0),
		anchor_min = anchor_min or vec(0, 0),
		anchor_max = anchor_max or vec(1, 1),
	}
	
	return setmetatable(rect, m_rect)
end

---@param anchor userdata
---@param size userdata
---@param offset userdata?
---@return UiRect
local function new_rect_at(anchor, size, offset)
	offset = offset or vec(0, 0)
	
	return new_rect(
		offset - size * anchor,
		offset + size * (1 - anchor),
		anchor,
		anchor
	)
end

return {
	new_rect = new_rect,
	new_rect_at = new_rect_at,
}