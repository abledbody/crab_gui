local max = math.max
local floor = math.floor

local discard_surface = userdata("u8", 1, 1)

---@param ctx RenderRequest
local function draw_panel(ctx)
	local bounds = ctx.rect:get_bounds()
	local bounds_size = bounds:get_size()
	rrectfill(bounds.min.x, bounds.min.y, bounds_size.x, bounds_size.y, ctx.args.radius, ctx.args.col)
end

---@param gui Gui
---@param col integer? Defaults to 1
---@param radius number? Defaults to 1
local function panel(gui, col, radius)
	gui:queue_render(draw_panel, {col = col or 1, radius = radius or 1})
end

local text_halign = {
	left = function(bounds)
		return bounds.min.x
	end,
	
	center = function(bounds, width)
		return bounds.min.x + bounds:get_size().x // 2 - width // 2
	end,
	
	right = function(bounds, width)
		return bounds.max.x - width
	end
}

local text_valign = {
	top = function(bounds)
		return bounds.min.y
	end,
	
	center = function(bounds, height)
		return bounds.min.y + bounds:get_size().y // 2 - height // 2
	end,
	
	bottom = function(bounds, height)
		return bounds.max.y - height
	end
}

---@param ctx RenderRequest
local function draw_text(ctx)
	local font_cache = ctx.args.font_cache
	local style = ctx.args.style
	font_cache:set_active(false, style.primary_font)
	font_cache:set_active(true, style.secondary_font)
	
	local prev_surface = set_draw_target(discard_surface)
	local width = print(ctx.args.str, 0, 0)
	set_draw_target(prev_surface)
	
	local height = max(
		font_cache:get_active(false).descender_height,
		font_cache:get_active(true).descender_height
	)
	local bounds = ctx.rect:get_bounds()
	local x = text_halign[style.halign](bounds, width)
	local y = text_valign[style.valign](bounds, height)
	
	print(ctx.args.str, x, y, style.col)
end

---@alias HorizontalAlignment "left" | "center" | "right"
---@alias VerticalAlignment "top" | "center" | "bottom"

---@param gui Gui
---@param font_cache FontCache
---@param str string
---@param style FontStyle?
---@overload fun(gui: Gui, font_cache: FontCache, str: string, font_style: FontStyle)
local function text(gui, font_cache, str, style)
	gui:queue_render(draw_text, {
		font_cache = font_cache,
		str = str,
		style = style,
	})
end

---@param gui Gui
---@param font_cache FontCache
---@param col integer? Defaults to 1
---@param str string?
---@param font_style FontStyle?
---@param radius number? Defaults to 1
local function button(gui, id, font_cache, col, str, font_style, radius)
	panel(gui, col, radius)
	gui:queue_interactable(id)
	
	if str != nil then
		text(gui, font_cache, str, font_style)
	end
end

return {
	panel = panel,
	text = text,
	button = button,
}