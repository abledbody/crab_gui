---@param ctx RenderRequest
local function draw_panel(ctx)
	local bounds_min = ctx.bounds.min
	local bounds_size = ctx.bounds:get_size()
	rrectfill(bounds_min.x, bounds_min.y, bounds_size.x, bounds_size.y, ctx.args.radius, ctx.args.col)
end

---@param gui Gui
---@param col integer? Defaults to 1
---@param radius number? Defaults to 1
local function panel(gui, col, radius)
	gui:push_render(draw_panel, {col = col or 1, radius = radius or 1})
end

return {
	panel = panel,
}