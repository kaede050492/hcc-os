local Updater = {}
Updater.__index = Updater

local function safeRelative(path)
    if type(path) ~= "string" or path == "" or #path > 160 then return false end
    if path:find("[%z\\]") or path:sub(1, 1) == "/" or path:match("^[A-Za-z]:") then return false end
    for part in path:gmatch("[^/]+") do
        if part == ".." or part == "." or part == "" then return false end
    end
    return true
end

local function safeVersion(value)
    value = tostring(value or "unknown")
    return value:gsub("[^%w%._%-]", "_"):sub(1, 48)
end

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
end

local function readLocalManifest(path)
    if not fs.exists(path) then return nil, "local manifest is missing" end
    local f = fs.open(path, "r")
    if not f then return nil, "local manifest cannot be opened" end
    local source = f.readAll() or ""
    f.close()
    local chunk, err = load(source, "@"..path, "t", {})
    if not chunk then return nil, err end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, "local manifest is invalid" end
    return value
end

local function manifestFiles(manifest)
    local result = {}
    if type(manifest) ~= "table" or type(manifest.files) ~= "table" then return nil, "manifest file list is missing" end
    for _, entry in ipairs(manifest.files) do
        local path = type(entry) == "string" and entry or entry and entry.path
        if not safeRelative(path) then return nil, "manifest contains an unsafe path" end
        result[#result+1] = {path=path, size=type(entry) == "table" and tonumber(entry.size) or nil}
    end
    return result
end

function Updater.new(paths, config, logger, remote)
    local self = setmetatable({}, Updater)
    self.paths, self.config, self.logger, self.remote = paths, config, logger, remote
    self.localManifest = readLocalManifest(paths.manifest)
    self.state = {phase="idle", current="", completed=0, total=0, message="Ready"}
    self.cancelled = false
    self.checkJob = nil
    self.downloadJob = nil
    return self
end

function Updater:status()
    local copy = {}
    for key, value in pairs(self.state) do copy[key] = value end
    return copy
end

function Updater:cleanup()
    self.cancelled = true
    -- An HTTP check cannot be forcibly aborted in CraftOS, but clearing the
    -- job makes its eventual response harmless instead of reviving cancelled
    -- update state after the user has moved on.
    self.checkJob = nil
    self.downloadJob = nil
    if fs.exists(self.paths.updateTemp) then pcall(fs.delete, self.paths.updateTemp) end
    self.state = {phase="idle", current="", completed=0, total=0, message="Cancelled"}
end

function Updater:check()
    self.state = {phase="checking", current="", completed=0, total=0, message="Checking manifest..."}
    local result, err = self.remote.check(self.config.data, self.localManifest)
    if not result then
        self.state.phase, self.state.message = "offline", tostring(err)
        self.logger:warn("Update check failed: "..tostring(err))
        return nil, err
    end
    self.lastCheck = result
    if result.available then
        self.state.phase, self.state.message = "available", "Update available"
    elseif result.refreshAvailable then
        self.state.phase, self.state.message = "refresh_available", "Same version - refresh available"
    elseif result.downgradeBlocked then
        self.state.phase, self.state.message = "current", "Remote revision is older; downgrade blocked"
    else
        self.state.phase, self.state.message = "current", "HCC OS is up to date"
    end
    self.logger:info("Update check: "..self.state.message)
    return result
end

function Updater:beginAsyncCheck()
    if self.checkJob then return false, "Update check already in progress" end
    if self.downloadJob then return false, "Download already in progress" end
    if self.state.phase == "downloading" or self.state.phase == "ready" then
        return false, "Finish or cancel the current update first"
    end
    if type(http) ~= "table" or type(http.request) ~= "function" then
        return false, "HTTP request API unavailable"
    end
    local url = self.remote.manifestUrl(self.config.data)
    local ok, accepted = pcall(http.request, url)
    if not ok or accepted == false or accepted == nil then return false, "HTTP request failed or denied" end
    self.checkJob = {url=url}
    self.state = {phase="check_wait", current="manifest.lua", completed=0, total=0, message="Checking manifest in background..."}
    return true
end

function Updater:handleHttpSuccess(url, handle)
    if self.downloadJob and self.downloadJob.url == url then
        local job = self.downloadJob
        local ok, body = false, "Invalid HTTP response handle"
        if type(handle) == "table" and type(handle.readAll) == "function" then ok, body = pcall(handle.readAll) end
        if type(handle) == "table" and type(handle.close) == "function" then pcall(handle.close) end
        self.downloadJob = nil
        if not ok then
            self:cleanup()
            self.state.phase, self.state.message = "failed", "Download response could not be read"
            self.logger:error(self.state.message.." ("..job.file.path..")")
            return true
        end
        local staged, stageError = self:stageDownloadedFile(job.file, body)
        if not staged then
            self:cleanup()
            self.state.phase, self.state.message = "failed", "Download failed: "..tostring(stageError)
            self.logger:error(self.state.message.." ("..job.file.path..")")
            return true
        end
        self.state.completed = self.fileIndex
        self.state.current = ""
        self.state.message = string.format("Downloaded %d/%d", self.state.completed, self.state.total)
        return true
    end
    if not self.checkJob or self.checkJob.url ~= url then
        -- Leave unrelated HCC Web handles untouched; the desktop dispatcher
        -- forwards this event to the Web app when it is not ours.
        return false
    end
    local ok, body = false, "Invalid HTTP response handle"
    if type(handle) == "table" and type(handle.readAll) == "function" then ok, body = pcall(handle.readAll) end
    if type(handle) == "table" and type(handle.close) == "function" then pcall(handle.close) end
    self.checkJob = nil
    if not ok then self.state.phase, self.state.message = "offline", "Manifest read failed"; return true end
    local manifest, err = self.remote.parseManifest(body or "")
    if not manifest then self.state.phase, self.state.message = "offline", tostring(err); return true end
    local result = self.remote.compareManifests(self.localManifest, manifest)
    if not result then self.state.phase, self.state.message = "offline", "Manifest comparison failed"; return true end
    -- The manifest was already retrieved asynchronously. Compare it without a
    -- second HTTP request so a same-version refresh remains non-blocking.
    self.lastCheck=result
    if self.lastCheck.available then self.state.phase,self.state.message="available","Update available"
    elseif self.lastCheck.refreshAvailable then self.state.phase,self.state.message="refresh_available","Same version - refresh available"
    elseif self.lastCheck.downgradeBlocked then self.state.phase,self.state.message="current","Remote revision is older; downgrade blocked"
    else self.state.phase,self.state.message="current","HCC OS is up to date" end
    self.logger:info("Background update check: "..self.state.message)
    return true
end

function Updater:handleHttpFailure(url, reason)
    if self.downloadJob and self.downloadJob.url == url then
        local file = self.downloadJob.file
        self.downloadJob = nil
        self:cleanup()
        self.state.phase = "failed"
        self.state.message = "Download failed: "..tostring(reason or "HTTP request failed")
        self.logger:error(self.state.message.." ("..file.path..")")
        return true
    end
    if not self.checkJob or self.checkJob.url ~= url then return false end
    self.checkJob = nil
    self.state.phase, self.state.message = "offline", tostring(reason or "HTTP request failed")
    self.logger:warn("Background update check failed: "..self.state.message)
    return true
end

function Updater:storageBudget(manifest, files)
    local declared = math.max(1, tonumber(manifest and manifest.installedSize) or 0)
    local listed = 0
    for _, file in ipairs(files or {}) do listed = listed + math.max(0, tonumber(file.size) or 0) end
    local baseline = math.max(declared, listed)
    -- Keep a bounded staging margin for manifests whose installedSize was
    -- generated before the latest source files were added. This prevents a
    -- valid update from stopping near the end while still preserving a hard
    -- upper bound for the temporary download tree.
    return baseline + math.max(32768, math.floor(baseline*0.1))
end

function Updater:spaceAvailable(files, manifest, repairOnly)
    if type(fs.getFreeSpace) ~= "function" then return true end
    local ok, free = pcall(fs.getFreeSpace, "/")
    if not ok or type(free) ~= "number" then return true end
    local installed = self:storageBudget(manifest, files)
    local required
    if repairOnly then
        local maximum = math.max(1, tonumber(manifest and manifest.maxFileSize) or 40000)
        required = math.min(installed, #files * maximum)
    else
        required = installed
    end
    if required <= 0 then
        for _, file in ipairs(files) do required = required + math.max(0, tonumber(file.size) or 0) end
    end
    return free >= required + 16384
end

function Updater:begin(manifest, repairOnly)
    if self.checkJob then return false, "Update check still in progress" end
    if self.downloadJob then return false, "Download already in progress" end
    local files, err = manifestFiles(manifest)
    if not files then return false, err end
    if repairOnly then
        local selected = {}
        for _, file in ipairs(files) do
            local target = fs.combine(self.paths.system, file.path)
            if not fs.exists(target) or fs.isDir(target) or fs.getSize(target) == 0 then selected[#selected+1] = file end
        end
        files = selected
    end
    if not self:spaceAvailable(files, manifest, repairOnly) then
        self.state = {phase="blocked", current="", completed=0, total=#files, message="Not enough free space"}
        return false, self.state.message
    end
    if fs.exists(self.paths.updateTemp) then pcall(fs.delete, self.paths.updateTemp) end
    fs.makeDir(self.paths.updateTemp)
    self.manifest = manifest
    self.files = files
    self.repairOnly = repairOnly == true
    self.fileIndex = 0
    self.downloadedBytes = 0
    self.cancelled = false
    self.state = {phase="downloading", current="", completed=0, total=#files, message=#files == 0 and "Nothing to repair" or "Downloading update"}
    return true
end

function Updater:stageDownloadedFile(file, body)
    if type(body) ~= "string" then return false, "Downloaded response is not text data" end
    if file.size and #body ~= file.size then return false, "Downloaded size mismatch: "..file.path end
    local maximum = math.max(1, tonumber(self.manifest and self.manifest.maxFileSize) or 40000)
    local installed = self:storageBudget(self.manifest, self.files)
    if #body > maximum or self.downloadedBytes + #body > installed then
        return false, "Downloaded data exceeds manifest storage limits"
    end
    local target = fs.combine(self.paths.updateTemp, file.path)
    ensureParent(target)
    local f, openError = fs.open(target, "w")
    if not f then return false, openError end
    local ok, writeError = pcall(f.write, body)
    f.close()
    if not ok then return false, writeError end
    self.downloadedBytes = self.downloadedBytes + #body
    return true
end

function Updater:step()
    if self.state.phase ~= "downloading" then return self.state.phase == "ready" end
    if self.cancelled then self:cleanup(); return false end
    if self.downloadJob then return true end
    self.fileIndex = self.fileIndex + 1
    local file = self.files[self.fileIndex]
    if not file then
        self.state.phase = "ready"
        self.state.current = ""
        self.state.message = "All files downloaded; ready to apply"
        return true
    end
    self.state.current = file.path
    if type(http) ~= "table" or type(http.request) ~= "function" then
        self:cleanup(); self.state.phase, self.state.message = "failed", "HTTP request API unavailable"
        return false, self.state.message
    end
    local url = self.remote.fileUrl(file.path, self.config.data)
    local requested, accepted = pcall(http.request, url)
    if not requested or accepted == false or accepted == nil then
        self:cleanup(); self.state.phase, self.state.message = "failed", "Download request was denied"
        return false, self.state.message
    end
    self.downloadJob = {url=url, file=file}
    self.state.message = "Waiting for "..file.path
    return true
end

function Updater:backupCurrent(version)
    local name = safeVersion(version)
    local destination = self.paths.backups.."/"..name
    if fs.exists(destination) then destination = destination.."-"..tostring(os.epoch("utc")) end
    fs.makeDir(destination)
    local info = fs.open(destination.."/version", "w")
    if info then info.write(tostring(version or "unknown")); info.close() end
    if fs.exists(self.paths.system) then fs.move(self.paths.system, destination.."/system") end
    return destination
end

function Updater:moveTree(source, destination, skip)
    if not fs.isDir(source) then ensureParent(destination); fs.move(source, destination); return end
    if not fs.exists(destination) then fs.makeDir(destination) end
    for _, name in ipairs(fs.list(source)) do
        if not (skip and skip[name]) then self:moveTree(fs.combine(source, name), fs.combine(destination, name), nil) end
    end
    if fs.exists(source) and #fs.list(source) == 0 then fs.delete(source) end
end

function Updater:apply()
    if self.state.phase ~= "ready" then return false, "update is not ready" end
    if self.repairOnly then
        local placed = {}
        local rollbackRoot = self.paths.temp.."/repair-rollback"
        if fs.exists(rollbackRoot) then return false, "Previous repair backup requires recovery: "..rollbackRoot end
        local ok, err = pcall(function()
            for _, file in ipairs(self.files or {}) do
                local source = fs.combine(self.paths.updateTemp, file.path)
                local target = fs.combine(self.paths.system, file.path)
                if not fs.exists(source) or fs.isDir(source) then error("Staged repair file is missing: "..file.path) end
                local backup = fs.combine(rollbackRoot, file.path)
                local hadOriginal = fs.exists(target)
                local item={path=target, backup=backup, moved=false, installed=false}
                placed[#placed+1] = item
                if hadOriginal then ensureParent(backup); fs.move(target,backup); item.moved=true end
                ensureParent(target); fs.move(source, target); item.installed=true
            end
            if fs.exists(self.paths.updateTemp) then fs.delete(self.paths.updateTemp) end
        end)
        if not ok then
            local restored=true
            for index=#placed,1,-1 do
                local item=placed[index]
                local recovered=pcall(function()
                    if item.installed and fs.exists(item.path) then fs.delete(item.path) end
                    if item.moved then ensureParent(item.path); fs.move(item.backup,item.path) end
                end)
                restored=restored and recovered
            end
            if restored and fs.exists(rollbackRoot) then pcall(fs.delete,rollbackRoot) end
            if fs.exists(self.paths.updateTemp) then pcall(fs.delete,self.paths.updateTemp) end
            self.state.phase, self.state.message = "failed", (restored and "Repair rolled back: " or "Repair recovery required; backup kept at "..rollbackRoot..": ")..tostring(err)
            self.logger:error(self.state.message)
            return false, err
        end
        if fs.exists(rollbackRoot) then pcall(fs.delete,rollbackRoot) end
        self.state.phase, self.state.message = "applied", "Repair applied; restart HCC OS"
        self.logger:info("Repaired "..tostring(#(self.files or {})).." system files")
        return true
    end
    local oldVersion = self.localManifest and self.localManifest.version or "previous"
    local backupOk, backup, backupError = pcall(self.backupCurrent, self, oldVersion)
    if not backupOk or not backup then return false, backupError or backup end
    local ok, err = pcall(function()
        local versionPath = fs.combine(self.paths.updateTemp, "version.lua")
        if not fs.exists(versionPath) then error("Downloaded version information is missing") end
        fs.makeDir(self.paths.system)
        self:moveTree(self.paths.updateTemp, self.paths.system, { ["version.lua"] = true })
        fs.move(versionPath, self.paths.versionFile)
        if fs.exists(self.paths.updateTemp) then fs.delete(self.paths.updateTemp) end
    end)
    if not ok then
        local restored=pcall(function()
            if fs.exists(self.paths.system) then fs.delete(self.paths.system) end
            fs.move(backup.."/system", self.paths.system)
        end)
        if restored and fs.exists(backup) then pcall(fs.delete,backup) end
        if fs.exists(self.paths.updateTemp) then pcall(fs.delete,self.paths.updateTemp) end
        self.state.phase, self.state.message = "failed", (restored and "Update rolled back: " or "Update recovery required; backup kept at "..backup..": ")..tostring(err)
        self.logger:error(self.state.message)
        return false, err
    end
    self.localManifest = self.manifest
    self.state.phase, self.state.message = "applied", "Update applied; restart HCC OS"
    self.logger:info("Updated to "..tostring(self.manifest.version).." build "..tostring(self.manifest.build))
    return true
end

function Updater:rollback(version)
    local name = version and safeVersion(version) or nil
    local candidates = {}
    if name then candidates[#candidates+1] = self.paths.backups.."/"..name end
    if fs.exists(self.paths.backups) then
        for _, entry in ipairs(fs.list(self.paths.backups)) do
            local path = self.paths.backups.."/"..entry
            if fs.isDir(path) and fs.exists(path.."/system") then candidates[#candidates+1] = path end
        end
    end
    local selected = candidates[1]
    if not name then
        table.sort(candidates, function(a, b) return a > b end)
        selected = candidates[1]
    end
    if not selected or not fs.exists(selected.."/system") then return false, "No rollback backup is available" end
    local temporary = self.paths.temp.."/rollback-current"
    if fs.exists(temporary) then fs.delete(temporary) end
    local movedCurrent, movedBackup = false, false
    local ok, err = pcall(function()
        if fs.exists(self.paths.system) then fs.move(self.paths.system, temporary); movedCurrent=true end
        fs.move(selected.."/system", self.paths.system); movedBackup=true
        if movedCurrent then fs.move(temporary, selected.."/system"); movedCurrent=false end
    end)
    if not ok then
        if movedBackup and fs.exists(self.paths.system) then pcall(fs.move,self.paths.system,selected.."/system") end
        if fs.exists(temporary) then fs.move(temporary, self.paths.system) end
        return false, err
    end
    self.logger:warn("Rolled back HCC OS using "..selected)
    self.state.phase, self.state.message = "rolledback", "Rollback complete; restart HCC OS"
    return true
end

function Updater:repair(manifest)
    local ok, err = self:begin(manifest, true)
    if not ok then return false, err end
    if self.state.total == 0 then self.state.phase="ready"; return true end
    return true
end

return Updater
