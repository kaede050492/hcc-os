local Recovery = {}
Recovery.__index = Recovery

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

local function wrapText(value, width)
    value = reasonText(value):gsub("\r\n", "\n"):gsub("\r", "\n")
    width = math.max(10, math.floor(tonumber(width) or 80))
    local lines = {}
    for line in (value.."\n"):gmatch("([^\n]*)\n") do
        if line == "" then
            lines[#lines+1] = ""
        else
            while #line > width do
                lines[#lines+1] = line:sub(1, width)
                line = line:sub(width + 1)
            end
            lines[#lines+1] = line
        end
    end
    return lines
end

local function displayWidth()
    if type(term) == "table" and type(term.getSize) == "function" then
        local ok, width = pcall(term.getSize)
        if ok and type(width) == "number" then return width end
    end
    return 80
end

local function pause(recovery)
    print("")
    print("Press SPACE to continue.")
    while true do
        local event={os.pullEventRaw()}
        if event[1]=="terminate" then return false
        elseif event[1]=="key" and event[2]==keys.space then return true
        elseif event[1]=="http_success" or event[1]=="http_failure" then
            local _,err=recovery:handleHttpEvent(event)
            if err then recovery:message("HTTP response error: "..tostring(err)) end
        end
    end
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function loadModule(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, err end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then return nil, loadError end
    local ok, value = xpcall(chunk, function(reason)
        return traceback(reason)
    end)
    if not ok then return nil, value end
    return value
end

function Recovery.new(context)
    return setmetatable({context=context, selected=1, reason=reasonText(nil)}, Recovery)
end

function Recovery:message(value)
    value = reasonText(value)
    if self.context and self.context.logger then
        pcall(function() self.context.logger:info(value) end)
    end
    for _, line in ipairs(wrapText(value, displayWidth()-2)) do print(line) end
end

function Recovery:prepareTerminalInput()
    local registry=self.context and self.context.capabilities
    if type(registry)~="table" or type(registry.scan)~="function" then return end
    local ok,items=pcall(registry.scan,registry)
    if not ok or type(items)~="table" then
        if self.context.logger then
            pcall(self.context.logger.warn,self.context.logger,
                "Peripheral input scan failed in Recovery; use the computer keyboard")
        end
        return
    end
    for _,item in ipairs(items) do
        local handle=type(item)=="table" and item.handle or nil
        local isKeyboard=type(item)=="table" and type(item.capabilities)=="table" and item.capabilities.tom_keyboard
        if isKeyboard and type(handle)=="table" and type(handle.setFireNativeEvents)=="function" then
            local modeOk,modeError=pcall(handle.setFireNativeEvents,true)
            if not modeOk and self.context.logger then
                pcall(self.context.logger.warn,self.context.logger,
                    tostring(item.name).." terminal keyboard mode failed: "..tostring(modeError))
            end
        end
    end
end

local function closeResponse(handle)
    if type(handle)=="table" and type(handle.close)=="function" then pcall(handle.close) end
end

function Recovery:handleHttpEvent(event)
    if type(event)~="table" then return false end
    local dispatcher=self.context and self.context.httpDispatcher
    if type(dispatcher)=="function" then
        local called,handled,dispatchError=pcall(dispatcher,event)
        if not called then return true,tostring(handled) end
        if handled then return true,dispatchError end
    end
    local updater=self.context and self.context.updater
    if not updater then closeResponse(event[1]=="http_success" and event[3] or event[4]); return false end
    local called,handled
    if event[1]=="http_success" then
        called,handled=pcall(updater.handleHttpSuccess,updater,event[2],event[3])
        if not called or not handled then closeResponse(event[3]) end
    elseif event[1]=="http_failure" then
        called,handled=pcall(updater.handleHttpFailure,updater,event[2],event[3])
        closeResponse(event[4])
    else
        return false
    end
    if not called then return true,tostring(handled) end
    return true
end

function Recovery:downloadUpdate()
    local updater=self.context.updater
    local lastMessage=nil
    self:message("Press C to cancel; Ctrl+T to leave Recovery.")
    while updater.state.phase=="downloading" do
        local stepOk,stepResult,stepError=pcall(updater.step,updater)
        if not stepOk then
            pcall(updater.cleanup,updater)
            return false,"Update failed: "..tostring(stepResult)
        end
        if stepResult==false then return false,tostring(stepError or updater.state.message or "Update failed") end
        if updater.state.message~=lastMessage then
            lastMessage=updater.state.message
            self:message(lastMessage)
        end
        if updater.state.phase=="failed" then return false,tostring(updater.state.message or "Update failed") end
        if updater.state.phase=="downloading" and updater.downloadJob then
            local event={os.pullEventRaw()}
            if event[1]=="terminate" or (event[1]=="key" and event[2]==keys.c) then
                pcall(updater.cleanup,updater)
                return false,event[1]=="terminate" and "Update cancelled with Ctrl+T" or "Update cancelled"
            elseif event[1]=="http_success" or event[1]=="http_failure" then
                local _,dispatchError=self:handleHttpEvent(event)
                if dispatchError then
                    pcall(updater.cleanup,updater)
                    return false,"Update response failed: "..tostring(dispatchError)
                end
            end
        end
    end
    return updater.state.phase=="ready",tostring(updater.state.message or updater.state.phase)
end

function Recovery:checkRemoteManifest()
    local updater=self.context.updater
    local url=updater.remote.manifestUrl(updater.config.data)
    while self.context.httpRequests and self.context.httpRequests[url] do
        self:message("Waiting for the previous manifest request to finish. Press C to cancel.")
        local event={os.pullEventRaw()}
        if event[1]=="terminate" or (event[1]=="key" and event[2]==keys.c) then
            return nil,event[1]=="terminate" and "Update check cancelled with Ctrl+T" or "Update check cancelled"
        elseif event[1]=="http_success" or event[1]=="http_failure" then
            local _,dispatchError=self:handleHttpEvent(event)
            if dispatchError then return nil,"Previous HTTP request failed: "..tostring(dispatchError) end
        end
    end
    local started,startError=updater:beginAsyncCheck()
    if not started then return nil,tostring(startError or "Update check could not start") end
    self:message("Checking remote manifest. Press C to cancel.")
    while updater.checkJob do
        local event={os.pullEventRaw()}
        if event[1]=="terminate" or (event[1]=="key" and event[2]==keys.c) then
            pcall(updater.cleanup,updater)
            return nil,event[1]=="terminate" and "Update check cancelled with Ctrl+T" or "Update check cancelled"
        elseif event[1]=="http_success" or event[1]=="http_failure" then
            local _,dispatchError=self:handleHttpEvent(event)
            if dispatchError then
                pcall(updater.cleanup,updater)
                return nil,"Update check failed: "..tostring(dispatchError)
            end
        end
    end
    if updater.lastCheck then return updater.lastCheck end
    return nil,tostring(updater.state and updater.state.message or "Update check failed")
end

function Recovery:clearPendingUpdate()
    local updater=self.context and self.context.updater
    if not updater then return true end
    local state=updater.state or {}
    if updater.checkJob or updater.downloadJob or state.phase=="downloading" or state.phase=="ready" then
        local ok,err=pcall(updater.cleanup,updater)
        if not ok then return false,tostring(err) end
        state=updater.state or {}
        if state.phase=="failed" then return false,tostring(state.message or "Update cleanup failed") end
    end
    return true
end

function Recovery:repair()
    local cleared,clearError=self:clearPendingUpdate()
    if not cleared then self:message("Could not reset the update service: "..tostring(clearError)); return end
    local result, err = self:checkRemoteManifest()
    if not result then self:message("Repair unavailable: "..tostring(err)); return end
    if not self.context.updater:repair(result.manifest) then self:message("No repair files could be prepared"); return end
    local downloaded,downloadError=self:downloadUpdate()
    if not downloaded then self:message("Repair download failed: "..tostring(downloadError)); return end
    local ok, applyError = self.context.updater:apply()
    self:message(ok and "Repair complete. Restart HCC OS." or ("Repair failed: "..tostring(applyError)))
end

function Recovery:reinstall()
    local cleared,clearError=self:clearPendingUpdate()
    if not cleared then self:message("Could not reset the update service: "..tostring(clearError)); return end
    local result, err = self:checkRemoteManifest()
    if not result then self:message("Reinstall unavailable: "..tostring(err)); return end
    if not self.context.updater:begin(result.manifest) then self:message("Reinstall could not start"); return end
    local downloaded,downloadError=self:downloadUpdate()
    if not downloaded then self:message("Reinstall download failed: "..tostring(downloadError)); return end
    local ok, applyError = self.context.updater:apply()
    self:message(ok and "Reinstall complete. Restart HCC OS." or ("Reinstall failed: "..tostring(applyError)))
end

function Recovery:resetSettings()
    local ok, err = self.context.config:reset()
    self:message(ok and "Settings reset. User files were kept." or ("Reset failed: "..tostring(err)))
end

local function runPastebinPut(path)
    if type(shell)~="table" or type(shell.run)~="function" then return false,"CC:T pastebin program is unavailable" end
    local output={}
    local runOk,runResult
    local current
    if type(term)=="table" and type(term.current)=="function" then current=term.current() end
    if current and type(window)=="table" and type(window.create)=="function" and type(term.redirect)=="function" then
        local captured=window.create(current,1,1,displayWidth(),8,false)
        local redirected,previous=pcall(term.redirect,captured)
        if redirected then
            runOk,runResult=pcall(shell.run,"pastebin","put",path)
            pcall(term.redirect,previous or current)
            for line=1,8 do
                local lineOk,value=pcall(captured.getLine,line)
                if lineOk and type(value)=="string" and trim(value)~="" then output[#output+1]=trim(value) end
            end
        end
    end
    if not runOk then runOk,runResult=pcall(shell.run,"pastebin","put",path) end
    if not runOk then return false,"pastebin command failed: "..tostring(runResult) end
    local text=table.concat(output,"\n")
    if runResult==false then return false,text~="" and text or "pastebin put failed" end
    local pasteUrl=text:match("https?://pastebin%.com/[A-Za-z0-9]+")
    return true,pasteUrl,text
end

function Recovery:uploadLogFile(path,label)
    if type(path)~="string" or path=="" or not fs.exists(path) or fs.isDir(path) then
        self:message(label.." is empty. Nothing to upload.")
        return
    end
    local file,readError=fs.open(path,"r")
    if not file then self:message("Upload failed: "..tostring(readError)); return end
    local readOk,content=pcall(file.readAll); pcall(file.close)
    if not readOk or type(content)~="string" or trim(content)=="" then
        self:message(label.." is empty. Nothing to upload.")
        return
    end
    self:message("Uploading "..label.." with pastebin put...")
    local uploaded,pasteUrl,output=runPastebinPut(path)
    if not uploaded then
        pcall(function() self.context.logger:warn(label.." upload failed: "..tostring(pasteUrl)) end)
        self:message("Upload failed: "..tostring(pasteUrl))
        if output and output~="" then self:message(output) end
        return
    end
    if pasteUrl then
        pcall(function() self.context.logger:info(label.." uploaded: "..pasteUrl) end)
        self:message(label.." uploaded with pastebin put (link-only; expires according to Pastebin).")
        self:message(pasteUrl)
    else
        self:message(label.." upload finished. Pastebin output:")
        if output and output~="" then self:message(output) end
    end
end

function Recovery:uploadBootLog()
    local path=self.context.logger and self.context.logger.path or "/.hccos/logs/boot.log"
    self:uploadLogFile(path,"Boot Log")
end

function Recovery:uploadImageDiagnostics()
    local root=self.context.paths.logs or "/.hccos/logs"
    self:uploadLogFile(fs.combine(root,"image-diagnostics.log"),"Image Diagnostics")
end

function Recovery:run(reason)
    self.reason = reasonText(reason)
    self:prepareTerminalInput()
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("HCC OS v1.5.1 - Recovery Mode")
        print("Reason:")
        for _, line in ipairs(wrapText(self.reason, displayWidth()-4)) do
            print("  "..line)
        end
        print("")
        local options = {
            "Start HCC OS", "Rollback", "Repair", "Reset Settings",
            "Boot Log", "Reinstall", "CC:T Shell", "Upload Boot Log", "Upload Image Diagnostics"
        }
        for i, label in ipairs(options) do print((i == self.selected and "> " or "  ")..i..". "..label) end
        print("")
        print("Use UP/DOWN and ENTER. Cancel update with C.")
        local event, key
        repeat
            local raw={os.pullEventRaw()}; event,key=raw[1],raw[2]
            if event=="http_success" or event=="http_failure" then
                local _,httpError=self:handleHttpEvent(raw)
                if httpError then self:message("HTTP response error: "..tostring(httpError)) end
                event=nil
            end
        until event=="key" or event=="terminate"
        if event=="terminate" then return "terminate" end
        if event == "key" then
            if key == keys.up then self.selected = (self.selected-2)%#options+1
            elseif key == keys.down then self.selected = self.selected%#options+1
            elseif key == keys.enter then
                if self.selected == 1 then return "start"
                elseif self.selected == 2 then
                    local ok, err = self.context.updater:rollback(); self:message(ok and "Rollback complete. Restart HCC OS." or tostring(err)); if not pause(self) then return "terminate" end
                elseif self.selected == 3 then self:repair(); if not pause(self) then return "terminate" end
                elseif self.selected == 4 then self:resetSettings(); if not pause(self) then return "terminate" end
                elseif self.selected == 5 then print(self.context.logger:read()); if not pause(self) then return "terminate" end
                elseif self.selected == 6 then self:reinstall(); if not pause(self) then return "terminate" end
                elseif self.selected == 7 then
                    local shellOk,shellError=pcall(function()
                        if type(shell)~="table" or type(shell.run)~="function" then error("CraftOS shell is unavailable") end
                        return shell.run("/rom/programs/shell")
                    end)
                    if not shellOk then self:message("CraftOS shell could not start: "..tostring(shellError)) end
                    if not pause(self) then return "terminate" end
                elseif self.selected == 8 then self:uploadBootLog(); if not pause(self) then return "terminate" end
                elseif self.selected == 9 then self:uploadImageDiagnostics(); if not pause(self) then return "terminate" end end
            elseif key == keys.escape then return "start" end
        end
    end
end

function Recovery.runStandalone(reason)
    local ok, result = xpcall(function()
        local base = "/.hccos/system/core/"
        local paths, pathsError = loadModule(base.."paths.lua")
        if not paths then error("Recovery module paths.lua: "..reasonText(pathsError), 0) end
        local Logger, loggerError = loadModule(base.."logger.lua")
        if not Logger then error("Recovery module logger.lua: "..reasonText(loggerError), 0) end
        local Config, configError = loadModule(base.."config.lua")
        if not Config then error("Recovery module config.lua: "..reasonText(configError), 0) end
        local Remote, remoteError = loadModule(base.."remote.lua")
        if not Remote then error("Recovery module remote.lua: "..reasonText(remoteError), 0) end
        local Updater, updaterError = loadModule(base.."updater.lua")
        if not Updater then error("Recovery module updater.lua: "..reasonText(updaterError), 0) end
        local CapabilityRegistry = loadModule(base.."capabilities.lua")
        local logger = Logger.new(paths, 400)
        local config = Config.new(paths, logger); config:ensureDirectories(); config:load()
        local updater = Updater.new(paths, config, logger, Remote)
        local context={paths=paths, logger=logger, config=config, updater=updater}
        if type(CapabilityRegistry)=="table" and type(CapabilityRegistry.new)=="function" then
            local registryOk,registry=pcall(CapabilityRegistry.new,{api=peripheral,logger=logger})
            if registryOk then context.capabilities=registry
            else logger:warn("Recovery input capability setup failed: "..tostring(registry)) end
        end
        return Recovery.new(context):run(reason)
    end, function(value)
        return traceback(value)
    end)
    if not ok then return nil, reasonText(result) end
    return result
end

return Recovery
