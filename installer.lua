-- HCC OS v1.4.0 standalone installer.
-- This file is intentionally self-contained. It is safe to wget only this
-- file onto an empty CC:T computer and run it.

-- GitHub is the source of truth for installation. Change only these constants
-- when publishing HCC OS under a different public repository.
local GITHUB_USER = "kaede050492"
local GITHUB_REPOSITORY = "hcc-os"
local GITHUB_BRANCH = "main"
local RAW_ROOT = "https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPOSITORY.."/"..GITHUB_BRANCH
local MANIFEST_URL = RAW_ROOT.."/hcc_os/manifest.lua"

-- CC:T target paths. The Windows/GitHub hcc_os/ directory is never used as a
-- target directory on the computer being installed.
local SYSTEM_ROOT = "/.hccos/system"
local CONFIG_ROOT = "/.hccos/config"
local TEMP_ROOT = "/.hccos/temp/installer"
local TEMP_SYSTEM = TEMP_ROOT.."/system"
local TEMP_LEGACY = TEMP_ROOT.."/hccos_v1.3.3.lua"
local TEMP_STARTUP = TEMP_ROOT.."/startup.lua"
local BACKUP_ROOT = "/.hccos/backups"
local STARTUP = "/startup.lua"
local LEGACY = "/hccos_v1.3.3.lua"
local DATA_DIRECTORIES = {
    "/.hccos", CONFIG_ROOT, "/.hccos/images", "/.hccos/cache",
    "/.hccos/downloads", "/.hccos/logs", BACKUP_ROOT, "/.hccos/temp"
}

local function safeRelative(path)
    if type(path) ~= "string" or path == "" or #path > 160 then return false end
    if path:find("[%z\\]") or path:sub(1, 1) == "/" or path:match("^[A-Za-z]:") then return false end
    for part in path:gmatch("[^/]+") do
        if part == ".." or part == "." or part == "" then return false end
    end
    return true
end

local function safeVersion(value)
    return tostring(value or "previous"):gsub("[^%w%._%-]", "_"):sub(1, 48)
end

local function makeDir(path)
    if fs.exists(path) then
        if not fs.isDir(path) then error("Not a directory: "..path) end
        return
    end
    local parent = fs.getDir(path)
    if parent ~= "" and parent ~= path then makeDir(parent) end
    fs.makeDir(path)
end

local function ensureParent(path)
    makeDir(fs.getDir(path))
end

