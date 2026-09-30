-- HCC OS v1.5 simple update center.
-- The app deliberately exposes one safe next action at a time so a user does
-- not have to understand the updater's internal transaction states.
local UpdateRecovery = {}

local function button(ui, app, canvas, x, y, width, label, action, enabled)
    enabled = enabled ~= false
    local wrapped = function()
        if enabled then
            action()
        else
            app.status = "Please finish the current step first"
            if app.win and ui and type(ui.mark) == "function" then ui.mark(app.win) end
        end
    end
    if ui and type(ui.button) == "function" then
        ui.button(app, canvas, x, y, width, label, wrapped)
        return
    end
    local palette = ui and type(ui.palette) == "function" and ui.palette() or {}
    canvas:filledRectangle(x, y, width, 16, enabled and palette.panelBackground or palette.windowBackground)
    canvas:rectangle(x, y, width, 16, enabled and palette.border or palette.grid)
    canvas:text(x+4, y+3, label, enabled and palette.textPrimary or palette.textSecondary)
    app.win.buttons[#app.win.buttons+1] = {x=x, y=y, w=width, h=16, action=wrapped}
end

local function mark(self)
    local ui = self.context and self.context.ui
    if self.win and ui and type(ui.mark) == "function" then ui.mark(self.win) end
end

function UpdateRecovery:state()
    local updater = self.context and self.context.updater
    if not updater then return {phase="offline", message="Update service unavailable", completed=0, total=0} end
    return updater:status()
end

function UpdateRecovery:setStatus(message, error)
    self.status = tostring(message or "")
    self.error = error and tostring(error) or nil
    mark(self)
end

function UpdateRecovery:init()
    local updater = self.context and self.context.updater
    if not updater then
        self:setStatus("Update service unavailable", true)
        return
    end
    self.result = updater.lastCheck
    self.error = nil
    local pending = self.context.takeAutoUpdatePending and self.context.takeAutoUpdatePending()
    self.status = pending and "Checking for updates..." or "Ready to check"
    if pending then
        local ok, err = updater:beginAsyncCheck()
        if not ok then self:setStatus("Could not start update check", err) end
    end
end

function UpdateRecovery:interval()
    local phase = self:state().phase
    if phase == "downloading" or phase == "check_wait" then return 0.05 end
    return 2
end

function UpdateRecovery:check()
    local phase = self:state().phase
    if phase == "check_wait" then
        self:setStatus("A check is already in progress")
        return
    end
    if phase == "downloading" or phase == "ready" then
        self:setStatus("Finish or cancel the current update first", true)
        return
    end
    self.result = nil
    self.error = nil
    self.status = "Checking for updates..."
    local updater = self.context and self.context.updater
    if not updater then self:setStatus("Update service unavailable", true); return end
    local ok, err = updater:beginAsyncCheck()
    if not ok then self:setStatus("Could not start update check", err) end
    mark(self)
end

function UpdateRecovery:download()
    local state = self:state()
    if state.phase ~= "available" and state.phase ~= "refresh_available" then
        self:setStatus("Check for an update before downloading", true)
        return
    end
    if not self.result or not self.result.manifest then
        self:setStatus("The update manifest is missing; check again", true)
        return
    end
    local updater = self.context and self.context.updater
    if not updater then self:setStatus("Update service unavailable", true); return end
    local ok, err = updater:begin(self.result.manifest)
    if ok then self:setStatus("Downloading update...") else self:setStatus("Download could not start", err) end
end

function UpdateRecovery:apply()
    if self:state().phase ~= "ready" then
        self:setStatus("Download the update before installing", true)
        return
    end
    local updater = self.context and self.context.updater
    if not updater then self:setStatus("Update service unavailable", true); return end
    local ok, err = updater:apply()
    if ok then self:setStatus("Update installed. Restart HCC OS to finish.")
    else self:setStatus("Install failed", err) end
end

function UpdateRecovery:cancel()
    local phase = self:state().phase
    if phase ~= "downloading" and phase ~= "check_wait" then
        self:setStatus("There is no update in progress")
        return
    end
    local updater = self.context and self.context.updater
    if not updater then self:setStatus("Update service unavailable", true); return end
    updater:cleanup()
    self:setStatus("Cancelled. Your current system is unchanged.")
end

function UpdateRecovery:openRecovery()
    local ui = self.context and self.context.ui
    if ui and type(ui.requestRecovery)=="function" then
        ui.requestRecovery()
    else
        self:setStatus("Recovery service unavailable", true)
    end
end

function UpdateRecovery:primaryAction()
    local phase = self:state().phase
    if phase == "available" or phase == "refresh_available" then self:download()
    elseif phase == "ready" then self:apply()
    else self:check() end
end

function UpdateRecovery:update()
    local state = self:state()
    local updater = self.context and self.context.updater
    if state.phase == "check_wait" then
        self.status = "Checking for updates..."
    elseif state.phase == "available" or state.phase == "refresh_available" or state.phase == "current" then
        self.result = updater and updater.lastCheck or self.result
        self.status = state.message
        self.error = nil
    elseif state.phase == "offline" then
        self.status = "Could not check for updates"
        self.error = state.message
    elseif state.phase == "downloading" then
        local ok, err
        if updater then ok, err = updater:step() else ok, err = false, state.message end
        local after = self:state()
        if ok == false then
            self.status = "Download failed"
            self.error = err or after.message
        elseif after.phase == "ready" then
            self.status = "Download complete. Install when ready."
            self.error = nil
        else
            self.status = after.message or "Downloading update..."
        end
    elseif state.phase == "ready" then
        self.status = "Download complete. Install when ready."
    elseif state.phase == "applied" then
        self.status = "Update installed. Restart HCC OS to finish."
    elseif state.phase == "blocked" or state.phase == "failed" then
        self.status = state.message or "Update failed"
        self.error = state.message
    end
    mark(self)
end

function UpdateRecovery:onKey(key)
    if key == keys.f5 then self:check()
    elseif key == keys.d then self:download()
    elseif key == keys.a then self:apply()
    elseif key == keys.c then self:cancel()
    elseif key == keys.enter then self:openRecovery() end
    mark(self)
end

local function percent(state)
    if state.phase == "ready" or state.phase == "applied" then return 100 end
    if not state.total or state.total <= 0 then return 0 end
    return math.max(0, math.min(100, math.floor(100*(state.completed or 0)/state.total+0.5)))
end

local function phaseTitle(state, result)
    local titles={
        idle="Ready to update", check_wait="Checking for updates", checking="Checking for updates",
        available="Update available", refresh_available="Repair update available", current="Your system is up to date",
        downloading="Downloading update", ready="Ready to install", applied="Restart required",
        offline="Update check unavailable", blocked="Update blocked", failed="Update failed"
    }
    if state.phase == "current" and result and result.downgradeBlocked then return "Update blocked" end
    return titles[state.phase] or "Update center"
end

function UpdateRecovery:draw(canvas)
    local env = self.context and self.context.ui or {}
    local palette = type(env.palette) == "function" and env.palette() or {}
    local state = self:state()
    local updater = self.context and self.context.updater
    local result = self.result or (updater and updater.lastCheck)
    local localVersion = result and result.localVersion or "unknown"
    local remoteVersion = result and result.remoteVersion or "not checked"
    local progress = percent(state)
    local active = state.phase == "downloading" or state.phase == "check_wait"
    local primary = (state.phase == "available" or state.phase == "refresh_available") and "DOWNLOAD"
        or (state.phase == "ready" and "INSTALL" or "CHECK NOW")

    if canvas.h < 180 or canvas.w < 430 then
        canvas:text(8, 4, "HCC OS UPDATE", palette.accent)
        canvas:clipping(8, 17, canvas.w-16, 10):text(0, 0, phaseTitle(state, result), self.error and palette.error or palette.textPrimary)
        canvas:clipping(8, 29, canvas.w-16, 10):text(0, 0, self.error or self.status or state.message, self.error and palette.error or palette.textSecondary)
        canvas:text(8, 42, string.format("PROGRESS %d%%", progress), palette.textPrimary)
        canvas:filledRectangle(8, 54, canvas.w-16, 7, palette.inputBackground or palette.windowBackground)
        canvas:rectangle(8, 54, canvas.w-16, 7, palette.border)
        if progress > 0 then canvas:filledRectangle(10, 56, math.floor((canvas.w-20)*progress/100), 3, palette.accent) end

        local gap, x = 3, 8
        local available = math.max(1, canvas.w-16-gap*3)
        local widths = {math.floor(available*0.36), math.floor(available*0.17), math.floor(available*0.18)}
        widths[4] = available-widths[1]-widths[2]-widths[3]
        local labels={primary,"CHECK","CANCEL","RECOVERY"}
        if widths[2]<24 then labels={"GO","C","X","R"}
        elseif widths[2]<40 then labels={"GO","CHK","X","REC"}
        else labels={widths[1]>=68 and primary or "GO","CHECK",widths[3]>=52 and "CANCEL" or "X",widths[4]>=72 and "RECOVERY" or "REC"} end
        local y = canvas.h-22
        button(env, self, canvas, x, y, widths[1], labels[1], function() self:primaryAction() end, not active); x=x+widths[1]+gap
        button(env, self, canvas, x, y, widths[2], labels[2], function() self:check() end, not active and state.phase ~= "ready"); x=x+widths[2]+gap
        button(env, self, canvas, x, y, widths[3], labels[3], function() self:cancel() end, active); x=x+widths[3]+gap
        button(env, self, canvas, x, y, widths[4], labels[4], function() self:openRecovery() end, not active)
        return
    end

    canvas:text(8, 6, "HCC OS UPDATE", palette.accent)
    canvas:text(8, 19, "Keep your system safe and up to date", palette.textSecondary)
    canvas:filledRectangle(8, 34, canvas.w-16, 48, palette.panelBackground)
    canvas:rectangle(8, 34, canvas.w-16, 48, palette.border)
    canvas:text(16, 41, phaseTitle(state, result), self.error and palette.error or palette.textPrimary)
    canvas:clipping(16, 54, canvas.w-32, 10):text(0, 0, self.error or self.status or state.message, self.error and palette.error or palette.textSecondary)
    canvas:text(16, 68, "CURRENT "..tostring(localVersion).."   AVAILABLE "..tostring(remoteVersion), palette.textSecondary)

    canvas:text(8, 91, string.format("PROGRESS  %d%%", progress), palette.textPrimary)
    canvas:filledRectangle(8, 104, canvas.w-16, 13, palette.inputBackground or palette.windowBackground)
    canvas:rectangle(8, 104, canvas.w-16, 13, palette.border)
    if progress > 0 then canvas:filledRectangle(10, 106, math.floor((canvas.w-20)*progress/100), 9, palette.accent) end
    local currentFile = tostring(state.current or "")
    local totalFiles = tonumber(state.total) or 0
    local completedFiles = tonumber(state.completed) or 0
    local fileText = currentFile ~= "" and ("FILE: "..currentFile) or (totalFiles > 0 and string.format("FILES: %d/%d", completedFiles, totalFiles) or "No download in progress")
    canvas:clipping(8, 122, canvas.w-16, 10):text(0, 0, fileText, palette.textSecondary)

    button(env, self, canvas, 8, 145, 140, primary, function() self:primaryAction() end, not active)
    button(env, self, canvas, 156, 145, 78, "CHECK", function() self:check() end, not active and state.phase ~= "ready")
    button(env, self, canvas, 242, 145, 78, "CANCEL", function() self:cancel() end, active)
    button(env, self, canvas, 328, 145, 92, "RECOVERY", function() self:openRecovery() end, not active)
    canvas:text(8, canvas.h-13, "F5 check  D download  A install  C cancel  ENTER recovery", palette.textSecondary)
end

function UpdateRecovery.attach(environment)
    environment.register("updates", "System Update", "UP", 448, 230, UpdateRecovery)
end

return UpdateRecovery
