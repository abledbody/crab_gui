local crab = require"src/crab_gui/gui"
local crab_layout = require"src/crab_gui/layout"
local gui = crab.new()

---@param ctx RenderRequest
local function draw_panel(ctx)
	local bounds_min = ctx.bounds.min
	local bounds_max = ctx.bounds.max
	local size = bounds_max // 1 - bounds_min // 1
	rrectfill(bounds_min.x, bounds_min.y, size.x, size.y, ctx.args.radius, ctx.args.col)
end

---@param gui Gui
---@param radius number
---@param col integer
local function panel(gui, radius, col)
	gui:push_render(draw_panel, {radius = radius, col = col})
end

local left_panel_rect =
	crab_layout.new_rect(vec(2, 2), vec(-1, -2), vec(0, 0), vec(0.3, 1))

local right_panel_rect =
	crab_layout.new_rect(vec(1, 2), vec(-2, -2), vec(0.3, 0), vec(1, 1))

local upper_left_panel_rect =
	crab_layout.new_rect(vec(2, 2), vec(-2, 20), vec(0, 0), vec(1, 0))

local lower_left_panel_rect = crab_layout.new_rect(vec(2, 22), vec(-2, -2))

local function do_gui()
	gui:push_rect(crab_layout.new_rect_at(
		vec(0.5, 0.5),
		vec(math.cos(t() * 0.7) * 210 + 270, math.sin(t() * 0.8652) * 105 + 165)
	))
	panel(gui, 6, 1)
	
	gui:push_rect(left_panel_rect)
	panel(gui, 2, 16)
	
	gui:push_rect(upper_left_panel_rect)
	panel(gui, 2, 1)
	gui:pop_rect()
	gui:push_rect(lower_left_panel_rect)
	panel(gui, 2, 1)
	gui:pop_rect()
	
	gui:pop_rect()
	
	gui:push_rect(right_panel_rect)
	panel(gui, 2, 16)
	gui:pop_rect()
	
	gui:pop_rect()
end

function _update()
	gui:flush()
	do_gui()
	gui:event_step()
end

function _draw()
	cls()
	gui:draw()
	print(("\^o0ffCPU: %.2f%%"):format(stat(1) * 100), 1, 1, 7)
end

require"src/error_explorer"