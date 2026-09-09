local _modules = {}

function require(name)
	if _modules[name] == nil then
		local path = name:gsub('%.', '/') .. '.lua'
		local module = fetch(path)
		if not module then error("Failed to load module at " .. path) end
		_modules[name] = include(path)
	end
	return _modules[name]
end