local mouselib = require"src/mouse"

local insert, remove = table.insert, table.remove

---@class Gui
local m_gui = {}
m_gui.__index = m_gui

---@param rect UiRect
function m_gui:push_rect(rect)
	self.bounds = rect:bounds(self.bounds)
	insert(self.bounds_stack, self.bounds)
end

---@return Bounds?
function m_gui:pop_rect()
	local old_bounds = remove(self.bounds_stack)
	self.bounds = self.bounds_stack[#self.bounds_stack]
	return old_bounds
end

---@class Layer
---@field priority number?
---@field children [Layer]?
---@field render_requests [RenderRequest]
---@field interactables [Interactable]

---@param priority number
function m_gui:push_layer(priority)
	self.layer.children = self.layer.children or {}
	
	---@type Layer
	local layer = {
		priority = priority,
		render_requests = {},
		interactables = {},
	}
	
	insert(self.layer.children, layer)
	insert(self.layer_stack, layer)
	self.layer = layer
end

---@return Layer
function m_gui:pop_layer()
	if #self.layer_stack <= 1 then
		error("Cannot pop master layer.")
	end
	
	local old_layer = remove(self.layer_stack)
	self.layer = self.layer_stack[#self.layer_stack]
	return old_layer
end

---@class RenderRequest
---@field render fun(ctx: RenderRequest, data: any)
---@field args any
---@field id any?
---@field bounds Bounds

---@param render fun(ctx: RenderRequest, data: any)
---@param args any
---@param id any?
function m_gui:push_render(render, args, id)
	insert(
		self.layer.render_requests,
		{
			render = render,
			args = args,
			id = id,
			bounds = self.bounds,
		} --[[@as RenderRequest]]
	)
end

---@class Interactable
---@field intersect fun(ctx: Interactable, pt: userdata, data: any): boolean
---@field id any
---@field bounds Bounds

---@param intersect? fun(ctx: Interactable, pt: userdata, data: any): boolean
---@param id any
function m_gui:push_interactable(intersect, id)
	insert(
		self.layer.interactables,
		{
			intersect = intersect or function() return true end,
			id = id,
			bounds = self.bounds,
		} --[[@as Interactable]]
	)
end

---@generic T
---@param table [T]
---@param key any
---@param descending boolean?
---@return fun():entry: T?, iteration: integer?, index: integer?
local function iter_ordered(table, key, descending)
	local ud = userdata("f64", 2, #table)
	for i = 1, #table do
		ud:set(0, i - 1, table[i][key], i)
	end
	
	ud:sort(0, descending)
	
	local i = 0
	return function()
		if i >= #table then return end
		local j = ud:get(1, i)
		i += 1
		return table[j], i, j
	end
end

---@param mouse_pt userdata
---@param layer Layer
---@return Interactable?
function m_gui:find_hot(mouse_pt, layer)
	if layer.children then
		for child in iter_ordered(layer.children, "priority", true) do
			local interactable = self:find_hot(mouse_pt, child)
			if interactable then return interactable end
		end
	end
	
	for i = #layer.interactables, 1, -1 do
		local interactable = layer.interactables[i]
		
		if mouse_pt.x > interactable.bounds.min.x
			and mouse_pt.y > interactable.bounds.min.y
			and mouse_pt.x <= interactable.bounds.max.x
			and mouse_pt.y <= interactable.bounds.max.y
			and interactable:intersect(mouse_pt, self.data_forward[interactable.id])
		then
			return interactable
		end
	end
	
	return nil
end

function m_gui:event_step()
	local new_hot = self:find_hot(mouselib.pos, self.layer_stack[1])
	
	local events = {}
	
	if self.hot and new_hot then -- Still have a hot
		if self.hot.id != new_hot.id then -- Hot changed
			insert(
				events,
				{
					variant = "exited",
					id = self.hot.id,
				}
			)
			insert(
				events,
				{
					variant = "entered",
					id = new_hot.id,
				}
			)
		end
	elseif self.hot and not new_hot then -- Lost hot
		insert(
			events,
			{
				variant = "exited",
				id = self.hot.id,
			}
		)
	elseif not self.hot and new_hot then -- Gained hot
		insert(
			events,
			{
				variant = "entered",
				id = new_hot.id,
			}
		)
	end
	
	for i = 0, 4 do
		if mouselib.down(i) and new_hot then
			insert(
				events,
				{
					variant = "pressed",
					id = new_hot.id,
				}
			)
			self.active[i] = new_hot.id
		end
		
		local active_id = self.active[i]
		
		if mouselib.up(i) and active_id then
			if new_hot and new_hot.id == active_id then
				insert(
					events,
					{
						variant = "released",
						id = active_id,
					}
				)
			else
				insert(
					events,
					{
						variant = "dropped",
						id = active_id,
					}
				)
			end
			self.active[i] = nil
		end
	end
	
	self.hot = new_hot
	
	return events
end

function m_gui:push_data(id, data)
	self.data_forward[id] = data
end

function m_gui:pull_data(id)
	return self.data_retained[id]
end

---@param layer Layer
function m_gui:draw_children(layer)
	for _, request in ipairs(layer.render_requests) do
		request:render(self.data_forward[request.id])
	end
	
	if layer.children then
		for child in iter_ordered(layer.children, "priority") do
			self:draw_children(child)
		end
	end
end

function m_gui:draw()
	self:draw_children(self.layer_stack[1])
end

function m_gui:flush()
	self.bounds = nil
	self.bounds_stack = {}
	
	local master_layer = {
		render_requests = {},
		interactables = {},
	}
	self.layer_stack = {master_layer}
	self.layer = master_layer
	
	self.data_retained = self.data_forward
	self.data_forward = {}
end

---@return Gui
local function new()
	---@type Layer
	local master_layer = {
		render_requests = {},
		interactables = {},
	}
	
	---@class Gui
	---@field bounds Bounds?
	---@field hot Interactable?
	local gui = {
		bounds_stack = {}, ---@type [Bounds]
		layer_stack = {master_layer}, ---@type [Layer]
		layer = master_layer,
		data_retained = {}, ---@type table<any, any>
		data_forward = {}, ---@type table<any, any>
		active = {} ---@type [any?]
	}
	
	return setmetatable(gui, m_gui)
end

return {
	new = new,
}