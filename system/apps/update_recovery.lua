local UpdateRecovery = {}

local function button(env, app, canvas, x, y, width, label, action)
    if env.button then
        env.button(app, canvas, x, y, width, label, action)
        return
    end
    canvas:rectangle(x, y, width, 16, env.palette.accent)
    canvas:text(x+4, y+3, label, env.palette.textPrimary)
    app.win.buttons[#app.win.buttons+1] = {x=x, y=y, w=width, h=16, action=action}
end

function UpdateRecovery:init()
    self.env = self.env or UpdateRecovery.environment
    self.api = UpdateRecovery.api or self.env.HCCV14
    self.api.updateWindow = self.win
    self.status = self.api.autoUpdatePending and "Automatic check pending" or "Ready"
    self.result = nil
    self.error = nil
    if self.api.autoUpdatePending then
        local ok, err = self.api.beginAutoCheck()
        self.api.autoUpdatePending = false
        if not ok then self.status = "Automatic check unavailable: "..tostring(err) end
    end
end

function UpdateRecovery:interval()
    local phase = self.api.context.updater.state.phase
    return phase == "downloading" and 0.05 or 5
end

function UpdateRecovery:check()
    self.error = nil
    local result, err = self.api.check()
    self.result = result
    self.error = err
    if result then
        self.status = result.available and "Update available" or (result.refreshAvailable and "Same version - refresh available" or (result.downgradeBlocked and "Remote revision is older; downgrade blocked" or "Already up to date"))
    else self.status = "Offline: "..tostring(err) end
    self.api.autoUpdatePending = false
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:download(refresh)
    if not self.result or (not self.result.available and not (refresh and self.result.refreshAvailable)) then return end
    local ok, err = self.api.beginUpdate(self.result.manifest)
    self.status = ok and "Downloading..." or "Download refused: "..tostring(err)
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:refresh()
    self:download(true)
end

function UpdateRecovery:apply()
    local ok, err = self.api.applyUpdate()
    self.status = ok and "Applied. Restart HCC OS." or "Apply failed: "..tostring(err)
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:cancel()
    self.api.cancelUpdate()
    self.status = "Update cancelled; current system unchanged"
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:rollback()
    local ok, err = self.api.rollback()
    self.status = ok and "Rollback complete. Restart HCC OS." or "Rollback failed: "..tostring(err)
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:openRecovery()
    shell.run("/startup.lua", "--recovery")
end

function UpdateRecovery:update()
    local state = self.api.context.updater:status()
    if state.phase == "available" or state.phase == "refresh_available" or state.phase == "current" then
        if not self.result then self.result = self.api.context.updater.lastCheck end
        self.status = state.message
    end
    if state.phase == "downloading" then
        local ok, err = self.api.stepUpdate()
        if ok == false then self.status = "Download failed: "..tostring(err)
        elseif self.api.context.updater.state.phase == "ready" then self.status = "Download complete; press APPLY" end
        if self.win then self.env.mark(self.win) end
    end
end

function UpdateRecovery:onKey(key)
    if key == keys.f5 then self:check()
    elseif key == keys.d then self:download()
    elseif key == keys.f then self:refresh()
    elseif key == keys.a then self:apply()
    elseif key == keys.c then self:cancel()
    elseif key == keys.r then self:rollback()
    elseif key == keys.enter then self:openRecovery() end
    if self.win then self.env.mark(self.win) end
end

function UpdateRecovery:draw(canvas)
    local env = self.env
    canvas:text(7, 6, "UPDATE & RECOVERY", env.palette.accent)
    canvas:text(7, 20, "GitHub manifest / transactional system updates", env.palette.textSecondary)
    local localRevision=self.result and self.result.localRevision or ""
    local remoteRevision=self.result and self.result.remoteRevision or ""
    canvas:text(7, 38, "LOCAL: "..tostring(self.result and self.result.localVersion or "1.4.0")..(localRevision~="" and " ("..localRevision..")" or ""), env.palette.textPrimary)
    canvas:text(7, 51, "REMOTE: "..tostring(self.result and self.result.remoteVersion or "not checked")..(remoteRevision~="" and " ("..remoteRevision..")" or ""), env.palette.textPrimary)
    canvas:text(7, 66, "STATUS: "..tostring(self.status), self.error and env.palette.error or env.palette.textSecondary)
    local state = self.api.context.updater:status()
    if state.total and state.total > 0 then
        local percent = math.floor(100*(state.completed or 0)/state.total+0.5)
        canvas:text(7, 81, string.format("FILE: %s  %d/%d  %d%%", state.current or "", state.completed or 0, state.total, percent), env.palette.textSecondary)
        canvas:filledRectangle(7, 95, math.max(20, canvas.w-14), 6, env.palette.panelBackground)
        canvas:filledRectangle(8, 96, math.max(0, (canvas.w-16)*(state.completed or 0)/state.total), 4, env.palette.accent)
    end
    button(env, self, canvas, 7, 112, 72, "F5 CHECK", function() self:check() end)
    button(env, self, canvas, 84, 112, 72, "DOWNLOAD", function() self:download() end)
    button(env, self, canvas, 161, 112, 62, "APPLY", function() self:apply() end)
    button(env, self, canvas, 228, 112, 60, "CANCEL", function() self:cancel() end)
    button(env, self, canvas, 293, 112, 76, "REFRESH", function() self:refresh() end)
    button(env, self, canvas, 7, 132, 72, "ROLLBACK", function() self:rollback() end)
    button(env, self, canvas, 84, 132, 82, "RECOVERY", function() self:openRecovery() end)
    canvas:text(7, canvas.h-17, "F5 check  D download  F refresh  A apply  R rollback", env.palette.textSecondary)
end

function UpdateRecovery.attach(environment, api)
    UpdateRecovery.environment = environment
    UpdateRecovery.api = api
    environment.register("updates", "Update & Recovery", "UP", 430, 190, UpdateRecovery)
end

return UpdateRecovery
