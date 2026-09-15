local Bootstrap = {}

local function loadModule(path)
    local f, err = fs.open(path, "r")
    if not f then error(err or ("Missing module: "..path)) end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then error(loadError) end
    local ok, value = pcall(chunk)
    if not ok then error(value) end
    return value
end

function Bootstrap.run(arguments)
    arguments = arguments or {}
    local base = "/.hccos/system/"
    local paths = loadModule(base.."core/paths.lua")
    local Logger = loadModule(base.."core/logger.lua")
    local Config = loadModule(base.."core/config.lua")
    local Remote = loadModule(base.."core/remote.lua")
    local Updater = loadModule(base.."core/updater.lua")
    local Setup = loadModule(base.."core/setup.lua")
    local Recovery = loadModule(base.."core/recovery.lua")
    local Bridge = loadModule(base.."core/legacy_bridge.lua")
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
        updater=updater, localManifest=updater.localManifest
    }

    _G.HCCV14 = {
        version="1.4.0", build=1400, context=context,
        autoUpdatePending=config.data.autoUpdateCheck,
        attachLegacy=function(environment)
            _G.HCCV14.legacyMark=environment.mark
            local app = loadModule(base.."apps/update_recovery.lua")
            if type(app.attach) == "function" then app.attach(environment, _G.HCCV14) end
        end,
        check=function() return updater:check() end,
        beginAutoCheck=function() return updater:beginAsyncCheck() end,
        handleHttp=function(url, handleOrReason)
            local handled
            if type(handleOrReason) == "table" then handled=updater:handleHttpSuccess(url, handleOrReason)
            else handled=updater:handleHttpFailure(url, handleOrReason) end
            if handled and _G.HCCV14.legacyMark then _G.HCCV14.legacyMark(_G.HCCV14.legacyUpdateWindow) end
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

    if arguments[1] == "--recovery" then
        return Recovery.new(context):run("manual recovery request")
    end
    if config:isFirstBoot() then Setup.run(config, Remote, logger) end

    if config.data.autoUpdateCheck then
        logger:info("Automatic update check scheduled after desktop start")
        -- The legacy desktop receives no blocking HTTP call here. The Update &
        -- Recovery app performs the optional check on its first service tick.
    end

    local ok, err = Bridge.run(paths, logger)
    if not ok then
        logger:error("Desktop start failed: "..tostring(err))
        return Recovery.new(context):run(tostring(err))
    end
    return "stopped"
end

return Bootstrap
