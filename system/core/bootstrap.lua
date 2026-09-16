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
    local paths = loadModule(base.."core/paths.lua")
    local Logger = loadModule(base.."core/logger.lua")
    local Config = loadModule(base.."core/config.lua")
    local Remote = loadModule(base.."core/remote.lua")
    local Updater = loadModule(base.."core/updater.lua")
    local Recovery = loadModule(base.."core/recovery.lua")
    local Widgets = loadModule(base.."ui/widgets.lua")
    local Icons = loadModule(base.."ui/icons.lua")
    local Taskbar = loadModule(base.."ui/taskbar.lua")
    local StartMenu = loadModule(base.."ui/start_menu.lua")
    local Desktop = loadModule(base.."ui/desktop.lua")
    local AppCatalog = loadModule(base.."apps/app_catalog.lua")
    local logger = Logger.new(paths, 400)
    local config = Config.new(paths, logger)
    config:ensureDirectories()
    config:load()
    local hadV133 = config.migrated or (not fs.exists(paths.versionFile) and
        (fs.exists(paths.legacySettings) or fs.exists(paths.currency) or fs.exists(paths.legacy)))
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
        paths=paths, config=config, logger=logger, remote=Remote,
        updater=updater, localManifest=updater.localManifest,
        ui={widgets=Widgets, icons=Icons, taskbar=Taskbar, startMenu=StartMenu}
    }
    context.enterRecovery = function(reason)
        return Recovery.new(context):run(reason or "manual recovery request")
    end

    _G.HCCV14 = {
        version="1.4.0", build=1400, context=context,
        autoUpdatePending=config.data.autoUpdateCheck,
        attachApp=function(environment)
            _G.HCCV14.appMark=environment.mark
            local app = loadModule(base.."apps/update_recovery.lua")
            if type(app.attach) == "function" then app.attach(environment, _G.HCCV14) end
        end,
        check=function() return updater:check() end,
        beginAutoCheck=function() return updater:beginAsyncCheck() end,
        handleHttp=function(url, handleOrReason)
            local handled
            if type(handleOrReason) == "table" then handled=updater:handleHttpSuccess(url, handleOrReason)
            else handled=updater:handleHttpFailure(url, handleOrReason) end
            if handled and _G.HCCV14.appMark then _G.HCCV14.appMark(_G.HCCV14.updateWindow) end
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
    context.api = _G.HCCV14

    if arguments[1] == "--recovery" then
        return Recovery.new(context):run("manual recovery request")
    end
    if config.data.autoUpdateCheck then
        logger:info("Automatic update check scheduled after desktop start")
        -- The legacy desktop receives no blocking HTTP call here. The Update &
        -- Recovery app performs the optional check on its first service tick.
    end

    local ok, result = xpcall(function()
        return Desktop.run(context, AppCatalog)
    end, function(reason)
        return traceback(reason, 3)
    end)
    if not ok then
        local failure = errorText(result)
        pcall(function() logger:error("Desktop start failed: "..failure) end)
        return Recovery.new(context):run(failure)
    end
    return result
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
