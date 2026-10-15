local crab = require"src/crab_gui/gui"
local layout = require"src/crab_gui/layout"
local sw = require"src/crab_gui/std_widgets"
local text_rendering = require"src/crab_gui/text_rendering"
local gui = crab.new()
local font_cache = text_rendering.new_font_cache()

local c_left_panel =
	layout.anchor_offset_all(vec(0, 0), vec(0.3, 1), vec(2, 2), vec(-1, -2))

local c_right_panel =
	layout.anchor_offset_all(vec(0.3, 0), vec(1, 1), vec(1, 2), vec(-2, -2))

local c_upper_left_panel =
	layout.anchor_offset_all(vec(0, 0), vec(1, 0), vec(2, 2), vec(-2, 20))

local c_lower_left_panel = layout.anchor_offset_all(nil, nil, vec(2, 22), vec(-2, -2))

local c_left_panel_item =
	layout.array(2, 2, 2, 1, "down", layout.offset_from_edge(12, "min_y"))

local c_right_panel_item = layout.new_constraints(
	layout.offset_from_edge(-70, "max_x"),
	layout.offset_from_rect("parent", "min_y", 4),
	layout.after_sibling(-4, -4, "max_x", "min_x"),
	layout.sum(
		layout.offset_from_rect("parent", "min_y", 4),
		layout.cross_ratio(0.5, "min_x", "max_x")
	)
)

local font_style = text_rendering.default_style{col = 7, halign = "center", valign = "center"}

local function do_gui()
	gui:push_rect(layout.anchor_size_all(
		vec(0.5, 0.5),
		vec(math.cos(t() * 0.7) * 210 + 270, math.sin(t() * 0.8652) * 105 + 165)
	))
	sw.panel(gui, 1, 6)
	
	gui:push_rect(c_right_panel)
	sw.panel(gui, 16, 2)
	
	for _ = 1, 3 do
		gui:push_rect(c_right_panel_item)
		sw.panel(gui, 1, 4)
		gui:pop_rect()
	end
	gui:pop_rect()
	
	gui:push_rect(c_left_panel)
	sw.panel(gui, 16, 2)
	
	gui:push_rect(c_upper_left_panel)
	sw.panel(gui, 1, 2)
	sw.text(gui, font_cache, "\^o0ffWow!", font_style)
	gui:pop_rect()
	
	gui:push_rect(c_lower_left_panel)
	sw.panel(gui, 1, 2)
	
	for i = 1, 10 do
		gui:push_rect(c_left_panel_item)
		sw.panel(gui, 16, 2)
		sw.text(gui, font_cache, "\^o0ffItem "..i, font_style)
		gui:pop_rect()
	end
	gui:pop_rect()
	
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