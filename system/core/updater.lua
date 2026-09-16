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

local function driveOf(path)
    local ok,value=pcall(fs.getDrive,path)
    return ok and value or nil
end

local function transfer(source,destination)
    ensureParent(destination)
    local sourceDrive=driveOf(source)
    local destinationDrive=driveOf(fs.getDir(destination)=="" and "/" or fs.getDir(destination))
    if sourceDrive and sourceDrive==destinationDrive then
        fs.move(source,destination)
        return
    end
    -- CC:T mounts disk and computer storage separately.  Move cannot be
    -- assumed to work across mounts, so copy first and remove only after the
    -- destination has been written successfully.
    fs.copy(source,destination)
    if fs.exists(source) then fs.delete(source) end
end

local function treeSize(path)
    if not fs.exists(path) then return 0 end
    if not fs.isDir(path) then return math.max(0,tonumber(fs.getSize(path)) or 0) end
    local total=0
    for _,name in ipairs(fs.list(path)) do total=total+treeSize(fs.combine(path,name)) end
    return total
end

local function freeSpace(path)
    local ok,value=pcall(fs.getFreeSpace,path)
    return ok and value or nil
end

local function writeBytes(path,body)
    ensureParent(path)
    local f,e=fs.open(path,"wb")
    if not f then return false,e or "file is not writable" end
    local ok,reason=pcall(f.write,body)
    local closed,closeError=pcall(f.close)
    if not ok then return false,tostring(reason) end
    if not closed then return false,tostring(closeError) end
    return true
end

local function updateRoots(paths)
    local roots=paths and paths.updateTemps
    if type(roots)=="table" and #roots>0 then return roots end
    return {paths and paths.updateTemp or "/.hccos/temp/update"}
end

local function backupRoots(paths)
    local roots=paths and paths.backupRoots
    if type(roots)=="table" and #roots>0 then return roots end
    return {paths and paths.backups or "/.hccos/backups"}
end

