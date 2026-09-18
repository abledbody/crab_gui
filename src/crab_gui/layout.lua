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

---@class UiRect
local m_rect = {}
m_rect.__index = m_rect

---Reifies the bounds of the UiRect based on the parent's bounds.
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
	
	return new_bounds(min_pos + self.offset_min, max_pos + self.offset_max)
end

---Creates a new UiRect.
---@param offset_min userdata? The position of the low corner relative to the low anchor. Defaults to `0, 0`
---@param offset_max userdata? The position of the high corner relative to the high anchor. Defaults to `0, 0`
---@param anchor_min userdata? How far from the parent bounds' low corner to its high corner the minimum anchor of the UiRect is as a perunitage. Defaults to `0, 0`
---@param anchor_max userdata? How far from the parent bounds' low corner to its high corner the maximum anchor of the UiRect is as a perunitage. Defaults to `1, 1`
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
---An anchor of `0.5, 0.5` will put the anchor in the centerof the UiRect.
---@param anchor userdata How far from the parent bounds' low corner to its high corner both anchors of the UiRect are as a perunitage.
---@param size userdata The width and height of the UiRect.
---@param offset userdata? How far the UiRect will be shifted relative to the anchor position.
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
	new_bounds = new_bounds,
	new_rect = new_rect,
	new_rect_at = new_rect_at,
}