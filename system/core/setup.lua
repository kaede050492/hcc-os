local Setup = {}

local function input(prompt, fallback)
    if fallback and fallback ~= "" then
        write(prompt.." ["..fallback.."]: ")
    else
        write(prompt..": ")
    end
    local value = read()
    return value == "" and (fallback or "") or value
end

local function detectHardware()
    local result = {gpus={}, keyboards=0, mice=0, monitors=0, width=nil, height=nil, pixelsPerBlock=64}
    if type(peripheral) ~= "table" or type(peripheral.getNames) ~= "function" then return result end
    local ok, names = pcall(peripheral.getNames)
    if not ok or type(names) ~= "table" then return result end
    for _, name in ipairs(names) do
        local wrapOk, device = pcall(peripheral.wrap, name)
        if wrapOk and device then
            if type(device.getSize) == "function" and type(device.sync) == "function" and type(device.drawText) == "function" then
                result.gpus[#result.gpus+1] = name
                local sizeOk, width, height = pcall(device.getSize)
                if sizeOk and width and height and not result.width then result.width, result.height = width, height end
            end
            local kindOk, kind = pcall(peripheral.getType, name)
            kind = kindOk and tostring(kind):lower() or ""
            if kind:find("keyboard", 1, true) then result.keyboards = result.keyboards + 1 end
            if kind:find("mouse", 1, true) then result.mice = result.mice + 1 end
            if kind:find("monitor", 1, true) then result.monitors = result.monitors + 1 end
        end
    end
    return result
end

local function httpState(remote, config)
    if type(http) ~= "table" or type(http.get) ~= "function" then return "HTTP API unavailable" end
    local manifest, err = remote.fetchManifest(config)
    return manifest and ("GitHub manifest reachable (build "..tostring(manifest.build or "?")..")") or ("Manifest unavailable: "..tostring(err))
end

function Setup.run(config, remote, logger)
    term.clear()
    term.setCursorPos(1, 1)
    print("HCC OS v1.4.0 Setup")
    print("Welcome to HCC OS. Existing user files are kept.")
    print("")
    local hardware = detectHardware()
    print("Tom's GPU: "..(#hardware.gpus > 0 and "detected" or "not detected"))
    print("Display: "..(hardware.width and (tostring(hardware.width).."x"..tostring(hardware.height)) or "unavailable"))
    print("Monitors: "..tostring(hardware.monitors).."  Pixels/block: "..tostring(hardware.pixelsPerBlock))
    print("Keyboard: "..tostring(hardware.keyboards > 0 and "connected" or "CraftOS keyboard"))
    print("Mouse: "..tostring(hardware.mice > 0 and "connected" or "not detected"))
    print("HTTP/GitHub: "..httpState(remote, config.data))
    print("")
    config.data.computerLabel = input("Computer Label", config.data.computerLabel)
    local theme = input("Theme (black/midnight)", config.data.theme)
    config.data.theme = theme == "midnight" and "midnight" or "black"
    config.data.accent = input("Accent", config.data.accent)
    config.data.wallpaperMode = input("Wallpaper (black/center/fit/fill/stretch/tile)", config.data.wallpaperMode)
    if not ({black=true,center=true,fit=true,fill=true,stretch=true,tile=true})[config.data.wallpaperMode] then config.data.wallpaperMode = "black" end
    config.data.updateChannel = input("Update Channel (stable/beta)", config.data.updateChannel)
    config.data.updateChannel = config.data.updateChannel == "beta" and "beta" or "stable"
    local automatic = input("Check for updates after boot? (yes/no)", config.data.autoUpdateCheck and "yes" or "no")
    config.data.autoUpdateCheck = automatic:lower() == "yes"
    if #hardware.gpus > 0 and config.data.gpuName == "" then config.data.gpuName = hardware.gpus[1] end
    local saved, err = config:completeFirstBoot()
    if not saved then logger:error("Setup settings could not be saved: "..tostring(err)) end
    print("")
    print(saved and "Setup complete. Starting HCC OS..." or "Setup completed in memory; settings could not be saved.")
    sleep(0.5)
    return saved
end

return Setup