local function backupSearchRoots(paths)
    local roots={}
    local seen={}
    local function add(path)
        if type(path)=="string" and path~="" and not seen[path] then
            seen[path]=true; roots[#roots+1]=path
        end
    end
    for _,root in ipairs(backupRoots(paths)) do add(root) end
    -- Keep rollback backups made before multi-disk storage was enabled.
    add("/.hccos/backups")
    return roots
end

local function backupName(path)
    return tostring(path):match("([^/]+)$") or tostring(path)
end

local function collectFiles(root,current,relative,result)
    for _,name in ipairs(fs.list(current)) do
        local child=fs.combine(current,name)
        local childRelative=relative=="" and name or relative.."/"..name
        if fs.isDir(child) then
            collectFiles(root,child,childRelative,result)
        else
            result[#result+1]={source=child,relative=childRelative}
        end
    end
end

local function readBackupIndex(backup)
    local indexPath=fs.combine(backup,"backup.lua")
    if not fs.exists(indexPath) or fs.isDir(indexPath) then return nil end
    local f=fs.open(indexPath,"r")
    if not f then return nil end
    local source=f.readAll() or ""
    f.close()
    local ok,value=pcall(textutils.unserialize,source)
    if ok and type(value)=="table" and type(value.locations)=="table" then return value end
    return nil
end

local function cleanupBackup(paths,backup)
    local name=backupName(backup)
    for _,root in ipairs(backupSearchRoots(paths)) do
        local path=fs.combine(root,name)
        if fs.exists(path) then pcall(fs.delete,path) end
    end
end

local function restoreBackup(paths,backup,destination)
    local index=readBackupIndex(backup)
    if not index then
        local source=fs.combine(backup,"system")
        if not fs.exists(source) then error("Rollback backup is incomplete: "..tostring(backup)) end
        transfer(source,destination)
        return
    end
    local moved={}
    local ok,err=pcall(function()
        for relative,source in pairs(index.locations) do
            if not safeRelative(relative) or type(source)~="string" or not fs.exists(source) or fs.isDir(source) then
                error("Rollback backup file is missing: "..tostring(relative))
            end
            local target=fs.combine(destination,relative)
            transfer(source,target)
            moved[#moved+1]={source=source,target=target}
        end
    end)
    if not ok then
        for index=#moved,1,-1 do
            local item=moved[index]
            if fs.exists(item.target) then pcall(transfer,item.target,item.source) end
        end
        error(err)
    end
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
    self.stageRoots = {}
    self.stagedBytes = {}
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
    for _,root in ipairs(updateRoots(self.paths)) do if fs.exists(root) then pcall(fs.delete,root) end end
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

function Updater:refreshAppRegistry()
    if self.appRegistry and type(self.appRegistry.scan)=="function" then
        local ok,err=pcall(self.appRegistry.scan,self.appRegistry)
        if not ok then self.logger:warn("Application registry refresh failed: "..tostring(err)) end
    end
end

function Updater:pruneRemovedAppPackages()
    local allowed={}
    for _,entry in ipairs((self.manifest and self.manifest.files) or {}) do
        local path=type(entry)=="string" and entry or entry and entry.path
        local id=type(path)=="string" and path:match("^apps/([^/]+)/")
        if id then allowed[id]=true end
    end
    local root=fs.combine(self.paths.system,"apps")
    if not fs.exists(root) or not fs.isDir(root) then return end
    for _,name in ipairs(fs.list(root)) do
        local path=fs.combine(root,name)
        if fs.isDir(path) and fs.exists(fs.combine(path,"manifest.lua")) and not allowed[name] then
            fs.delete(path)
        elseif not fs.isDir(path) then
            local id=name:match("^([a-z][a-z0-9_-]*)%.lua$")
            if id and allowed[id] and fs.exists(fs.combine(root,id,"manifest.lua")) then fs.delete(path) end
        end
    end
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
    local stageFree=0
    local stageExternal=false
    for _,root in ipairs(updateRoots(self.paths)) do
        local value=freeSpace(root)
        if type(value)=="number" then stageFree=stageFree+value elseif value=="unlimited" then stageFree=math.huge end
        if driveOf(root) and driveOf(root)~=driveOf("/") then stageExternal=true end
    end
    local backupFree=0
    for _,root in ipairs(backupRoots(self.paths)) do
        local value=freeSpace(root)
        if type(value)=="number" then backupFree=backupFree+value elseif value=="unlimited" then backupFree=math.huge end
    end
    local currentSize=treeSize(self.paths.system)
    if stageExternal then
        -- The update and the distributed rollback backup share the mounted
        -- disks.  Reserve both before allowing the download to start.
        required=math.max(65536,tonumber(manifest and manifest.maxFileSize) or 40000)*2
        if type(stageFree)=="number" and stageFree<installed+currentSize+32768 then return false end
        if type(backupFree)=="number" and backupFree<currentSize+16384 then return false end
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
    local prepared,prepareError=pcall(function()
        for _,root in ipairs(updateRoots(self.paths)) do
            if fs.exists(root) then pcall(fs.delete,root) end
            fs.makeDir(root)
        end
    end)
    if not prepared then
        self.state = {phase="failed", current="", completed=0, total=#files, message="Update storage unavailable: "..tostring(prepareError)}
        self.logger:error(self.state.message)
        return false, self.state.message
    end
    self.manifest = manifest
    self.files = files
    self.repairOnly = repairOnly == true
    self.fileIndex = 0
    self.downloadedBytes = 0
    self.stageRoots = {}
    self.stagedBytes = {}
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
    local selected,selectedFree
    for _,root in ipairs(updateRoots(self.paths)) do
        local free=freeSpace(root)
        if free=="unlimited" then free=math.huge end
        if type(free)=="number" then
            free=free-(self.stagedBytes[root] or 0)
            if free>=#body+4096 and (not selectedFree or free>selectedFree) then selected,selectedFree=root,free end
        end
    end
    if selected then
        local target=fs.combine(selected,file.path)
        local ok,writeError=writeBytes(target,body)
        if not ok then return false,writeError end
        self.stageRoots[file.path]=selected
        self.stagedBytes[selected]=(self.stagedBytes[selected] or 0)+#body
    else
        -- A file can be larger than every remaining floppy even when the
        -- aggregate free space across all floppies is sufficient. Stage
        -- numbered binary parts and reconstruct the file during apply.
        local candidates={}
        for _,root in ipairs(updateRoots(self.paths)) do
            local free=freeSpace(root)
            if free=="unlimited" then free=math.huge end
            if type(free)=="number" then
                free=free-(self.stagedBytes[root] or 0)-4096
                if free>0 then candidates[#candidates+1]={root=root,free=free} end
            end
        end
        table.sort(candidates,function(a,b) return a.free>b.free end)
        local parts={}; local offset=1; local partIndex=0
        for _,candidate in ipairs(candidates) do
            if offset>#body then break end
            local partSize=math.min(#body-offset+1,math.max(0,math.floor(candidate.free)))
            if partSize>0 then
                partIndex=partIndex+1
                local partPath=fs.combine(candidate.root,file.path..".part"..string.format("%03d",partIndex))
                local ok,writeError=writeBytes(partPath,body:sub(offset,offset+partSize-1))
                if not ok then
                    for _,part in ipairs(parts) do if fs.exists(part.path) then pcall(fs.delete,part.path) end end
                    if fs.exists(partPath) then pcall(fs.delete,partPath) end
                    return false,writeError
                end
                parts[#parts+1]={path=partPath,size=partSize}
                self.stagedBytes[candidate.root]=(self.stagedBytes[candidate.root] or 0)+partSize
                offset=offset+partSize
            end
        end
        if offset<=#body then
            for _,part in ipairs(parts) do if fs.exists(part.path) then pcall(fs.delete,part.path) end end
            return false,"No combined update disk space remains for "..file.path
        end
        self.stageRoots[file.path]={parts=parts,size=#body}
    end
    self.downloadedBytes = self.downloadedBytes + #body
    return true
end

function Updater:stagedPath(relative)
    local selected=self.stageRoots and self.stageRoots[relative]
    if type(selected)=="string" then return fs.combine(selected,relative) end
    for _,root in ipairs(updateRoots(self.paths)) do
        local candidate=fs.combine(root,relative)
        if fs.exists(candidate) then return candidate end
    end
    return fs.combine(self.paths.updateTemp,relative)
end

function Updater:stagedFileAvailable(relative)
    local selected=self.stageRoots and self.stageRoots[relative]
    if type(selected)=="table" and type(selected.parts)=="table" then return #selected.parts>0 end
    local source=self:stagedPath(relative)
    return fs.exists(source) and not fs.isDir(source)
end

function Updater:installStaged(relative,target)
    local selected=self.stageRoots and self.stageRoots[relative]
    if type(selected)~="table" or type(selected.parts)~="table" then
        local source=self:stagedPath(relative)
        if not fs.exists(source) or fs.isDir(source) then error("Staged update file is missing: "..relative) end
        transfer(source,target)
        return
    end
    local ok,err=pcall(function()
        ensureParent(target)
        local output,openError=fs.open(target,"wb")
        if not output then error(openError or "staged file is not writable") end
        local outputClosed=false
        local success,reason=pcall(function()
            for _,part in ipairs(selected.parts) do
                local input,inputError=fs.open(part.path,"rb")
                if not input then error(inputError or "staged file part is missing") end
                local readOk,readError=pcall(function()
                    while true do
                        local chunk=input.read(32768)
                        if not chunk or #chunk==0 then break end
                        output.write(chunk)
                    end
                end)
                pcall(input.close)
                if not readOk then error(readError) end
            end
            local closeOk,closeError=pcall(output.close); outputClosed=closeOk
            if not closeOk then error(closeError) end
        end)
        if not success then
            if not outputClosed then pcall(output.close) end
            error(reason)
        end
    end)
    if not ok then
        if fs.exists(target) then pcall(fs.delete,target) end
        error(err)
    end
    for _,part in ipairs(selected.parts) do if fs.exists(part.path) then pcall(fs.delete,part.path) end end
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
    local roots=backupRoots(self.paths)
    local primary=roots[1] or self.paths.backups or "/.hccos/backups"
    local name=safeVersion(version)
    local function nameExists(value)
        for _,root in ipairs(backupSearchRoots(self.paths)) do
            if fs.exists(fs.combine(root,value)) then return true end
        end
        return false
    end
    if nameExists(name) then name=name.."-"..tostring(os.epoch("utc")) end
    local destination=fs.combine(primary,name)
    local moved={}
    local locations={}
    local usage={}
    local files={}
    if fs.exists(self.paths.system) then collectFiles(self.paths.system,self.paths.system,"",files) end
    local ok,err=pcall(function()
        if not fs.exists(destination) then fs.makeDir(destination) end
        for _,file in ipairs(files) do
            local size=math.max(0,tonumber(fs.getSize(file.source)) or 0)
            local selected,selectedFree
            for _,root in ipairs(roots) do
                local free=freeSpace(root)
                if free=="unlimited" or free==nil then free=math.huge end
                if type(free)=="number" then
                    free=free-(usage[root] or 0)
                    if free>=size+4096 and (not selectedFree or free>selectedFree) then selected,selectedFree=root,free end
                end
            end
            if not selected then error("No backup disk has enough free space for "..file.relative) end
            local target=fs.combine(selected,name.."/parts/"..file.relative)
            ensureParent(target)
            transfer(file.source,target)
            moved[#moved+1]={source=file.source,target=target}
            locations[file.relative]=target
            usage[selected]=(usage[selected] or 0)+size
        end
        local index=fs.open(fs.combine(destination,"backup.lua"),"w")
        if not index then error("Could not write distributed rollback index") end
        local serialized=textutils.serialize({version=tostring(version or "unknown"),locations=locations})
        local wrote=pcall(index.write,serialized)
        index.close()
        if not wrote then error("Could not write distributed rollback index") end
    end)
    if not ok then
        for index=#moved,1,-1 do
            local item=moved[index]
            if fs.exists(item.target) then pcall(transfer,item.target,item.source) end
        end
        cleanupBackup(self.paths,destination)
        return nil,err
    end
    return destination
end

function Updater:moveTree(source, destination, skip)
    if not fs.isDir(source) then transfer(source, destination); return end
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
                local target = fs.combine(self.paths.system, file.path)
                if not self:stagedFileAvailable(file.path) then error("Staged repair file is missing: "..file.path) end
                local backup = fs.combine(rollbackRoot, file.path)
                local hadOriginal = fs.exists(target)
                local item={path=target, backup=backup, moved=false, installed=false}
                placed[#placed+1] = item
                if hadOriginal then transfer(target,backup); item.moved=true end
                self:installStaged(file.path,target); item.installed=true
            end
            for _,root in ipairs(updateRoots(self.paths)) do
                if fs.exists(root) then fs.delete(root) end
            end
        end)
        if not ok then
            local restored=true
            for index=#placed,1,-1 do
                local item=placed[index]
                local recovered=pcall(function()
                    if item.installed and fs.exists(item.path) then fs.delete(item.path) end
                    if item.moved then transfer(item.backup,item.path) end
                end)
                restored=restored and recovered
            end
            if restored and fs.exists(rollbackRoot) then pcall(fs.delete,rollbackRoot) end
            for _,root in ipairs(updateRoots(self.paths)) do
                if fs.exists(root) then pcall(fs.delete,root) end
            end
            self.state.phase, self.state.message = "failed", (restored and "Repair rolled back: " or "Repair recovery required; backup kept at "..rollbackRoot..": ")..tostring(err)
            self.logger:error(self.state.message)
            return false, err
        end
        if fs.exists(rollbackRoot) then pcall(fs.delete,rollbackRoot) end
        self.state.phase, self.state.message = "applied", "Repair applied; restart HCC OS"
        self:refreshAppRegistry()
        self.logger:info("Repaired "..tostring(#(self.files or {})).." system files")
        return true
    end
    local oldVersion = self.localManifest and self.localManifest.version or "previous"
    local backupOk, backup, backupError = pcall(self.backupCurrent, self, oldVersion)
    if not backupOk or not backup then return false, backupError or backup end
    local ok, err = pcall(function()
        if not self:stagedFileAvailable("version.lua") then error("Downloaded version information is missing") end
        fs.makeDir(self.paths.system)
        for _,file in ipairs(self.files or {}) do
            if file.path ~= "version.lua" then
                if not self:stagedFileAvailable(file.path) then error("Staged update file is missing: "..file.path) end
                self:installStaged(file.path,fs.combine(self.paths.system,file.path))
            end
        end
        self:installStaged("version.lua",self.paths.versionFile)
        self:pruneRemovedAppPackages()
        for _,root in ipairs(updateRoots(self.paths)) do
            if fs.exists(root) then fs.delete(root) end
        end
    end)
    if not ok then
        local restored=pcall(function()
            if fs.exists(self.paths.system) then fs.delete(self.paths.system) end
            restoreBackup(self.paths,backup,self.paths.system)
        end)
        if restored then cleanupBackup(self.paths,backup) end
        for _,root in ipairs(updateRoots(self.paths)) do
            if fs.exists(root) then pcall(fs.delete,root) end
        end
        self.state.phase, self.state.message = "failed", (restored and "Update rolled back: " or "Update recovery required; backup kept at "..backup..": ")..tostring(err)
        self.logger:error(self.state.message)
        return false, err
    end
    self.localManifest = self.manifest
    self.state.phase, self.state.message = "applied", "Update applied; restart HCC OS"
    self:refreshAppRegistry()
    self.logger:info("Updated to "..tostring(self.manifest.version).." build "..tostring(self.manifest.build))
    return true
end

function Updater:rollback(version)
    local requested=version and safeVersion(version) or nil
    local candidates={}
    local byName={}
    for _,root in ipairs(backupSearchRoots(self.paths)) do
        if fs.exists(root) and fs.isDir(root) then
            for _,entry in ipairs(fs.list(root)) do
                local path=fs.combine(root,entry)
                if fs.isDir(path) and (fs.exists(path.."/backup.lua") or fs.exists(path.."/system")) then
                    if not byName[entry] or fs.exists(path.."/backup.lua") then byName[entry]=path end
                end
            end
        end
    end
    for _,path in pairs(byName) do candidates[#candidates+1]=path end
    local selected=requested and byName[requested] or nil
    if not selected then
        table.sort(candidates, function(a,b) return a>b end)
        selected=candidates[1]
    end
    if not selected or (not readBackupIndex(selected) and not fs.exists(selected.."/system")) then return false, "No rollback backup is available" end

    if readBackupIndex(selected) then
        local currentVersion=self.localManifest and self.localManifest.version or "current"
        local currentBackup,currentError=self:backupCurrent(currentVersion)
        if not currentBackup then return false,"Could not preserve the current system: "..tostring(currentError) end
        local restored,restoreError=pcall(function()
            if fs.exists(self.paths.system) then fs.delete(self.paths.system) end
            restoreBackup(self.paths,selected,self.paths.system)
        end)
        if not restored then
            local recovered=pcall(function()
                if fs.exists(self.paths.system) then fs.delete(self.paths.system) end
                restoreBackup(self.paths,currentBackup,self.paths.system)
            end)
            if recovered then cleanupBackup(self.paths,currentBackup) end
            return false,(recovered and "Rollback failed and was restored: " or "Rollback recovery required: ")..tostring(restoreError)
        end
        cleanupBackup(self.paths,selected)
        self.logger:warn("Rolled back HCC OS using "..selected)
        self:refreshAppRegistry()
        self.state.phase, self.state.message = "rolledback", "Rollback complete; restart HCC OS"
        return true
    end

    local temporary = self.paths.temp.."/rollback-current"
    if fs.exists(temporary) then fs.delete(temporary) end
    local movedCurrent, movedBackup = false, false
    local ok, err = pcall(function()
        if fs.exists(self.paths.system) then transfer(self.paths.system, temporary); movedCurrent=true end
        transfer(selected.."/system", self.paths.system); movedBackup=true
        if movedCurrent then transfer(temporary, selected.."/system"); movedCurrent=false end
    end)
    if not ok then
        if movedBackup and fs.exists(self.paths.system) then pcall(transfer,self.paths.system,selected.."/system") end
        if fs.exists(temporary) then transfer(temporary, self.paths.system) end
        return false, err
    end
    self.logger:warn("Rolled back HCC OS using "..selected)
    self:refreshAppRegistry()
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
