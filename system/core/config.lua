local Config = {}
Config.__index = Config

local defaults = {
    configVersion = 2,
    installMode = "CLEAN_INSTALL",
    upgradeFrom = "",
    firstBootComplete = false,
    computerLabel = "",
    theme = "black",
    accent = "cyan",
    wallpaperMode = "black",
    wallpaperPath = "",
    wallpaperCache = true,
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
    updateChannel = "stable",
    autoUpdateCheck = false,
    updateRepository = "https://github.com/kaede050492/hcc-os",
    computerId = "",
    logLimit = 400,
    networkRefresh = 3,
    resourceRefresh = 2,
    maxImageDownload = 4194304,
    imageCacheLimit = 4194304,
    imageCacheEnabled = true
}

local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function readTable(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local source = f.readAll() or ""
    f.close()
    local ok, value = pcall(textutils.unserialize, source)
    return ok and type(value) == "table" and value or nil
end

local function writeTable(path, value)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
    local f, err = fs.open(path, "w")
    if not f then return false, err end
    local ok, writeError = pcall(f.write, textutils.serialize(value))
    f.close()
    return ok, writeError
end

local function computerId()
    if type(os.getComputerID) == "function" then
        local ok, value = pcall(os.getComputerID)
        if ok and value then return tostring(value) end
    end
    return "unknown"
end

function Config.new(paths, logger)
    local self = setmetatable({}, Config)
    self.paths = paths
    self.logger = logger
    self.data = copy(defaults)
    self.data.computerId = computerId()
    self.migrated = false
    self.warning = nil
    return self
end

function Config:load()
    local current = readTable(self.paths.settings)
    local legacy = readTable(self.paths.legacySettings)
    local source = current or legacy
    if source then
        for key, defaultValue in pairs(defaults) do
            if source[key] ~= nil and type(source[key]) == type(defaultValue) then
                self.data[key] = source[key]
            end
        end
        if not current and legacy then
            self.migrated = true
            -- An existing v1.3.3 installation has already completed first boot.
            -- Only the new configuration container is migrated.
            self.data.firstBootComplete = true
            self.logger:info("Migrated v1.3.3 settings to config/settings")
        end
    end
    if not self.data.computerId or self.data.computerId == "" then self.data.computerId = computerId() end
    self.data.configVersion = 2
    self.data.theme = self.data.theme == "midnight" and "midnight" or "black"
    self.data.wallpaperMode = ({black=true,center=true,fit=true,fill=true,stretch=true,tile=true})[self.data.wallpaperMode] and self.data.wallpaperMode or "black"
    self.data.updateChannel = self.data.updateChannel == "beta" and "beta" or "stable"
    self.data.logLimit = math.max(50, math.min(1000, math.floor(tonumber(self.data.logLimit) or 400)))
    return self.data
end

function Config:save()
    local ok, err = writeTable(self.paths.settings, self.data)
    if not ok then self.warning = tostring(err) end
    return ok, err
end

function Config:ensureDirectories()
    local directories = {
        self.paths.config, self.paths.images, self.paths.cache, self.paths.downloads,
        self.paths.logs, self.paths.backups, self.paths.temp, self.paths.updateTemp
    }
    for _, path in ipairs(directories) do
        if not fs.exists(path) then fs.makeDir(path) end
    end
end

function Config:backupLegacyStartup()
    local backup = self.paths.backups.."/migration-1.3.3"
    if fs.exists(self.paths.startup) and not fs.exists(backup.."/startup.lua") then
        if not fs.exists(backup) then fs.makeDir(backup) end
        fs.copy(self.paths.startup, backup.."/startup.lua")
        self.logger:info("Backed up existing startup.lua before migration")
    end
end

function Config:isFirstBoot()
    return not self.data.firstBootComplete
end

function Config:completeFirstBoot()
    self.data.firstBootComplete = true
    return self:save()
end

function Config:reset()
    local id = self.data.computerId
    self.data = copy(defaults)
    self.data.computerId = id ~= "" and id or computerId()
    self.data.firstBootComplete = true
    return self:save()
end

return {new = function(paths, logger) return Config.new(paths, logger) end, defaults = defaults}
