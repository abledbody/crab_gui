local crab = require"src/crab_gui/gui"
local crab_layout = require"src/crab_gui/layout"
local sw = require"src/crab_gui/std_widgets"
local text_rendering = require"src/crab_gui/text_rendering"
local gui = crab.new()

local font_cache = text_rendering.new_font_cache()
font_cache:add("charcoal", fetch(DATP .. "fonts/charcoal.font"))

local top_left_style   = text_rendering.default_style{col = 7, halign = "left"  , valign = "top", primary_font = "charcoal"}
local top_center_style = text_rendering.default_style{col = 7, halign = "center", valign = "top", primary_font = "charcoal"}
local top_right_style  = text_rendering.default_style{col = 7, halign = "right" , valign = "top", primary_font = "charcoal"}

local center_left_style   = text_rendering.default_style{col = 7, halign = "left"  , valign = "center", primary_font = "charcoal"}
local center_center_style = text_rendering.default_style{col = 7, halign = "center", valign = "center", primary_font = "charcoal"}
local center_right_style  = text_rendering.default_style{col = 7, halign = "right" , valign = "center", primary_font = "charcoal"}

local bottom_left_style   = text_rendering.default_style{col = 7, halign = "left"  , valign = "bottom", primary_font = "charcoal"}
local bottom_center_style = text_rendering.default_style{col = 7, halign = "center", valign = "bottom", primary_font = "charcoal"}
local bottom_right_style  = text_rendering.default_style{col = 7, halign = "right" , valign = "bottom", primary_font = "charcoal"}

local fonts_style_1 = text_rendering.default_style{col = 10, halign = "center", valign = "center", primary_font = "lil", secondary_font = "lil_mono"}
local fonts_style_2 = text_rendering.default_style{col = 28, halign = "center", valign = "center", primary_font = "p8" , secondary_font = "charcoal"}

local function do_gui()
	sw.text(gui, font_cache, "top left"     , top_left_style)
	sw.text(gui, font_cache, "top center"   , top_center_style)
	sw.text(gui, font_cache, "top right"    , top_right_style)
	sw.text(gui, font_cache, "center left"  , center_left_style)
	sw.text(gui, font_cache, "center center", center_center_style)
	sw.text(gui, font_cache, "center right" , center_right_style)
	sw.text(gui, font_cache, "bottom left"  , bottom_left_style)
	sw.text(gui, font_cache, "bottom center", bottom_center_style)
	sw.text(gui, font_cache, "bottom right" , bottom_right_style)
	
	gui:push_rect(crab_layout.new_rect(nil, nil, vec(0, 0), vec(0.5, 0.5)))
	sw.text(gui, font_cache, "lil \014& lil_mono", fonts_style_1)
	gui:pop_rect()
	
	gui:push_rect(crab_layout.new_rect(nil, nil, vec(0.5, 0), vec(1, 0.5)))
	sw.text(gui, font_cache, "p8 \014& charcoal", fonts_style_2)
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
	font_cache:set_active(false, "lil")
	print(("\^o0ffCPU: %.2f%%"):format(stat(1) * 100), 1, 11, 7)
end

require"src/error_explorer"