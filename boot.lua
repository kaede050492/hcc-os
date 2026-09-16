-- HCC OS v1.5.0 boot entry.
-- This file is intentionally small; all policy lives in system/core.

local core = "/.hccos/system/core/bootstrap.lua"

local function loadFile(path)
    local f, err = fs.open(path, "r")
    if not f then error(err or ("Missing file: "..path)) end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then error(loadError) end
    return chunk
end

local function copyTree(source, destination)
    if fs.isDir(source) then
        if not fs.exists(destination) then fs.makeDir(destination) end
        for _, name in ipairs(fs.list(source)) do copyTree(fs.combine(source, name), fs.combine(destination, name)) end
    elseif not fs.exists(destination) then
        local parent = fs.getDir(destination)
        if not fs.exists(parent) then fs.makeDir(parent) end
        fs.copy(source, destination)
    end
end

if not fs.exists(core) and fs.exists("/hcc_os/system") then
    copyTree("/hcc_os/system", "/.hccos/system")
end

if not fs.exists(core) then
    print("[HCC OS] Core files are not installed.")
    print("Run /hcc_os/installer.lua from CraftOS.")
    return
end

local arguments={...}
local ok, err = pcall(function()
    local bootstrap = loadFile(core)()
    bootstrap.run(arguments)
end)

if not ok then
    print("[HCC OS] Recovery required: "..tostring(err))
    local recovery = "/.hccos/system/core/recovery.lua"
    if fs.exists(recovery) then
        local recoveryChunk = loadFile(recovery)
        pcall(function() recoveryChunk().runStandalone(tostring(err)) end)
    else
        print("Run /hcc_os/installer.lua or restore /.hccos/backups manually.")
    end
end
