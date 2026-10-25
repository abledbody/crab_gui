local mouselib = require"src/mouse"
local layout = require"src/crab_gui/layout"

local insert, remove = table.insert, table.remove

---The metatable and index target for the Gui class.
---@class Gui
local m_gui = {}
m_gui.__index = m_gui

---Pushes a child rect to the stack as a child of the current rect.
---@param constraints Solvers
function m_gui:push_rect(constraints)
	local rect = layout.new_rect(constraints, self.rect, debug.getinfo(2, "Sl"))
	insert(self.rect_stack, rect)
	self.rect = rect
end

---Removes a rect from the stack, and restores its parent rect.
---@return GuiRect?
function m_gui:pop_rect()
	local old_rect = remove(self.rect_stack)
	self.rect = self.rect_stack[#self.rect_stack]
	return old_rect
end

---A sorting layer. Render requests and interactables are always below children,
---and children are sorted by priority, with the highest in front.
---@class Layer
---@field priority number?
---@field children [Layer]?
---@field render_requests [RenderRequest]
---@field interactables [Interactable]

---Pushes a sorting layer to the stack, to be sorted by the parent layer. Further
---render requests and interactables will be put on that layer.
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

---Pops a sorting layer from the stack, restoring the parent layer as the render
---request and interactable target.
---@return Layer
function m_gui:pop_layer()
	if #self.layer_stack <= 1 then
		error("Cannot pop master layer.")
	end
	
	local old_layer = remove(self.layer_stack)
	self.layer = self.layer_stack[#self.layer_stack]
	return old_layer
end

---A deferred request to render a widget.
---@class RenderRequest
---@field render fun(ctx: RenderRequest, data: any)
---@field args any
---@field id any?
---@field rect GuiRect

---Creates a request to render a widget at the current layer and in the current bounds.
---@param render fun(ctx: RenderRequest, data: any)
---@param args any
---@param id any?
function m_gui:queue_render(render, args, id)
	insert(
		self.layer.render_requests,
		{
			render = render,
			args = args,
			id = id,
			rect = self.rect,
		} --[[@as RenderRequest]]
	)
end

---An interaction target for the mouse and keyboard.
---@class Interactable
---@field intersect fun(ctx: Interactable, pt: userdata, data: any): boolean The intersection test function.
---@field id any Arbitrary data for identifying the source of the interactable.
---@field rect GuiRect The rect that defines the bounds of the interactable area.

---Creates an interaction target on the current layer and in the current bounds.
---@param id any Arbitrary data for identifying the source of the interactable.
---@param intersect? fun(ctx: Interactable, pt: userdata, data: any): boolean The intersection test function.
function m_gui:queue_interactable(id, intersect)
	insert(
		self.layer.interactables,
		{
			id = id,
			intersect = intersect or function() return true end,
			rect = self.rect,
		} --[[@as Interactable]]
	)
end

---Iterates a table ordered by a key in that table.
---@generic T
---@param table [T]
---@param key any
---@param descending boolean?
---@return fun():entry: T?, iteration: integer?, index: integer? @An iterator over every element in `table` in sorted order.
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

---Finds the topmost interactable under the mouse.
---@param mouse_pt userdata Position of the mouse in draw surface coordinates.
---@param layer Layer The layer in which to check for the hot element.
---@return Interactable? hot
function m_gui:find_hot(mouse_pt, layer)
	if layer.children then
		for child in iter_ordered(layer.children, "priority", true) do
			local interactable = self:find_hot(mouse_pt, child)
			if interactable then return interactable end
		end
	end
	
	for i = #layer.interactables, 1, -1 do
		local interactable = layer.interactables[i]
		
		local bounds = interactable.rect:get_bounds()
		if mouse_pt.x > bounds.min.x
			and mouse_pt.y > bounds.min.y
			and mouse_pt.x <= bounds.max.x
			and mouse_pt.y <= bounds.max.y
			and interactable:intersect(mouse_pt, self.data_forward[interactable.id])
		then
			return interactable
		end
	end
	
	return nil
end

---@alias EventType "entered" | "exited" | "pressed" | "released"

---Generates the set of events that have occured since the last flush.
---@return {variant: EventType, id: any}[] events
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

---Saves retained data for the next frame under an id.
---@param id any
---@param data any
function m_gui:push_data(id, data)
	self.data_forward[id] = data
end

---Retrieves retained data under an id from the last frame.
---@param id any
---@return any
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

---Draws all render requests in painter's algorithm order.
function m_gui:draw()
	self:draw_children(self.layer_stack[1])
end

---Resets GUI buffers for the next frame.
--- - Resets the active bounds and bounds stack
--- - Resets the active layer and layer stack
--- - Shifts `data_forward` to `data_retained`, and resets the forward data.
function m_gui:flush()
	self.rect = layout.new_rect(layout.solvers_from_target(get_draw_target()))
	self.rect_stack = {self.rect}
	
	local master_layer = {
		render_requests = {},
		interactables = {},
	}
	self.layer_stack = {master_layer}
	self.layer = master_layer
	
	self.data_retained = self.data_forward
	self.data_forward = {}
end

---Creates a new GUI system.
---@return Gui
local function new()
	---@type Layer
	local master_layer = {
		render_requests = {},
		interactables = {},
	}
	
	local root = layout.new_rect(layout.solvers_from_target(get_draw_target()))
	
	---@class Gui
	---@field hot Interactable?
	local gui = {
		rect = root,
		rect_stack = {root}, ---@type [GuiRect]
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
	
	m_gui = m_gui,
}