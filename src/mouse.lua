-- I'm not afraid to put non-instanced state in here, because input by definition
-- is global. Just keep in mind that most feature functionality is not like this.
local state = {
	last_mb = 0, --- The last mouse button state.
	mb = 0, --- The current mouse button state.
	delta = vec(0, 0), --- The mouse delta from the last frame.
	pos = vec(0, 0), --- The current mouse position.
	scroll = vec(0, 0),
}

--- Must be called at the start of each frame to update the mouse state.
local function frame_start()
	local mx, my, new_mb, sx, sy = mouse()
	local new_mouse_pos = vec(mx, my)
	state.delta = new_mouse_pos - state.pos
	state.pos = new_mouse_pos
	state.scroll = vec(sx, sy)
	state.last_mb = state.mb
	state.mb = new_mb
end

--- Checks if a mouse button is currently pressed.
--- @param button integer? The mouse button to check. Defaults to 0 (lmb)
--- @return boolean is_pressed Whether the button is currently pressed.
local function pressed(button)
	button = button or 0
	return state.mb & (1 << button) ~= 0
end

--- Checks if a mouse button was pressed this frame.
--- @param button integer? The mouse button to check. Defaults to 0 (lmb)
--- @return boolean was_pressed Whether the button was pressed this frame.
local function down(button)
	button = button or 0
	return ~state.last_mb & state.mb & (1 << button) ~= 0
end

--- Checks if a mouse button was released this frame.
--- @param button integer? The mouse button to check. Defaults to 0 (lmb)
--- @return boolean was_released Whether the button was released this frame.
local function up(button)
	button = button or 0
	return state.last_mb & ~state.mb & (1 << button) ~= 0
end

return setmetatable(
	{
		frame_start = frame_start,
		pressed = pressed,
		down = down,
		up = up,
	},
	{
		__index = state,
		__newindex = function() error("Mouse state is read-only.") end
	}
)
