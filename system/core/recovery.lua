local Recovery = {}
Recovery.__index = Recovery

local function pause()
    print("")
    print("Press any key to continue.")
    os.pullEventRaw("key")
end

local function loadModule(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, err end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then return nil, loadError end
    local ok, value = pcall(chunk)
    if not ok then return nil, value end
    return value
end

function Recovery.new(context)
    return setmetatable({context=context, selected=1, reason=nil}, Recovery)
end

function Recovery:message(value)
    self.context.logger:info(value)
    print(value)
end

function Recovery:repair()
    local result, err = self.context.updater:check()
    if not result then self:message("Repair unavailable: "..tostring(err)); return end
    if not self.context.updater:repair(result.manifest) then self:message("No repair files could be prepared"); return end
    while self.context.updater.state.phase == "downloading" do
        local ok, stepError = self.context.updater:step()
        if ok == false then self:message("Repair download failed: "..tostring(stepError)); return end
    end
    local ok, applyError = self.context.updater:apply()
    self:message(ok and "Repair complete. Restart HCC OS." or ("Repair failed: "..tostring(applyError)))
end

function Recovery:reinstall()
    local result, err = self.context.updater:check()
    if not result then self:message("Reinstall unavailable: "..tostring(err)); return end
    if not self.context.updater:begin(result.manifest) then self:message("Reinstall could not start"); return end
    while self.context.updater.state.phase == "downloading" do
        local ok, stepError = self.context.updater:step()
        if ok == false then self:message("Reinstall download failed: "..tostring(stepError)); return end
    end
    local ok, applyError = self.context.updater:apply()
    self:message(ok and "Reinstall complete. Restart HCC OS." or ("Reinstall failed: "..tostring(applyError)))
end

function Recovery:resetSettings()
    local ok, err = self.context.config:reset()
    self:message(ok and "Settings reset. User files were kept." or ("Reset failed: "..tostring(err)))
end

function Recovery:run(reason)
    self.reason = reason
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("HCC OS v1.4.0 - Recovery Mode")
        print("Reason: "..tostring(self.reason or "manual recovery"))
        print("")
        local options = {
            "Start HCC OS", "Rollback", "Repair", "Reset Settings",
            "Boot Log", "Reinstall", "CC:T Shell"
        }
        for i, label in ipairs(options) do print((i == self.selected and "> " or "  ")..i..". "..label) end
        print("")
        print("Use UP/DOWN and ENTER. Cancel update with C.")
        local event, key = os.pullEventRaw("key")
        if event == "key" then
            if key == keys.up then self.selected = (self.selected-2)%#options+1
            elseif key == keys.down then self.selected = self.selected%#options+1
            elseif key == keys.enter then
                if self.selected == 1 then return "start"
                elseif self.selected == 2 then
                    local ok, err = self.context.updater:rollback(); self:message(ok and "Rollback complete. Restart HCC OS." or tostring(err)); pause()
                elseif self.selected == 3 then self:repair(); pause()
                elseif self.selected == 4 then self:resetSettings(); pause()
                elseif self.selected == 5 then print(self.context.logger:read()); pause()
                elseif self.selected == 6 then self:reinstall(); pause()
                elseif self.selected == 7 then shell.run("/rom/programs/shell"); pause() end
            elseif key == keys.escape then return "start" end
        end
    end
end

function Recovery.runStandalone(reason)
    local base = "/.hccos/system/core/"
    local paths = loadModule(base.."paths.lua")
    local Logger = loadModule(base.."logger.lua")
    local Config = loadModule(base.."config.lua")
    local Remote = loadModule(base.."remote.lua")
    local Updater = loadModule(base.."updater.lua")
    if not (paths and Logger and Config and Remote and Updater) then
        print("Recovery modules are incomplete. Run /hcc_os/installer.lua.")
        return
    end
    local logger = Logger.new(paths, 400)
    local config = Config.new(paths, logger); config:ensureDirectories(); config:load()
    local updater = Updater.new(paths, config, logger, Remote)
    return Recovery.new({paths=paths, logger=logger, config=config, updater=updater}):run(reason)
end

return Recovery
