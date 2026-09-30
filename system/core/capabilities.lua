-- Peripheral capability discovery. Device-specific code consumes descriptors,
-- not guessed peripheral names or unverified method calls.
local Registry = {}
Registry.__index = Registry

local GPU_METHODS = {
    "getSize", "refreshSize", "setSize", "filledRectangle", "line",
    "drawText", "getTextLength", "sync", "fill"
}
local MODEM_METHODS = { "open", "close", "isOpen", "transmit" }
local DETECTOR_METHODS = {
    "getPlayer", "getPlayerPos", "getOnlinePlayers", "getPlayersInRange"
}

local function normalise(value)
    local result = tostring(value or ""):lower():gsub("[^%w]", "")
    return result
end

local function addMethods(target, methods)
    if type(methods) ~= "table" then return end
    for _, name in ipairs(methods) do
        if type(name) == "string" then target[name] = true end
    end
end

local function hasAll(set, names)
    for _, name in ipairs(names) do
        if not set[name] then return false end
    end
    return true
end

local function protectedLog(logger, level, message)
    if logger and type(logger[level]) == "function" then
        pcall(logger[level], logger, message)
    end
end

function Registry.new(options)
    options = options or {}
    return setmetatable({
        api = options.api or peripheral,
        logger = options.logger,
        items = {},
        errors = {},
        generation = 0
    }, Registry)
end

function Registry:scan()
    self.items, self.errors = {}, {}
    local api = self.api
    if type(api) ~= "table" or type(api.getNames) ~= "function" then
        self.error = "Peripheral API unavailable"
        return self.items, self.error
    end

    local namesOk, names = pcall(api.getNames)
    if not namesOk or type(names) ~= "table" then
        self.error = "Peripheral enumeration failed: " .. tostring(names)
        protectedLog(self.logger, "warn", self.error)
        return self.items, self.error
    end
    self.error = nil
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)

    for _, rawName in ipairs(names) do
        local name = tostring(rawName or "")
        if name ~= "" then
            local item = { name=name, types={}, methods={}, capabilities={}, handle=nil }
            if type(api.getType) == "function" then
                local returned = { pcall(api.getType, name) }
                if returned[1] then
                    for index = 2, #returned do
                        if type(returned[index]) == "string" then item.types[#item.types + 1] = returned[index] end
                    end
                else
                    self.errors[#self.errors + 1] = name .. ": getType failed: " .. tostring(returned[2])
                end
            end

            if type(api.getMethods) == "function" then
                local ok, methods = pcall(api.getMethods, name)
                if ok then addMethods(item.methods, methods)
                else self.errors[#self.errors + 1] = name .. ": getMethods failed: " .. tostring(methods) end
            end

            if type(api.wrap) == "function" then
                local ok, handle = pcall(api.wrap, name)
                if ok and type(handle) == "table" then item.handle = handle
                elseif not ok then self.errors[#self.errors + 1] = name .. ": wrap failed: " .. tostring(handle) end
            end

            local caps = item.capabilities
            caps.tom_gpu = hasAll(item.methods, GPU_METHODS)
            caps.tom_keyboard = item.methods.setFireNativeEvents == true
            caps.inventory = item.methods.list == true and item.methods.size == true
            caps.modem = hasAll(item.methods, MODEM_METHODS)
            caps.player_detector = false
            for _, kind in ipairs(item.types) do
                if normalise(kind) == "playerdetector" then caps.player_detector = true end
            end
            caps.detector_methods = {}
            for _, method in ipairs(DETECTOR_METHODS) do
                if item.methods[method] then caps.detector_methods[method] = true end
            end
            caps.player_detector = caps.player_detector or next(caps.detector_methods) ~= nil
            local hasPlayerList = caps.detector_methods.getOnlinePlayers == true or
                caps.detector_methods.getPlayersInRange == true
            local hasPlayerPosition = caps.detector_methods.getPlayerPos == true or
                caps.detector_methods.getPlayer == true
            caps.player_radar = caps.player_detector and hasPlayerList and hasPlayerPosition

            self.items[#self.items + 1] = item
        end
    end

    self.generation = self.generation + 1
    for _, message in ipairs(self.errors) do protectedLog(self.logger, "warn", "Capability scan: " .. message) end
    return self.items
end

function Registry:get(name)
    for _, item in ipairs(self.items) do
        if item.name == name then return item end
    end
end

function Registry:find(capability, preferredName)
    if preferredName and preferredName ~= "" then
        local preferred = self:get(preferredName)
        if preferred and preferred.capabilities[capability] then return preferred end
    end
    for _, item in ipairs(self.items) do
        if item.capabilities[capability] then return item end
    end
end

function Registry:snapshot()
    local result = {}
    for _, item in ipairs(self.items) do
        local types = {}
        for index, kind in ipairs(item.types) do types[index] = kind end
        local capabilities = {}
        for name, available in pairs(item.capabilities) do
            if name ~= "detector_methods" then capabilities[name] = available end
        end
        result[#result + 1] = { name=item.name, types=types, capabilities=capabilities }
    end
    return result
end

return { new = function(options) return Registry.new(options) end }
