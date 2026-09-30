-- Versioned configuration store with safe recovery and replace-on-commit writes.
local Config = {}
Config.__index = Config
local MAX_SETTINGS_BYTES = 131072

local defaults = {
    configVersion = 3,
    installMode = "CLEAN_INSTALL",
    upgradeFrom = "",
    firstBootComplete = false,
    computerLabel = "",
    theme = "black",
    accent = "cyan",
    wallpaperEnabled = true,
    wallpaperMode = "black",
    wallpaperPath = "",
    wallpaperBackground = "#080B12",
    wallpaperLastGood = "",
    wallpaperLastFailed = "",
    wallpaperError = "",
    showRichIcons = true,
    taskbarLabels = true,
    centerX = 470,
    centerZ = -33,
    dimension = "minecraft:overworld",
    grid = true,
    clockMode = "JST",
    snapEnabled = true,
    snapDistance = 10,
    clockInterval = 1,
    radarInterval = 0.5,
    serverInterval = 2,
    inventoryRefresh = 2,
    systemInterval = 1,
    performanceHistory = 60,
    resolution = 64,
    gpuName = "",
    keyboardName = "",
    detectorName = "",
    debugInputTrace = false,
    updateChannel = "stable",
    autoUpdateCheck = false,
    updateRepository = "https://github.com/kaede050492/hcc-os",
    computerId = "",
    logLimit = 400,
    networkRefresh = 3,
    resourceRefresh = 2,
    maxImageDownload = 4194304,
    imageCacheLimit = 4194304,
    imageCacheEnabled = true,
    imageDownloadConcurrency = 3,
    httpImageCacheLimit = 8388608,
    httpImageCacheEnabled = true,
    cursorIdle = 6,
    uiScale = 1,
    fpsMax = 60,
    fpsMin = 10,
    adaptiveFps = true
}

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function safeNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function exists(path)
    local ok, value = pcall(fs.exists, path)
    return ok and value == true
end

local function checkedExists(path)
    local ok, value = pcall(fs.exists, path)
    if not ok then return nil, tostring(value) end
    if type(value) ~= "boolean" then return nil, "filesystem existence check returned an invalid value" end
    return value == true
end

local function readRaw(path, limit)
    local found, existsError = checkedExists(path)
    if found == nil then return nil, existsError end
    if not found then return nil, "missing" end
    local dirOk, isDirectory = pcall(fs.isDir, path)
    if not dirOk then return nil, tostring(isDirectory) end
    if isDirectory then return nil, "not a settings file" end
    local sizeOk, size = pcall(fs.getSize, path)
    if not sizeOk or not safeNumber(size) or size < 0 then return nil, tostring(size) end
    if size > limit then return nil, "settings file exceeds 128 KiB" end
    local opened, file, openError = pcall(fs.open, path, "rb")
    if not opened then return nil, tostring(file) end
    if not file then return nil, tostring(openError or "could not open settings") end
    local readOk, contents = pcall(file.readAll)
    local closeOk, closeError = pcall(file.close)
    if not readOk then return nil, tostring(contents) end
    if not closeOk then return nil, tostring(closeError) end
    if type(contents) ~= "string" then return nil, "settings file did not return text" end
    if #contents > limit then return nil, "settings file exceeds 128 KiB" end
    return contents
end

local function readTable(path)
    local source, readError = readRaw(path, MAX_SETTINGS_BYTES)
    if not source then return nil, readError end
    local parseOk, value = pcall(textutils.unserialize, source)
    if not parseOk then return nil, value end
    if type(value) ~= "table" then return nil, "settings must contain a table" end
    return value
end

local function safeSuffix()
    local ok, epoch = pcall(function() return os.epoch("utc") end)
    if ok and type(epoch) == "number" then return tostring(math.floor(epoch)) end
    return tostring(math.floor(os.clock() * 1000))
end

local function quarantine(path)
    local found, existsError = checkedExists(path)
    if found == nil then return false, existsError end
    if not found then return true end
    local base = path .. ".corrupt." .. safeSuffix()
    local target
    for index = 0, 999 do
        target = index == 0 and base or (base .. "." .. tostring(index))
        local occupied, occupiedError = checkedExists(target)
        if occupied == nil then return false, occupiedError end
        if not occupied then break end
        target = nil
    end
    if not target then return false, "could not find a free settings recovery path" end
    local ok, err = pcall(fs.move, path, target)
    local targetExists, targetError = checkedExists(target)
    local sourceExists, sourceError = checkedExists(path)
    if not ok or targetExists ~= true or sourceExists ~= false then
        return false, tostring(err or targetError or sourceError or "could not preserve invalid settings")
    end
    return true
