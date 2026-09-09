---@class ButtonArguments
---@field enabled boolean
---@field render fun(context)

---@param gui Gui
---@param arguments ButtonArguments
---@param id any
local function button(gui, arguments, id)
	if arguments.enabled then
		gui:push_render(render, {
			
		})
	end
end

return {
	button = button
}