local function readAll(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, err end
    local ok, value = pcall(f.readAll)
    f.close()
    if not ok then return nil, value end
    return value or ""
end

local function writeAll(path, value)
    ensureParent(path)
    local f, err = fs.open(path, "w")
    if not f then return false, err end
    local ok, writeError = pcall(f.write, value)
    f.close()
    return ok, writeError
end

local function fetch(url)
    if type(http) ~= "table" or type(http.get) ~= "function" then
        return nil, "CC:T HTTP API unavailable"
    end
    if type(url) ~= "string" or not url:match("^https://[^%s]+$") then
        return nil, "unsafe HTTPS URL"
    end
    local ok, handle = pcall(http.get, url, { ["User-Agent"] = "HCC-OS-Installer/1.4.0" })
    if not ok or not handle then return nil, tostring(handle or "HTTP request denied") end
    local readOk, body = pcall(handle.readAll)
    local code = 200
    if type(handle.getResponseCode) == "function" then
        local codeOk, responseCode = pcall(handle.getResponseCode)
        if codeOk and responseCode then code = responseCode end
    end
    if handle.close then pcall(handle.close) end
    if not readOk then return nil, "HTTP response could not be read" end
    if code < 200 or code >= 300 then return nil, "HTTP "..tostring(code) end
    if type(body) ~= "string" or #body == 0 then return nil, "empty HTTP response" end
    return body
end

local function parseManifest(source)
    -- The manifest is evaluated in an empty environment; it is data only.
    local chunk, err = load(source, "@remote manifest.lua", "t", {})
    if not chunk then return nil, err end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, "manifest is invalid" end
    if type(value.version) ~= "string" or value.version == "" then return nil, "manifest version is missing" end
    if type(value.files) ~= "table" then return nil, "manifest files list is missing" end
    return value
end

local function systemUrl(relative)
    if relative == "manifest.lua" then return RAW_ROOT.."/hcc_os/manifest.lua" end
    return RAW_ROOT.."/hcc_os/system/"..relative
end

local function systemPath(relative)
    if not safeRelative(relative) then error("Unsafe manifest path: "..tostring(relative)) end
    return fs.combine(TEMP_SYSTEM, relative)
end

local function manifestEntries(manifest)
    local entries, seen = {}, {}
    for _, raw in ipairs(manifest.files) do
        local relative = type(raw) == "string" and raw or raw and raw.path
        if not safeRelative(relative) then error("Unsafe manifest path: "..tostring(relative)) end
        if seen[relative] then error("Duplicate manifest path: "..relative) end
        seen[relative] = true
        entries[#entries+1] = {path=relative, size=type(raw) == "table" and tonumber(raw.size) or nil}
    end
    if #entries == 0 then error("Manifest has no system files") end
    return entries
end

local function currentVersion()
    local source = readAll(SYSTEM_ROOT.."/version.lua")
    return source and (source:match("version%s*=%s*['\"]([^'\"]+)") or "previous") or "previous"
end

local function treeSize(path)
    if not fs.exists(path) then return 0 end
    if not fs.isDir(path) then return fs.getSize(path) or 0 end
    local total = 0
    for _, name in ipairs(fs.list(path)) do total = total + treeSize(fs.combine(path, name)) end
    return total
end

local function hasSpace(required)
    if type(fs.getFreeSpace) ~= "function" then return true end
    local ok, free = pcall(fs.getFreeSpace, "/")
    if not ok or type(free) ~= "number" then return true end
    return free > required + treeSize(SYSTEM_ROOT) + treeSize(LEGACY) + treeSize(STARTUP) + 32768
end

local function fetchSystem(entries)
    makeDir(TEMP_SYSTEM)
    local downloaded = 0
    for index, entry in ipairs(entries) do
        print(string.format("Downloading %d/%d: %s", index, #entries, entry.path))
        local body, err = fetch(systemUrl(entry.path))
        if not body then error(entry.path..": "..tostring(err)) end
        if entry.size and #body ~= entry.size then error(entry.path..": size mismatch") end
        local destination = systemPath(entry.path)
        local ok, writeError = writeAll(destination, body)
        if not ok then error(destination..": "..tostring(writeError)) end
        downloaded = downloaded + #body
    end
    return downloaded
end

local function fetchExtra(path, destination)
    print("Downloading: "..path)
    local body, err = fetch(RAW_ROOT.."/"..path)
    if not body then error(path..": "..tostring(err)) end
    local ok, writeError = writeAll(destination, body)
    if not ok then error(destination..": "..tostring(writeError)) end
    return #body
end

local function backupPath()
    makeDir(BACKUP_ROOT)
    local path = BACKUP_ROOT.."/"..safeVersion(currentVersion())
    if fs.exists(path) then path = path.."-"..tostring(os.epoch("utc")) end
    makeDir(path)
    return path
end

local function restorePlacement(state)
    if state.newStartup and fs.exists(STARTUP) then pcall(fs.delete, STARTUP) end
    if state.oldStartup and fs.exists(state.backup.."/startup.lua") then pcall(fs.move, state.backup.."/startup.lua", STARTUP) end
    if state.newLegacy and fs.exists(LEGACY) then pcall(fs.delete, LEGACY) end
    if state.oldLegacy and fs.exists(state.backup.."/hccos_v1.3.3.lua") then pcall(fs.move, state.backup.."/hccos_v1.3.3.lua", LEGACY) end
    if state.newSystem and fs.exists(SYSTEM_ROOT) then pcall(fs.delete, SYSTEM_ROOT) end
    if state.oldSystem and fs.exists(state.backup.."/system") then pcall(fs.move, state.backup.."/system", SYSTEM_ROOT) end
end

local function placeFiles(manifest)
    local state = {backup=backupPath(), oldSystem=false, newSystem=false, oldLegacy=false, newLegacy=false, oldStartup=false, newStartup=false}
    local ok, err = pcall(function()
        if fs.exists(SYSTEM_ROOT) then
            fs.move(SYSTEM_ROOT, state.backup.."/system")
            state.oldSystem = true
        end
        if fs.exists(LEGACY) then
            fs.move(LEGACY, state.backup.."/hccos_v1.3.3.lua")
            state.oldLegacy = true
        end
        fs.move(TEMP_SYSTEM, SYSTEM_ROOT)
        state.newSystem = true

        if not fs.exists(TEMP_LEGACY) then error("Compatibility file was not staged") end
        fs.move(TEMP_LEGACY, LEGACY)
        state.newLegacy = true

        -- startup.lua is deliberately the final placed file.
        if not fs.exists(TEMP_STARTUP) then error("startup.lua was not staged") end
        fs.move(TEMP_STARTUP, STARTUP)
        state.newStartup = true
    end)
    if not ok then
        restorePlacement(state)
        error(err)
    end
    return state
end

local function install()
    term.clear()
    term.setCursorPos(1, 1)
    print("HCC OS v1.4.0 Standalone Installer")
    print("GitHub: "..RAW_ROOT)
    print("User data is kept outside /.hccos/system.")
    print("")

    local manifestBody, manifestError = fetch(MANIFEST_URL)
    if not manifestBody then error("manifest.lua: "..tostring(manifestError)) end
    local manifest, parseError = parseManifest(manifestBody)
    if not manifest then error("manifest.lua: "..tostring(parseError)) end
    local entries = manifestEntries(manifest)
    print("Release: "..manifest.version.." / build "..tostring(manifest.build or "unknown"))

    for _, path in ipairs(DATA_DIRECTORIES) do makeDir(path) end
    if fs.exists(TEMP_ROOT) then fs.delete(TEMP_ROOT) end
    makeDir(TEMP_SYSTEM)
    local downloaded = fetchSystem(entries)
    local legacyName = manifest.legacy or "hccos_v1.3.3.lua"
    if not safeRelative(legacyName) then error("Unsafe compatibility path: "..tostring(legacyName)) end
    downloaded = downloaded + fetchExtra(legacyName, TEMP_LEGACY)
    downloaded = downloaded + fetchExtra("startup.lua", TEMP_STARTUP)
    -- Reserve space for the compatibility pack, startup and rollback copy.
    local expected = downloaded + 65536
    if not hasSpace(expected) then error("Not enough free space; existing system was not changed") end

    local state = placeFiles(manifest)
    if fs.exists(TEMP_ROOT) then fs.delete(TEMP_ROOT) end
    if not fs.exists(CONFIG_ROOT) then fs.makeDir(CONFIG_ROOT) end
    print("")
    print("Installation complete: HCC OS v"..manifest.version)
    print("Backup: "..state.backup)
    print("Reboot or run /startup.lua.")
end

local ok, err = pcall(install)
if not ok then
    if fs.exists(TEMP_ROOT) then pcall(fs.delete, TEMP_ROOT) end
    print("Installation failed: "..tostring(err))
    print("The existing system and user data were not removed.")
end
