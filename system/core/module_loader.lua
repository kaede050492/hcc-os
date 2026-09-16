-- HCC OS v1.5 module loader.
-- Supports bundled modules and user-provided external Lua modules without
-- replacing CraftOS's global require function.

local Loader = {}
Loader.__index = Loader

local function normaliseName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("%z") or name:find("\\", 1, true) or name:find("..", 1, true) then return nil end
    name = name:gsub("^/+", ""):gsub("%.lua$", "")
    return name:gsub("%.", "/")
end

local function read(path)
    local file, err = fs.open(path, "r")
    if not file then return nil, err end
    local ok, source = pcall(file.readAll)
    pcall(file.close)
    if not ok then return nil, source end
    return source or ""
end

function Loader.new(options)
    options = options or {}
    return setmetatable({
        roots = options.roots or {}, cache = {}, loading = {}, paths = {}
    }, Loader)
end

function Loader:resolve(name)
    local relative = normaliseName(name)
    if not relative then return nil, "unsafe module name: "..tostring(name) end
    for _, root in ipairs(self.roots) do
        local candidate = fs.combine(root, relative..".lua")
        if fs.exists(candidate) and not fs.isDir(candidate) then return candidate end
    end
    return nil, "module not found: "..tostring(name)
end

function Loader:loadPath(path, environment, cacheKey)
    cacheKey = cacheKey or path
    if self.cache[cacheKey] ~= nil then return self.cache[cacheKey] end
    if self.loading[cacheKey] then error("circular module dependency: "..tostring(cacheKey), 0) end
    local source, err = read(path)
    if not source then error(err or ("missing module: "..path), 0) end
    self.loading[cacheKey] = true
    local moduleEnvironment = setmetatable({
        require = function(first, second) return self:load(second or first) end
    }, {__index = environment or _ENV})
    local chunk, loadError = load(source, "@"..path, "t", moduleEnvironment)
    if not chunk then
        self.loading[cacheKey] = nil
        error(loadError or ("could not load module: "..path), 0)
    end
    local ok, value = xpcall(chunk, function(reason)
        return debug and debug.traceback and debug.traceback(tostring(reason), 2) or tostring(reason)
    end)
    self.loading[cacheKey] = nil
    if not ok then error(value, 0) end
    self.cache[cacheKey], self.paths[cacheKey] = value, path
    return value
end

function Loader:load(name)
    local path, err = self:resolve(name)
    if not path then error(err, 0) end
    return self:loadPath(path, _ENV, name)
end

function Loader:clear(name)
    if name then self.cache[name] = nil; self.paths[name] = nil
    else self.cache = {}; self.paths = {} end
end

return {new = function(options) return Loader.new(options) end}