end

local function writeFile(path, contents)
    if type(contents) ~= "string" or #contents > MAX_SETTINGS_BYTES then
        return false, "settings exceed the 128 KiB save limit"
    end
    local opened, file, openError = pcall(fs.open, path, "wb")
    if not opened then return false, tostring(file) end
    if not file then return false, openError or "could not open temporary settings" end
    local writeOk, writeError = pcall(file.write, contents)
    local closeOk, closeError = pcall(file.close)
    if not writeOk then return false, writeError end
    if not closeOk then return false, closeError end
    local saved, verifyError = readRaw(path, MAX_SETTINGS_BYTES)
    if saved ~= contents then return false, verifyError or "temporary settings did not match the serialized data" end
    return true
end

local function deleteIfPresent(path)
    local found, existsError = checkedExists(path)
    if found == nil then return false, existsError end
    if not found then return true end
    local dirOk, isDirectory = pcall(fs.isDir, path)
    if not dirOk then return false, tostring(isDirectory) end
    if isDirectory then return false, "recovery path is a directory" end
    local ok, err = pcall(fs.delete, path)
    local remains, checkError = checkedExists(path)
    if not ok or remains ~= false then return false, tostring(err or checkError or "could not remove recovery file") end
    return true
end

local function computerId()
    if type(os.getComputerID) == "function" then
        local ok, value = pcall(os.getComputerID)
        if ok and value then return tostring(value) end
    end
    return "unknown"
end

