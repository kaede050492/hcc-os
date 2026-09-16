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

local function pause()
    print("")
    print("Press SPACE to continue.")
    local event, key
    repeat event,key=os.pullEventRaw() until event=="terminate" or (event=="key" and key==keys.space)
    return event~="terminate"
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
        repeat event,key=os.pullEventRaw() until event=="key" or event=="terminate"
        if event=="terminate" then return "terminate" end
        if event == "key" then
            if key == keys.up then self.selected = (self.selected-2)%#options+1
            elseif key == keys.down then self.selected = self.selected%#options+1
            elseif key == keys.enter then
                if self.selected == 1 then return "start"
                elseif self.selected == 2 then
                    local ok, err = self.context.updater:rollback(); self:message(ok and "Rollback complete. Restart HCC OS." or tostring(err)); if not pause() then return "terminate" end
                elseif self.selected == 3 then self:repair(); if not pause() then return "terminate" end
                elseif self.selected == 4 then self:resetSettings(); if not pause() then return "terminate" end
                elseif self.selected == 5 then print(self.context.logger:read()); if not pause() then return "terminate" end
                elseif self.selected == 6 then self:reinstall(); if not pause() then return "terminate" end
                elseif self.selected == 7 then shell.run("/rom/programs/shell"); if not pause() then return "terminate" end
                elseif self.selected == 8 then self:uploadBootLog(); if not pause() then return "terminate" end
                elseif self.selected == 9 then self:uploadImageDiagnostics(); if not pause() then return "terminate" end end
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
        local logger = Logger.new(paths, 400)
        local config = Config.new(paths, logger); config:ensureDirectories(); config:load()
        local updater = Updater.new(paths, config, logger, Remote)
        return Recovery.new({paths=paths, logger=logger, config=config, updater=updater}):run(reason)
    end, function(value)
        return traceback(value)
    end)
    if not ok then return nil, reasonText(result) end
    return result
end

return Recovery
