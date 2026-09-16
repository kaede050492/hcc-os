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
    local Remote = loadSystem("core/remote")
    local Updater = loadSystem("core/updater")
    local Recovery = loadSystem("core/recovery")
    local Widgets = loadSystem("ui/widgets")
    local Icons = loadSystem("ui/icons")
    local Taskbar = loadSystem("ui/taskbar")
    local StartMenu = loadSystem("ui/start_menu")
    local Desktop = loadSystem("ui/desktop")
    local AppCatalog = loadSystem("apps/app_catalog")
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
    elseif not fs.exists(paths.settings) then
        config:save()
    end
    if fs.exists(paths.updateTemp) then
        pcall(fs.delete, paths.updateTemp)
        logger:info("Cleaned interrupted update temporary files")
    end

    local updater = Updater.new(paths, config, logger, Remote)
    local context = {
        paths=paths, config=config, logger=logger, remote=Remote, modules=moduleLoader,
        updater=updater, localManifest=updater.localManifest,
        ui={widgets=Widgets, icons=Icons, taskbar=Taskbar, startMenu=StartMenu}
    }
    context.enterRecovery = function(reason)
        return Recovery.new(context):run(reason or "manual recovery request")
    end

    _G.HCCV15 = {
        version="1.5.0", build=1500, context=context,
        autoUpdatePending=config.data.autoUpdateCheck,
        attachApp=function(environment)
            _G.HCCV15.appMark=environment.mark
            local app = loadSystem("apps/update_recovery")
            if type(app.attach) == "function" then app.attach(environment, _G.HCCV15) end
        end,
        check=function() return updater:check() end,
        beginCheck=function() return updater:beginAsyncCheck() end,
        beginAutoCheck=function() return updater:beginAsyncCheck() end,
        handleHttp=function(url, handleOrReason)
            local handled
            if type(handleOrReason) == "table" then handled=updater:handleHttpSuccess(url, handleOrReason)
            else handled=updater:handleHttpFailure(url, handleOrReason) end
            if handled and _G.HCCV15.appMark then _G.HCCV15.appMark(_G.HCCV15.updateWindow) end
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
    context.api = _G.HCCV15
    _G.HCCV14 = _G.HCCV15

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
        local ok, result = xpcall(function()
            return Desktop.run(context, AppCatalog)
        end, function(reason)
            return traceback(reason, 3)
        end)
        if ok then return result end
        local failure = errorText(result)
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
