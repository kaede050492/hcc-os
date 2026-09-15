-- HCC OS v1.4.0 minimal root boot loader.
-- The HCC OS implementation remains under /.hccos/system/.

local entrypoint = "/.hccos/system/core/bootstrap.lua"

local function loadFile(path)
    local file, err = fs.open(path, "r")
    if not file then error(err or ("Missing file: " .. path), 0) end
    local source = file.readAll()
    file.close()
    local chunk, loadError = load(source, "@" .. path, "t", _ENV)
    if not chunk then error(loadError, 0) end
    return chunk
end

if not fs.exists(entrypoint) then
    print("[HCC OS] HCC OS v1.4 core entrypoint is missing:")
    print(entrypoint)
    print("Run the standalone installer.lua to install or repair HCC OS.")
    return
end

local ok, err = pcall(function()
    local bootstrap = loadFile(entrypoint)()
    if type(bootstrap) ~= "table" or type(bootstrap.run) ~= "function" then
        error("Invalid HCC OS bootstrap entrypoint", 0)
    end
    bootstrap.run()
end)

if not ok then
    print("[HCC OS] Boot failure: " .. tostring(err))
    local recovery = "/.hccos/system/core/recovery.lua"
    if fs.exists(recovery) then
        local recoveryChunk = loadFile(recovery)
        pcall(function()
            local recoveryApp = recoveryChunk()
            if type(recoveryApp) == "table" and type(recoveryApp.runStandalone) == "function" then
                recoveryApp.runStandalone(tostring(err))
            end
        end)
    else
        print("Run the standalone installer.lua to repair HCC OS.")
    end
end
