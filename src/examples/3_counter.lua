local crab = require"src/crab_gui/gui"
local layout = require"src/crab_gui/layout"
local sw = require"src/crab_gui/std_widgets"
local text_rendering = require"src/crab_gui/text_rendering"
local mouselib = require"src/mouse"
local gui = crab.new()
local font_cache = text_rendering.new_font_cache()

local number

local c_main_panel = layout.new_solvers(
	layout.axis_size_min(
		layout.fit_child_array(4, "right"),
		layout.anchor_size_min(0.5, 0.5, "horizontal")
	),
	layout.axis_size_min(
		layout.fit_to_children(4, "vertical"),
		layout.anchor_size_min(0.5, 0.5, "vertical")
	)
)

local c_button_panel = layout.new_solvers(
	layout.axis_size_min(
		layout.fit_to_children(0, "horizontal"),
		layout.offset_from_edge("parent", 2, "min_x")
	),
	layout.axis_size_min(
		layout.fit_child_array(0, "down"),
		layout.offset_from_edge("parent", 2, "min_y")
	)
)

local c_button = layout.new_solvers(
	layout.axis_size_min(
		layout.fixed(16),
		layout.offset_from_edge("parent", 0, "min_x")
	),
	layout.axis_size_min(
		layout.aspect_ratio(1, true),
		layout.after_sibling(2, 0, "max_y", "min_y")
	)
)

local c_number_panel = layout.new_solvers(
	layout.axis_size_min(
		layout.fixed(20),
		layout.after_sibling(2, 2, "max_x", "min_x")
	),
	layout.axis_min_max(
		layout.offset_from_edge("parent", 2, "min_y"),
		layout.offset_from_edge("parent", -2, "max_y")
	)
)

local font_style = text_rendering.default_style{col = 7, halign = "center", valign = "center"}

local function do_gui()
	gui:push_rect(c_main_panel)
	sw.panel(gui, 1, 6)
	
	gui:push_rect(c_button_panel)
	sw.panel(gui, 1, 6)
	gui:push_rect(c_button)
	sw.button(gui, "increment_button", font_cache, 16, "\^o0ff+", font_style, 2)
	gui:pop_rect()
	
	gui:push_rect(c_button)
	sw.button(gui, "decrement_button", font_cache, 16, "\^o0ff-", font_style, 2)
	gui:pop_rect()
	gui:pop_rect()
	
	gui:push_rect(c_number_panel)
	sw.panel(gui, 16, 4)
	sw.text(gui, font_cache, ("\^o0ff%i"):format(number), font_style)
	gui:pop_rect()
	
	gui:pop_rect()
end

local event_handlers = {
	increment_button = {
		released = function() number += 1 end,
	},
	decrement_button = {
		released = function() number -= 1 end,
	}
}

---@param events {variant: "entered"|"exited"|"pressed"|"released", id: any}[]
local function dispatch_events(events)
	for _, event in ipairs(events) do
		printh(("EVENT: %s was %s"):format(tostr(event.id), event.variant))
		
		if event_handlers[event.id] then
			local handler = event_handlers[event.id]
			if handler[event.variant] then
				handler[event.variant]()
			end
		end
	end
end

function _init()
	number = 0
end

function _update()
	mouselib.frame_start()
	gui:flush()
	do_gui()
	dispatch_events(gui:event_step())
end

function _draw()
	cls()
	gui:draw()
	print(("\^o0ffCPU: %.2f%%"):format(stat(1) * 100), 1, 1, 7)
end

require"src/error_explorer"