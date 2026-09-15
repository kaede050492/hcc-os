-- HCC OS v1.4.0 installer.
-- Run from CraftOS with: /hcc_os/installer.lua
-- The installer never writes user data directories.

local root = "/hcc_os"
local system = "/.hccos/system"
local backup = "/.hccos/backups/installer"

local function loadFile(path)
    local f, err = fs.open(path, "r")
    if not f then error(err or ("Missing installer module: "..path)) end
    local source = f.readAll(); f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then error(loadError) end
    return chunk()
end

local function copyPackageFile(relative)
    local source = fs.combine(root.."/system", relative)
    local destination = fs.combine(system, relative)
    if not fs.exists(source) then return false end
    local parent = fs.getDir(destination)
    if not fs.exists(parent) then fs.makeDir(parent) end
    fs.copy(source, destination)
    return true
end

local function localManifest()
    local f = fs.open(root.."/manifest.lua", "r")
    if not f then return nil end
    local source = f.readAll(); f.close()
    local chunk = load(source, "@"..root.."/manifest.lua", "t", _ENV)
    return chunk and chunk()
end

local function installLocal(manifest)
    if not manifest or type(manifest.files) ~= "table" then return false end
    if not fs.exists("/.hccos") then fs.makeDir("/.hccos") end
    if not fs.exists(system) then fs.makeDir(system) end
    for _, relative in ipairs(manifest.files) do
        if not copyPackageFile(relative) then return false end
    end
    return true
end

local function backupStartup()
    if not fs.exists("/startup.lua") then return end
    if not fs.exists("/.hccos/backups") then fs.makeDir("/.hccos/backups") end
    if not fs.exists(backup) then fs.makeDir(backup) end
    if not fs.exists(backup.."/startup.lua") then fs.copy("/startup.lua", backup.."/startup.lua") end
end

local function installStartup()
    local source = root.."/startup.lua"
    if fs.exists(source) then
        if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
        fs.copy(source, "/startup.lua")
        return true
    end
    return false
end

local function installLegacyCompatibility(remote, manifest)
    if fs.exists("/hccos_v1.3.3.lua") then return true end
    local localCopy = root.."/legacy/hccos_v1.3.3.lua"
    if fs.exists(localCopy) then fs.copy(localCopy, "/hccos_v1.3.3.lua"); return true end
    if not remote then return false end
    local source, fetchError = remote.fetch(remote.rootFileUrl(manifest and manifest.legacy or "hccos_v1.3.3.lua", {updateRepository=remote.repository}))
    if not source or #source < 1024 then return false, fetchError end
    local f = fs.open("/hccos_v1.3.3.lua", "w")
    if not f then return false end
    f.write(source); f.close(); return true
end

term.clear()
term.setCursorPos(1, 1)
print("HCC OS v1.4.0 Installer")
print("User files, images, currency, notes and downloads are preserved.")
print("")

local ok, err = pcall(function()
    backupStartup()
    local remote = fs.exists(root.."/system/core/remote.lua") and loadFile(root.."/system/core/remote.lua") or nil
    local manifest = localManifest()
    if not installLocal(manifest) then
        print("Local package incomplete; downloading the release manifest...")
        local paths = loadFile(root.."/system/core/paths.lua")
        local Logger = loadFile(root.."/system/core/logger.lua")
        local Config = loadFile(root.."/system/core/config.lua")
        local Remote = loadFile(root.."/system/core/remote.lua")
        local Updater = loadFile(root.."/system/core/updater.lua")
        local logger = Logger.new(paths, 400)
        local config = Config.new(paths, logger); config:ensureDirectories(); config:load()
        local updater = Updater.new(paths, config, logger, Remote)
        local result, checkError = updater:check()
        if not result then error(checkError) end
        local started, startError = updater:begin(result.manifest)
        if not started then error(startError) end
        while updater.state.phase == "downloading" do
            local stepOk, stepError = updater:step()
            if stepOk == false then error(stepError) end
            print(string.format("%d/%d %s", updater.state.completed, updater.state.total, updater.state.current or ""))
        end
        local applied, applyError = updater:apply()
        if not applied then error(applyError) end
    end
    installStartup()
    if not installLegacyCompatibility(remote, manifest) then error("v1.3.3 compatibility application pack is unavailable") end
    if not fs.exists("/.hccos/config") then fs.makeDir("/.hccos/config") end
    print("Installation complete. Reboot or run /hcc_os/boot.lua.")
end)

if not ok then
    print("Installation failed: "..tostring(err))
    print("The existing system and user data were not removed.")
end
