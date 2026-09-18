local max = math.max

local glyph_buffer = userdata("u8", 8)

---Finds the lowest active pixel in a font based on a subset of its glyphs.
---@param font_data userdata The raw byte data of the font
---@param glyphs string[] The glyphs to check
---@return integer lowest @The lowest active pixel across each glyph checked
local function find_lowest(font_data, glyphs)
	local lowest_baseline = 0
	for _, glyph in ipairs(glyphs) do
		glyph_buffer:copy(font_data, true, ord(glyph) * 8, 0, 8)
		
		local baseline = 7
		while glyph_buffer[baseline] == 0 and baseline > 0 do
			baseline -= 1
		end
		if baseline == 7 then return 7 end
		
		lowest_baseline = max(baseline, lowest_baseline)
	end
	
	return lowest_baseline
end

---A cache of a font's data and metrics for use in text rendering widgets.
---@class CachedFont
local m_cached_font = {}
m_cached_font.__index = m_cached_font

---Applies the font as the primary or secondary. Not intended as public API.
---Use `FontCache:set_active` instead.
---@param secondary boolean If true: assigns the font data to address 0x5600. If false, assigns to address 0x4000
function m_cached_font:apply(secondary)
	self.data:poke(secondary and 0x5600 or 0x4000)
end

---Creates a new cached font from its data.
---@param data userdata
---@return CachedFont
local function new_cached_font(data)
	---@class CachedFont
	local cached_font = {
		data = data, ---The raw byte data of the font
		baseline_height = find_lowest(data, {'E', 'L'}) + 1, ---The estimated height of the font relative to its baseline.
		descender_height = find_lowest(data, {'q', 'p', 'y', '_', ',', 'g'}) + 1 ---The estimated height of the font including descenders.
	}
	
	return setmetatable(cached_font, m_cached_font)
end

---@class FontCache
local m_font_cache = {}
m_font_cache.__index = m_font_cache

---Adds a font to the cache under a name.
---@param name string The name of the font.
---@param font_data userdata The raw byte data of the font
function m_font_cache:add(name, font_data)
	self.fonts[name] = new_cached_font(font_data)
end

---Gets the active primary or secondary cached font.
---@param secondary boolean
---@return CachedFont
function m_font_cache:get_active(secondary)
	return self.fonts[secondary and self.active_secondary or self.active_primary]
end

---Sets the primary or secondary active font by name.
---@param secondary boolean
---@param font_name string The name of a font currently in the cache.
function m_font_cache:set_active(secondary, font_name)
	local key = secondary and "active_secondary" or "active_primary"
	
	if self[key] != font_name then
		self.fonts[font_name]:apply(secondary)
		self[key] = font_name
	end
end

---@return FontCache
local function new_font_cache()
	---@class FontCache
	local font_cache = {
		fonts = {}, ---@type table<string, CachedFont>
		active_primary = "lil",
		active_secondary = "p8"
	}
	
	setmetatable(font_cache, m_font_cache)
	
	font_cache:add("lil", fetch("/system/fonts/lil.font"))
	font_cache:add("lil_mono", fetch("/system/fonts/lil_mono.font"))
	font_cache:add("p8", fetch("/system/fonts/p8.font"))
	
	return setmetatable(font_cache, m_font_cache)
end

---A style sheet for use in text rendering.
---@class FontStyle
---@field col integer? Defaults to 7
---@field halign HorizontalAlignment? Defaults to left
---@field valign VerticalAlignment? Defaults to top
---@field primary_font string? Defaults to lil
---@field secondary_font string? Defaults to p8

---Sets unspecified fields in a style sheet to their defaults.
---@param style FontStyle
---@return FontStyle
local function default_style(style)
	return {
		col = style.col or 7,
		halign = style.halign or "left",
		valign = style.valign or "top",
		primary_font = style.primary_font or "lil",
		secondary_font = style.secondary_font or "p8",
	}
end

return {
	new_font_cache = new_font_cache,
	find_baseline = find_lowest,
	default_style = default_style,
}