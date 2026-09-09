include"src/require.lua"

local floor = math.floor
local remove = table.remove

local example_scripts

local OPTION_PADDING <const> = 6
local RECT_PADDING <const> = 3
local FONT_HEIGHT = 8

local rect_width = 0
local y_off = 0
local option = 1

local function lerp(t, a, b)
	return (b - a) * t + a
end

function _init()
	example_scripts = ls("src/examples")
	for i = #example_scripts, 1, -1 do
		if example_scripts[i]:sub(-4) == ".lua" then
			example_scripts[i] = example_scripts[i]:sub(1, -5)
		else
			remove(example_scripts, i)
		end
	end
end

function _update()
	if (btnp(3)) then
		option = option % #example_scripts + 1
		sfx(0)
	end
	if (btnp(2)) then
		option = (option - 2) % #example_scripts + 1
		sfx(0)
	end
	
	clip(0, 0, 0, 0)
	local w = print(example_scripts[option], 0, 0)
	clip()
	
	local target_y_off = floor((option - 1) * (FONT_HEIGHT + OPTION_PADDING))
	y_off = lerp(0.7, target_y_off, y_off)
	rect_width = lerp(0.7, w, rect_width)
	
	if btnp(4) then
		_init = nil
		_draw = nil
		_update = nil
		include("src/examples/" .. example_scripts[option] .. ".lua")
		if _init then _init() end
	end
end

function _draw()
	cls()
	
	local rect_x0 = 240.5 - rect_width * 0.5 - RECT_PADDING
	local rect_y0 = 135.5 - FONT_HEIGHT * 0.5 - RECT_PADDING
	local rect_x1 = rect_x0 + rect_width + RECT_PADDING * 2 - 1
	local rect_y1 = rect_y0 + FONT_HEIGHT + RECT_PADDING * 2 - 1
	
	rectfill(rect_x0 - 1, rect_y0 - 1, rect_x1 + 1, rect_y1 + 1, 7)
	rect(rect_x0, rect_y0, rect_x1, rect_y1, 0)
	
	for i, v in ipairs(example_scripts) do
		clip(0, 0, 0, 0)
		local w = print(v, 0, 0)
		clip()
		
		local x = 240.5 - w * 0.5
		local y = 135.5
			- floor(FONT_HEIGHT * 0.5)
			+ (i - 1) * (FONT_HEIGHT + OPTION_PADDING)
			- y_off
		
		print("\^o0ff" .. v, x, y, 7)
	end
end