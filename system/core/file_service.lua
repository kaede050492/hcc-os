-- Shared guarded file access for user-facing applications.
local FileService = {}
FileService.__index = FileService

local TEMP_SUFFIX = ".hccos-tmp"
local PREVIOUS_SUFFIX = ".hccos-prev"

local function checkedLimit(value, default, maximum)
    if value == nil then return default end
    local limit = tonumber(value)
    if not limit or limit ~= limit or limit < 0 or limit > maximum then return nil end
    return math.floor(limit)
end

local function safeExists(api, path)
    local ok, value = pcall(api.exists, path)
    if not ok then return nil, tostring(value) end
    return value == true
end

local function safeDelete(api, path)
    local exists, existsError = safeExists(api, path)
    if exists == nil then return false, existsError end
    if not exists then return true end
    local checked, isDirectory = pcall(api.isDir, path)
    if not checked then return false, isDirectory end
    if isDirectory then return false, "Recovery path is a directory" end
    local ok, err = pcall(api.delete, path)
    if not ok then return false, err end
    local remains, verifyError = safeExists(api, path)
    if remains == nil then return false, verifyError end
    if remains then return false, "Recovery file remains after deletion" end
    return true
end

function FileService.new(options)
    options = options or {}
    local self = setmetatable({fs=options.fs or fs, paths=options.paths or {}, logger=options.logger}, FileService)
    self.protected = {}
    self.managed = {}
    local function protect(path)
        if type(path) == "string" and path ~= "" then
            local ok, canonical = pcall(self.fs.combine, "/", path)
            if ok and type(canonical) == "string" then
                canonical = canonical:gsub("^/+", ""):gsub("/+$", "")
                if canonical ~= "" then self.protected[#self.protected+1] = canonical end
            end
        end
    end
    local function manage(path)
        if type(path) == "string" and path ~= "" then
            local ok, canonical = pcall(self.fs.combine, "/", path)
            if ok and type(canonical) == "string" then
                canonical = canonical:gsub("^/+", ""):gsub("/+$", "")
                if canonical ~= "" then self.managed[#self.managed+1] = canonical end
            end
        end
    end
    for _, path in ipairs({self.paths.system, self.paths.config, self.paths.legacySettings,
        self.paths.startup, self.paths.backups, self.paths.temp, self.paths.updateTemp,
        self.paths.cache, self.paths.logs, "/boot.lua", "/installer.lua"}) do
        protect(path)
    end
    for _, group in ipairs({self.paths.backupRoots or {}, self.paths.updateTemps or {}}) do
        for _, path in ipairs(group) do protect(path) end
    end
    manage(self.paths.currency)
    manage(self.paths.currencyBackup)
    return self
end

function FileService:normalisePath(path)
    if type(path) ~= "string" or path == "" or #path > 512 or path:find("%z") then
        return nil, "Invalid file path"
    end
    local ok, canonical = pcall(self.fs.combine, "/", path)
    if not ok or type(canonical) ~= "string" then return nil, "Invalid file path" end
    canonical = canonical:gsub("^/+", ""):gsub("/+$", "")
    if canonical == "" then return nil, "Choose a file, not the filesystem root" end
    return canonical
end

function FileService:isProtected(path)
    local canonical = self:normalisePath(path)
    if not canonical then return true end
    for _, root in ipairs(self.protected) do
        if canonical == root or canonical:sub(1, #root+1) == root.."/" then return true end
    end
    return false
end

function FileService:isManagedPath(path)
    local canonical = self:normalisePath(path)
    if not canonical then return true end
    for _, managed in ipairs(self.managed) do
        if canonical == managed then return true end
    end
    return false
end

function FileService:isInternalPath(path)
    local canonical = self:normalisePath(path)
    return canonical ~= nil and (canonical:sub(-#TEMP_SUFFIX) == TEMP_SUFFIX or
        canonical:sub(-#PREVIOUS_SUFFIX) == PREVIOUS_SUFFIX)
end

function FileService:canWrite(path, managedWrite)
    local canonical, pathError = self:normalisePath(path)
    if not canonical then return false, pathError end
    if self:isProtected(canonical) then return false, "This path is managed by an OS service" end
    if self:isManagedPath(canonical) and managedWrite ~= true then return false, "This file is managed by the Currency service" end
    if self:isInternalPath(canonical) then return false, "This path is reserved for safe file saves" end
    local api = self.fs
    local exists, existsError = safeExists(api, canonical)
    if exists == nil then return false, existsError end
    if exists then
        local ok, isDirectory = pcall(api.isDir, canonical)
        if not ok then return false, tostring(isDirectory) end
        if isDirectory then return false, "Choose a file, not a directory" end
    end
    local parentOk, parent = pcall(api.getDir, canonical)
    if not parentOk then return false, tostring(parent) end
    if parent == "" then parent = "/" end
    local parentOk, parentExists = pcall(api.exists, parent)
    local dirOk, parentIsDir = pcall(api.isDir, parent)
    if not parentOk or not parentExists or not dirOk or not parentIsDir then
        return false, "The parent directory does not exist"
    end
    local readOnlyOk, parentReadOnly = pcall(api.isReadOnly, parent)
    if not readOnlyOk then return false, tostring(parentReadOnly) end
    if parentReadOnly then return false, "The destination is read-only" end
    if exists then
        local readOnly, value = pcall(api.isReadOnly, canonical)
        if not readOnly then return false, tostring(value) end
        if value then return false, "The file is read-only" end
    end
    return true, canonical
end

function FileService:canDelete(path)
    local allowed, canonical = self:canWrite(path)
    if not allowed then return false, canonical end
    local recovered, recoveryError = self:_recover(canonical)
    if not recovered then return false, recoveryError end
    allowed, canonical = self:canWrite(canonical)
    if not allowed then return false, canonical end
    local existsOk, exists = pcall(self.fs.exists, canonical)
    if not existsOk or not exists then return false, "The file no longer exists" end
    local dirOk, isDirectory = pcall(self.fs.isDir, canonical)
    if not dirOk then return false, tostring(isDirectory) end
    if isDirectory then return false, "Deleting directories is disabled" end
    return true, canonical
end

function FileService:deleteFile(path)
    local allowed, canonical = self:canDelete(path)
    if not allowed then return false, canonical end
    local removed, removeError = safeDelete(self.fs, canonical)
    if not removed then return false, tostring(removeError or "Could not delete file") end
    return true, canonical
end

function FileService:_readRaw(path, limit)
    local api = self.fs
    local sizeOk, size = pcall(api.getSize, path)
    if not sizeOk or type(size) ~= "number" then return nil, tostring(size) end
    if size > limit then return nil, "File exceeds the "..tostring(limit).." byte limit" end
    local opened, file, openError = pcall(api.open, path, "rb")
    if not opened then return nil, tostring(file) end
    if not file then return nil, tostring(openError or "Could not open file") end
    local readOk, contents = pcall(file.readAll)
    local closeOk, closeError = pcall(file.close)
    if not readOk then return nil, tostring(contents) end
    if not closeOk then return nil, tostring(closeError) end
    if type(contents) ~= "string" then return nil, "File did not return text" end
    if #contents > limit then return nil, "File exceeds the "..tostring(limit).." byte limit" end
    return contents
end

function FileService:_matches(path, expected, limit)
    local api = self.fs
    local sizeOk, size = pcall(api.getSize, path)
    if not sizeOk or type(size) ~= "number" then return false, tostring(size) end
    if size ~= #expected or size > limit then return false, "File size does not match the staged contents" end
    local opened, file, openError = pcall(api.open, path, "rb")
    if not opened then return false, tostring(file) end
    if not file then return false, tostring(openError or "Could not open file for verification") end
    local offset, mismatch = 1, nil
    while offset <= #expected do
        local count = math.min(4096, #expected-offset+1)
        local parts, received = {}, 0
        while received < count do
            local readOk, chunk = pcall(file.read, count-received)
            if not readOk then mismatch = tostring(chunk); break end
            if type(chunk) ~= "string" or #chunk == 0 then
                mismatch = "File ended before all staged contents were read"; break
            end
            parts[#parts+1]=chunk; received=received+#chunk
        end
        if mismatch then break end
        if table.concat(parts) ~= expected:sub(offset, offset+count-1) then
            mismatch = "File contents do not match the staged contents"; break
        end
        offset = offset + count
    end
    if not mismatch then
        local readOk, extra = pcall(file.read, 1)
        if not readOk then mismatch = tostring(extra)
        elseif extra ~= nil and extra ~= "" then mismatch = "File contains unexpected trailing data" end
    end
    local closeOk, closeError = pcall(file.close)
    if not closeOk then return false, tostring(closeError) end
    return mismatch == nil, mismatch
end

function FileService:_recover(path)
    local api = self.fs
    local temporary, previous = path..TEMP_SUFFIX, path..PREVIOUS_SUFFIX
    local targetExists, existsError = safeExists(api, path)
    if targetExists == nil then return false, existsError end
    if targetExists then
        local previousExists, previousError = safeExists(api, previous)
        if previousExists == nil then return false, previousError end
        if previousExists then
            local dirOk, isDirectory = pcall(api.isDir, previous)
            if not dirOk or isDirectory then return false, "Previous recovery path is not a file" end
            local removed, removeError = safeDelete(api, path)
            if not removed then return false, tostring(removeError or "Could not restore the previous file") end
            local moved, moveError = pcall(api.move, previous, path)
            local restored, restoreError = safeExists(api, path)
            if not moved or restored ~= true then
                return false, "Could not restore the previous file: "..tostring(moveError or restoreError or previous)
            end
        end
        local removed, err = safeDelete(api, temporary)
        if not removed then return false, tostring(err or "Could not remove incomplete save") end
        return true
    end
    local previousExists, previousError = safeExists(api, previous)
    if previousExists == nil then return false, previousError end
    if previousExists then
        local dirOk, isDirectory = pcall(api.isDir, previous)
        if not dirOk or isDirectory then return false, "Previous recovery path is not a file" end
        local moved, err = pcall(api.move, previous, path)
        local restored = safeExists(api, path)
        if not moved or restored ~= true then
            return false, "Could not restore the previous file: "..tostring(err or previous)
        end
    end
    local removed, err = safeDelete(api, temporary)
    if not removed then return false, tostring(err or "Could not remove incomplete save") end
    return true
end

function FileService:readText(path, limit)
    local canonical, pathError = self:normalisePath(path)
    if not canonical then return nil, pathError end
    if self:isInternalPath(canonical) then return nil, "This path is reserved for safe file saves" end
    limit = checkedLimit(limit,65536,16777216)
    if not limit then return nil, "Invalid file size limit" end
    local recovered, recoveryError = self:_recover(canonical)
    if not recovered then return nil, recoveryError end
    local exists, existsError = safeExists(self.fs, canonical)
    if exists == nil then return nil, existsError end
    if not exists then return nil, "File does not exist" end
    local dirOk, isDirectory = pcall(self.fs.isDir, canonical)
    if not dirOk then return nil, tostring(isDirectory) end
    if isDirectory then return nil, "Cannot open a directory as a file" end
    return self:_readRaw(canonical, limit)
end

function FileService:writeAtomic(path, contents, limit, managedWrite)
    if type(contents) ~= "string" then return false, "File contents must be bytes" end
    limit = checkedLimit(limit,65536,16777216)
    if not limit then return false, "Invalid file size limit" end
    if #contents > limit then return false, "File exceeds the "..tostring(limit).." byte limit" end
    local allowed, canonical = self:canWrite(path, managedWrite)
    if not allowed then return false, canonical end
    local recovered, recoveryError = self:_recover(canonical)
    if not recovered then return false, recoveryError end
    allowed, canonical = self:canWrite(canonical, managedWrite)
    if not allowed then return false, canonical end

    local api = self.fs
    local temporary, previous = canonical..TEMP_SUFFIX, canonical..PREVIOUS_SUFFIX
    local opened, file, openError = pcall(api.open, temporary, "wb")
    if not opened then return false, tostring(file) end
    if not file then return false, tostring(openError or "Could not open temporary file") end
    local writeOk, writeError = pcall(file.write, contents)
    local closeOk, closeError = pcall(file.close)
    if not writeOk or not closeOk then
        safeDelete(api, temporary)
        return false, tostring(writeError or closeError or "Could not finish temporary file")
    end
    local staged, stageError = self:_matches(temporary, contents, limit)
    if not staged then
        safeDelete(api, temporary)
        return false, tostring(stageError or "Temporary file verification failed")
    end

    local hadOriginal, existsError = safeExists(api, canonical)
    if hadOriginal == nil then safeDelete(api, temporary); return false, existsError end
    if hadOriginal then
        local moved, moveError = pcall(api.move, canonical, previous)
        local previousExists, previousError = safeExists(api, previous)
        local sourceExists, sourceError = safeExists(api, canonical)
        if not moved or previousExists ~= true or sourceExists ~= false then
            safeDelete(api, temporary)
            return false, tostring(moveError or previousError or sourceError or "Could not preserve the original file")
        end
    end
    local committed, commitError = pcall(api.move, temporary, canonical)
    local verified, verifyError
    local targetExists, targetError = safeExists(api, canonical)
    if committed and targetExists == true then verified, verifyError = self:_matches(canonical, contents, limit) end
    if not committed or not verified then
        if targetExists == nil then
            return false, "Save state is uncertain; recovery files were preserved: "..tostring(targetError)
        end
        if targetExists then safeDelete(api, canonical) end
        local previousExists = safeExists(api, previous)
        if hadOriginal and previousExists == true then
            local restored, restoreError = pcall(api.move, previous, canonical)
            local restoredExists = safeExists(api, canonical)
            if not restored or restoredExists ~= true then
                return false, "Save failed and the original remains at "..previous..": "..
                    tostring(restoreError or commitError or verifyError or "restore failed")
            end
        end
        safeDelete(api, temporary)
        return false, tostring(commitError or verifyError or "Saved file verification failed")
    end

    local removed, removeError = safeDelete(api, previous)
    if not removed then
        if not hadOriginal then
            return false, "Save verified but could not remove the recovery path: "..tostring(removeError)
        end
        local targetRemoved, targetRemoveError = safeDelete(api, canonical)
        if targetRemoved then
            local restored, restoreError = pcall(api.move, previous, canonical)
            local targetRestored = safeExists(api, canonical)
            if not restored or targetRestored ~= true then
                return false, "Save verified but could not finalize recovery cleanup; previous file remains at "..
                    previous..": "..tostring(restoreError or targetRemoveError or removeError)
            end
        else
            return false, "Save verified but could not finalize recovery cleanup; previous file remains at "..
                previous..": "..tostring(targetRemoveError or removeError)
        end
        return false, "Save could not be finalized; the previous file was restored: "..tostring(removeError)
    end
    return true
end

function FileService:writeTextAtomic(path, contents, limit)
    return self:writeAtomic(path, contents, limit)
end

function FileService:writeManagedAtomic(path, contents, limit)
    return self:writeAtomic(path, contents, limit, true)
end

return {new=function(options) return FileService.new(options) end}
