-- HCC OS v1.4.0 minimal root boot loader.
-- The HCC OS implementation remains under /.hccos/system/.

local entrypoint = "/.hccos/system/core/bootstrap.lua"
local bootLog = "/.hccos/logs/boot.log"
local arguments = {...}

local function reasonText(value)
    local text = tostring(value or "")
    if text == "" or text == "nil" then return "Unknown boot failure" end
    return text
end

local function traceback(value)
    local text = reasonText(value)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, result = pcall(debug.traceback, text, 2)
        if ok and type(result) == "string" and result ~= "" then return result end
    end
    return text
end

local function saveBootLog(value)
    local text = reasonText(value):gsub("\r\n", "\n"):gsub("\r", "\n")
    pcall(function()
        local directory = "/.hccos/logs"
        if not fs.exists(directory) then fs.makeDir(directory) end
        local lines = {}
        if fs.exists(bootLog) then
            local old = fs.open(bootLog, "r")
            if old then
                local content = old.readAll() or ""
                old.close()
                for line in (content.."\n"):gmatch("([^\n]*)\n") do
                    if line ~= "" then lines[#lines+1] = line end
                end
            end
        end
        for line in ("[ERROR] Boot failure: "..text.."\n"):gmatch("([^\n]*)\n") do
            lines[#lines+1] = line
        end
        while #lines > 400 do table.remove(lines, 1) end
        local file = fs.open(bootLog, "w")
        if not file then return end
        pcall(file.write, table.concat(lines, "\n").."\n")
        pcall(file.close)
    end)
end

local function printWrapped(value, width)
    value = reasonText(value):gsub("\r\n", "\n"):gsub("\r", "\n")
    width = math.max(10, math.floor(tonumber(width) or 80))
    for line in (value.."\n"):gmatch("([^\n]*)\n") do
        if line == "" then
            print("")
        else
            while #line > width do
                print(line:sub(1, width))
                line = line:sub(width + 1)
            end
            print(line)
        end
    end
end

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

local ok, err = xpcall(function()
    local bootstrap = loadFile(entrypoint)()
    if type(bootstrap) ~= "table" or type(bootstrap.run) ~= "function" then
        error("Invalid HCC OS bootstrap entrypoint", 0)
    end
    bootstrap.run(arguments)
end, function(reason)
    return traceback(reason)
end)

if not ok then
    local reason = reasonText(err)
    saveBootLog(reason)
    print("[HCC OS] Boot failure:")
    printWrapped(reason, 78)
    local recovery = "/.hccos/system/core/recovery.lua"
    if fs.exists(recovery) then
        local recoveryOk, recoveryError = xpcall(function()
            local recoveryChunk = loadFile(recovery)
            local recoveryApp = recoveryChunk()
            if type(recoveryApp) ~= "table" or type(recoveryApp.runStandalone) ~= "function" then
                error("Invalid Recovery entrypoint", 0)
            end
            local result, startError = recoveryApp.runStandalone(reason)
            if startError then error(startError, 0) end
            return result
        end, function(value)
            return traceback(value)
        end)
        if not recoveryOk then
            local failure = "Recovery start failed: "..reasonText(recoveryError)
            saveBootLog(failure)
            printWrapped(failure, 78)
        end
    else
        print("Run the standalone installer.lua to repair HCC OS.")
    end
end