local function mergeKnown(data, source, logger)
    for key, defaultValue in pairs(defaults) do
        local value = source[key]
        if value ~= nil and type(value) == type(defaultValue) then
            if type(defaultValue) ~= "number" or safeNumber(value) then
                data[key] = value
            elseif logger and type(logger.warn) == "function" then
                pcall(logger.warn, logger, "Ignored unsafe numeric setting: "..tostring(key))
            end
        end
    end
    -- Retain simple app-owned extensions without allowing unserializable values
    -- or arbitrarily large strings into the system configuration.
    for key, value in pairs(source) do
        if type(key) == "string" and defaults[key] == nil then
            local kind = type(value)
            if kind == "boolean" or (kind == "number" and safeNumber(value)) or
                (kind == "string" and #value <= 16384) then
                data[key] = value
            end
        end
    end
end

function Config.new(paths, logger)
    local self = setmetatable({}, Config)
    self.paths = paths
    self.logger = logger
    self.data = copy(defaults)
    self.data.computerId = computerId()
    self.migrated = false
    self.recovered = false
    self.warning = nil
    self.notice = nil
    self.primaryValid = false
    return self
end

function Config:load()
    self.data = copy(defaults)
    self.data.computerId = computerId()
    self.migrated, self.recovered, self.primaryValid, self.warning, self.notice = false, false, false, nil, nil

    local current, currentError = readTable(self.paths.settings)
    local source, sourcePath = current, current and self.paths.settings or nil
    if current then
        self.primaryValid = true
    else
        if currentError ~= "missing" then
            local moved, moveError = quarantine(self.paths.settings)
            if moved then
                self.warning = "Invalid settings were preserved for recovery"
                self.recovered = true
            else
                self.warning = "Settings are unreadable; recovery file could not be moved: " .. tostring(moveError)
            end
        end
        for _, candidate in ipairs({self.paths.settings .. ".prev", self.paths.settings .. ".bak"}) do
            local recovered, recoverError = readTable(candidate)
            if recovered then
                source, sourcePath = recovered, candidate
                self.recovered = true
                self.warning = "Settings were restored from a recovery copy"
                break
            elseif recoverError ~= "missing" and self.logger then
                if type(self.logger.warn) == "function" then
                    pcall(self.logger.warn, self.logger, "Unreadable settings recovery copy: " .. tostring(candidate))
                end
            end
        end
    end

    if not source then
        local legacy, legacyError = readTable(self.paths.legacySettings)
        if legacy then
            source, sourcePath = legacy, self.paths.legacySettings
            self.migrated, self.recovered = true, true
            self.data.firstBootComplete = true
            self.warning = "Legacy settings were migrated"
        elseif legacyError ~= "missing" then
            self.warning = self.warning or "Legacy settings could not be read; defaults were loaded"
        end
    end

    if source then mergeKnown(self.data, source, self.logger) end
    if not self.data.computerId or self.data.computerId == "" then self.data.computerId = computerId() end

    -- Keep the installed settings contract while normalising older data.
    self.data.configVersion = 3
    self.data.theme = self.data.theme == "midnight" and "midnight" or "black"
    self.data.wallpaperMode = ({black=true,solid=true,center=true,fit=true,fill=true,stretch=true,tile=true})[
        self.data.wallpaperMode] and self.data.wallpaperMode or "black"
    self.data.wallpaperBackground = tostring(self.data.wallpaperBackground or "#080B12")
    if not self.data.wallpaperBackground:match("^#%x%x%x%x%x%x$") then self.data.wallpaperBackground = "#080B12" end
    for _, key in ipairs({"wallpaperPath", "wallpaperLastGood", "wallpaperLastFailed"}) do
        if type(self.data[key]) ~= "string" or #self.data[key] > 256 then self.data[key] = "" end
    end
    if type(self.data.wallpaperError) ~= "string" or #self.data.wallpaperError > 256 then self.data.wallpaperError = "" end
    self.data.updateChannel = self.data.updateChannel == "beta" and "beta" or "stable"
    self.data.logLimit = math.max(50, math.min(1000, math.floor(tonumber(self.data.logLimit) or 400)))
    self.data.cursorIdle = math.max(1, math.min(30, tonumber(self.data.cursorIdle) or 6))
    self.data.uiScale = self.data.uiScale == 2 and 2 or 1
    local fpsSteps = {[10]=true,[15]=true,[20]=true,[30]=true,[45]=true,[60]=true}
    self.data.fpsMax = fpsSteps[self.data.fpsMax] and self.data.fpsMax or 60
    self.data.fpsMin = fpsSteps[self.data.fpsMin] and self.data.fpsMin or 10
    if self.data.fpsMin > self.data.fpsMax then self.data.fpsMin = self.data.fpsMax end
    self.data.adaptiveFps = self.data.adaptiveFps ~= false
    self.recoveredFrom = sourcePath
    if self.recovered then self.notice = self.warning or "Settings were recovered" end
    return self.data
end

function Config:save()
    local serializeOk, serialized = pcall(textutils.serialize, self.data)
    if not serializeOk or type(serialized) ~= "string" then
        self.warning = "Settings could not be serialized: " .. tostring(serialized)
        return false, self.warning
    end
    if #serialized > MAX_SETTINGS_BYTES then
        self.warning = "Settings exceed the 128 KiB save limit"
        return false, self.warning
    end

    local path = self.paths.settings
    local temporary = path .. ".tmp"
    local previous = path .. ".prev"
    local backup = path .. ".bak"
    local ok, err = writeFile(temporary, serialized)
    if not ok then
        deleteIfPresent(temporary)
        self.warning = tostring(err)
        return false, err
    end

    local pathExists, existsError = checkedExists(path)
    if pathExists == nil then
        deleteIfPresent(temporary)
        self.warning = tostring(existsError)
        return false, self.warning
    end
    local previousContents

    -- The active file stays untouched until the new data and recovery copy
    -- have both been written successfully.
    if self.primaryValid and pathExists then
        previousContents, err = readRaw(path, MAX_SETTINGS_BYTES)
        if not previousContents then
            deleteIfPresent(temporary)
            self.warning = "Current settings could not be verified: " .. tostring(err)
            return false, self.warning
        end
        local backupTemporary = backup .. ".tmp"
        local removed, removeError = deleteIfPresent(backupTemporary)
        if not removed then deleteIfPresent(temporary); self.warning = tostring(removeError); return false, self.warning end
        local copied, copyError = pcall(fs.copy, path, backupTemporary)
        local copiedContents, copiedReadError = readRaw(backupTemporary, MAX_SETTINGS_BYTES)
        if not copied or copiedContents ~= previousContents then
            deleteIfPresent(temporary)
            deleteIfPresent(backupTemporary)
            self.warning = tostring(copyError or copiedReadError or "settings recovery copy did not match")
            return false, self.warning
        end
        removed, removeError = deleteIfPresent(backup)
        if not removed then
            deleteIfPresent(temporary); deleteIfPresent(backupTemporary)
            self.warning = tostring(removeError)
            return false, self.warning
        end
        local moved, moveError = pcall(fs.move, backupTemporary, backup)
        local backupContents, backupReadError = readRaw(backup, MAX_SETTINGS_BYTES)
        if not moved or backupContents ~= previousContents then
            deleteIfPresent(temporary)
            deleteIfPresent(backupTemporary)
            self.warning = tostring(moveError or backupReadError or "settings recovery copy could not be verified")
            return false, self.warning
        end
    end

    if pathExists then
        local removed, removeError = deleteIfPresent(previous)
        if not removed then deleteIfPresent(temporary); self.warning = tostring(removeError); return false, self.warning end
        local moved, moveError = pcall(fs.move, path, previous)
        local sourceExists, sourceError = checkedExists(path)
        local previousExists, previousError = checkedExists(previous)
        if not moved or sourceExists ~= false or previousExists ~= true then
            if sourceExists == false and previousExists == true then pcall(fs.move, previous, path) end
            deleteIfPresent(temporary)
            self.warning = tostring(moveError or sourceError or previousError or "could not preserve current settings")
            return false, self.warning
        end
    end

    local committed, commitError = pcall(fs.move, temporary, path)
    local targetExists, targetError = checkedExists(path)
    if targetExists == nil then
        self.warning = "Save state is uncertain; recovery files were preserved: " .. tostring(targetError)
        return false, self.warning
    end
    local savedContents, savedReadError
    if targetExists then savedContents, savedReadError = readRaw(path, MAX_SETTINGS_BYTES) end
    if not targetExists or savedContents ~= serialized then
        if targetExists then
            local removed, removeError = deleteIfPresent(path)
            if not removed then
                self.warning = "Settings could not be verified; recovery files were preserved: " .. tostring(removeError)
                return false, self.warning
            end
        end
        if pathExists then
            local priorExists, priorError = checkedExists(previous)
            if priorExists == nil then
                self.warning = "Settings could not be verified and the previous file is inaccessible: " .. tostring(priorError)
                return false, self.warning
            end
            if priorExists then
                local restored, restoreError = pcall(fs.move, previous, path)
                local restoredExists, restoredError = checkedExists(path)
                if not restored or restoredExists ~= true then
                    self.warning = "Save failed; the previous settings remain at " .. previous .. ": " ..
                        tostring(restoreError or restoredError or commitError or savedReadError or "restore failed")
                    return false, self.warning
                end
            end
        end
        deleteIfPresent(temporary)
        self.warning = tostring(commitError or savedReadError or "saved settings did not match the serialized data")
        return false, self.warning
    end

    local removed, removeError = deleteIfPresent(previous)
    if not removed and self.logger then
        pcall(self.logger.warn, self.logger, "Settings saved; previous copy could not be removed: " .. tostring(removeError))
    end
    deleteIfPresent(temporary)
    self.primaryValid = true
    self.recovered = false
    self.warning = nil
    return true
end

function Config:ensureDirectories()
    local directories = {
        self.paths.config, self.paths.images, self.paths.cache, self.paths.downloads,
        self.paths.logs, self.paths.backups, self.paths.temp, self.paths.updateTemp
    }
    for _, path in ipairs(self.paths.backupRoots or {}) do directories[#directories+1] = path end
    for _, path in ipairs(self.paths.updateTemps or {}) do directories[#directories+1] = path end
    for _, path in ipairs(directories) do
        local ok, err = pcall(function()
            if not fs.exists(path) then fs.makeDir(path) end
            if not fs.isDir(path) then error("path exists but is not a directory") end
        end)
        if not ok and self.logger then self.logger:warn("Storage path unavailable: " .. tostring(path) .. " (" .. tostring(err) .. ")") end
    end
end

function Config:backupLegacyStartup()
    local backup = self.paths.backups .. "/migration-1.3.3"
    if exists(self.paths.startup) and not exists(backup .. "/startup.lua") then
        local ok, err = pcall(function()
            if not exists(backup) then fs.makeDir(backup) end
            fs.copy(self.paths.startup, backup .. "/startup.lua")
        end)
        if ok then self.logger:info("Backed up existing startup.lua before migration")
        else self.logger:warn("Could not back up existing startup.lua: " .. tostring(err)) end
    end
end

function Config:isFirstBoot()
    return not self.data.firstBootComplete
end

function Config:completeFirstBoot()
    local previous = self.data.firstBootComplete
    self.data.firstBootComplete = true
    local ok, err = self:save()
    if not ok then self.data.firstBootComplete = previous end
    return ok, err
end

function Config:reset()
    local old = self.data
    local id = old.computerId
    self.data = copy(defaults)
    self.data.computerId = id ~= "" and id or computerId()
    self.data.firstBootComplete = true
    local ok, err = self:save()
    if not ok then self.data = old end
    return ok, err
end

return {new = function(paths, logger) return Config.new(paths, logger) end, defaults = defaults}
