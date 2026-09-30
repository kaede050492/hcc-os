local Bootstrap = {}

local function errorText(value)
    local text = tostring(value or "")
    if text == "" or text == "nil" then text = "Unknown boot failure" end
    return text
end

local function traceback(value, level)
    local text = errorText(value)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, result = pcall(debug.traceback, text, level or 2)
        if ok and type(result) == "string" and result ~= "" then return result end
    end
    return text
end

local function loadModule(path)
    local f, err = fs.open(path, "r")
    if not f then error(err or ("Missing module: "..path), 0) end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then error(loadError or ("Could not load module: "..path), 0) end
    local ok, value = xpcall(chunk, function(reason)
        return errorText(reason)
    end)
    if not ok then error(value, 0) end
    return value
end

local function runInternal(arguments)
    arguments = arguments or {}
    local base = "/.hccos/system/"
    local ModuleLoader = loadModule(base.."core/module_loader.lua")
    local moduleLoader = ModuleLoader.new({roots={base, base.."lib", "/.hccos/lib", "/lib"}})
    local function loadSystem(name) return moduleLoader:load(name) end
    local paths = loadSystem("core/paths")
    local Logger = loadSystem("core/logger")
    local Config = loadSystem("core/config")
    local HttpService = loadSystem("core/http_service")
    local Remote = loadSystem("core/remote")
    local Updater = loadSystem("core/updater")
    local AppRegistry = loadSystem("core/app_registry")
    local CapabilityRegistry = loadSystem("core/capabilities")
    local Performance = loadSystem("core/performance")
    local FileService = loadSystem("core/file_service")
    local Recovery = loadSystem("core/recovery")
    local Widgets = loadSystem("ui/widgets")
    local Icons = loadSystem("ui/icons")
    local Taskbar = loadSystem("ui/taskbar")
    local StartMenu = loadSystem("ui/start_menu")
    local Desktop = loadSystem("ui/desktop")
    local logger = Logger.new(paths, 400)
    local config = Config.new(paths, logger)
    config:ensureDirectories()
    config:load()
    local hadV133 = config.migrated or (not fs.exists(paths.versionFile) and
        (fs.exists(paths.legacySettings) or fs.exists(paths.currency)))
    if hadV133 then
        config.data.installMode = "UPGRADE_FROM_1_3_3"
        config.data.upgradeFrom = "1.3.3"
    elseif not config.data.upgradeFrom or config.data.upgradeFrom == "" then
        config.data.installMode = "CLEAN_INSTALL"
    end
    logger:info(config.data.installMode)
    if config.migrated then
        config:backupLegacyStartup()
        local saved, err = config:save()
        if not saved then logger:warn("Migrated settings were not saved: "..tostring(err)) end
    elseif config.recovered or not fs.exists(paths.settings) then
        local saved, err = config:save()
        if not saved then logger:warn("Recovered settings were not saved: "..tostring(err)) end
    end
    local interruptedUpdate=false
    for _,root in ipairs(paths.updateTemps or {paths.updateTemp}) do
        if fs.exists(root) then
            pcall(fs.delete, root)
            interruptedUpdate=true
        end
    end
    if interruptedUpdate then logger:info("Cleaned interrupted update temporary files") end

    local appRegistry = AppRegistry.new({root=paths.apps,logger=logger})
    local capabilities = CapabilityRegistry.new({api=peripheral,logger=logger})
    local performance = Performance.new({maxFps=config.data.fpsMax,minFps=config.data.fpsMin,adaptive=config.data.adaptiveFps})
    local fileService = FileService.new({fs=fs,paths=paths,logger=logger})
    local httpService = HttpService.new(http)
    local updater = Updater.new(paths, config, logger, Remote)
    updater.appRegistry=appRegistry
    local context = {
        paths=paths, config=config, logger=logger, remote=Remote, modules=moduleLoader,
        updater=updater, httpService=httpService, httpRequests=httpService.requests,
        appRegistry=appRegistry, capabilities=capabilities, performance=performance, fileService=fileService,
        localManifest=updater.localManifest,
        ui={widgets=Widgets, icons=Icons, taskbar=Taskbar, startMenu=StartMenu}
    }
    context.enterRecovery = function(reason)
        return Recovery.new(context):run(reason or "manual recovery request")
    end

    local api
    api = {
        version="1.5.1", build=1501, context=context,
        autoUpdatePending=config.data.autoUpdateCheck,
        attachApp=function(environment)
            api.appMark=environment.mark
            local entry=context.appRegistry:entry("updates")
            if not entry then context.appRegistry:scan(); entry=context.appRegistry:entry("updates") end
            if entry then
                local app=loadModule(entry.entryPath)
                if type(app) == "table" and type(app.attach) == "function" then app.attach(environment, api) end
            end
        end,
        check=function() return updater:check() end,
        beginCheck=function() return updater:beginAsyncCheck() end,
        beginAutoCheck=function() return updater:beginAsyncCheck() end,
        handleHttp=function(url, handleOrReason)
            local handled
            if type(handleOrReason) == "table" then handled=updater:handleHttpSuccess(url, handleOrReason)
            else handled=updater:handleHttpFailure(url, handleOrReason) end
            if handled and api.appMark then api.appMark(api.updateWindow) end
            return handled
        end,
        beginUpdate=function(manifest) return updater:begin(manifest) end,
        beginRepair=function(manifest) return updater:repair(manifest) end,
        stepUpdate=function() return updater:step() end,
        applyUpdate=function() return updater:apply() end,
        cancelUpdate=function() return updater:cleanup() end,
        rollback=function(version) return updater:rollback(version) end,
        resetSettings=function() return config:reset() end,
        bootLog=function() return logger:read() end
    }
    context.api = api

    if arguments[1] == "--recovery" then
        local action = Recovery.new(context):run("manual recovery request")
        if action ~= "start" then return action end
    end
    if config.data.autoUpdateCheck then
        logger:info("Automatic update check scheduled after desktop start")
        -- The modular desktop receives no blocking HTTP call here. The Update &
        -- Recovery app performs the optional check on its first service tick.
    end

    while true do
        local ok, started, result = xpcall(function()
            return Desktop.run(context, context.appRegistry)
        end, function(reason)
            return traceback(reason, 3)
        end)
        if ok and started ~= false then return started end
        local failure = errorText(ok and result or started)
        pcall(function() logger:error("Desktop start failed: "..failure) end)
        local action = Recovery.new(context):run(failure)
        if action ~= "start" then return action end
    end
end

function Bootstrap.run(arguments)
    local ok, result = xpcall(function()
        return runInternal(arguments)
    end, function(reason)
        return traceback(reason, 3)
    end)
    if not ok then error(errorText(result), 0) end
    return result
end

return Bootstrap
