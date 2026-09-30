-- Adaptive render budget controller. Event dispatch remains independent from
-- this target: it only controls when a dirty frame is requested.
local Performance = {}
Performance.__index = Performance

local STEPS = { 60, 45, 30, 20, 15, 10 }
local TIMER_TICK_SECONDS = 0.05
local TIMER_TICK_FPS = 1 / TIMER_TICK_SECONDS

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < 1e9
end

local function supported(value, fallback)
    value = tonumber(value) or fallback
    value = math.max(10, math.min(60, math.floor(value)))
    for _, step in ipairs(STEPS) do
        if step <= value then return step end
    end
    return 10
end

local function makeTargets(maximum, minimum)
    local targets = {}
    for _, step in ipairs(STEPS) do
        if step <= maximum and step >= minimum then targets[#targets + 1] = step end
    end
    if #targets == 0 then targets[1] = maximum end
    return targets
end

local function normaliseLimits(maximum, minimum)
    local requestedMaximum = supported(maximum, 60)
    local requestedMinimum = supported(minimum, 10)
    if requestedMinimum > requestedMaximum then requestedMinimum = requestedMaximum end
    local effectiveMaximum = math.min(requestedMaximum, TIMER_TICK_FPS)
    local effectiveMinimum = math.min(requestedMinimum, effectiveMaximum)
    return requestedMaximum, requestedMinimum, effectiveMaximum, effectiveMinimum
end

function Performance.new(options)
    options = options or {}
    local requestedMaximum, requestedMinimum, maximum, minimum =
        normaliseLimits(options.maxFps, options.minFps)
    return setmetatable({
        targets = makeTargets(maximum, minimum),
        configuredMaximum = requestedMaximum,
        configuredMinimum = requestedMinimum,
        targetIndex = 1,
        adaptive = options.adaptive ~= false,
        actualFps = 0,
        frameTimeMs = 0,
        averageFrameTimeMs = 0,
        droppedFrameCount = 0,
        frameCount = 0,
        windowFrames = 0,
        windowStartedAt = nil,
        overloadFrames = 0,
        underBudgetSince = nil,
        lastChangeAt = 0,
        tickRemainder = 0
    }, Performance)
end

function Performance:getTargetFps()
    return self.targets[self.targetIndex]
end

function Performance:getConfiguredMaxFps() return self.configuredMaximum end
function Performance:getConfiguredMinFps() return self.configuredMinimum end
function Performance:getTimerCeilingFps() return TIMER_TICK_FPS end

-- CC:T timers resolve to 50 ms world ticks. Distribute fractional tick
-- intervals so targets such as 15 FPS do not get rounded down to 10 FPS.
function Performance:nextFrameDelay()
    local fps = math.min(self:getTargetFps(), TIMER_TICK_FPS)
    self.tickRemainder = self.tickRemainder + TIMER_TICK_FPS / fps
    local ticks = math.floor(self.tickRemainder + 1e-9)
    self.tickRemainder = self.tickRemainder - ticks
    return math.max(1, ticks) * TIMER_TICK_SECONDS
end

function Performance:getActualFps()
    return self.actualFps
end

function Performance:getFrameTimeMs()
    return self.frameTimeMs
end

function Performance:getAverageFrameTimeMs()
    return self.averageFrameTimeMs
end

-- Image sampling is a real quality tier: lower render targets use fewer source
-- samples and larger fills instead of reporting a visual downgrade only.
function Performance:getQualityLevel()
    local target = self:getTargetFps()
    if target <= 10 then return 2 end
    if target <= 15 then return 1 end
    return 0
end

function Performance:getImageSampleStep()
    local level = self:getQualityLevel()
    return level == 2 and 4 or (level == 1 and 2 or 1)
end

function Performance:getDroppedFrameCount()
    return self.droppedFrameCount
end

function Performance:isDegraded()
    return self:getQualityLevel() > 0
end

function Performance:setAdaptive(enabled)
    self.adaptive = enabled == true
    self.overloadFrames = 0
    self.underBudgetSince = nil
end

function Performance:setLimits(maximum, minimum)
    local requestedMaximum, requestedMinimum, effectiveMaximum, effectiveMinimum =
        normaliseLimits(maximum, minimum)
    local current = self:getTargetFps()
    self.targets = makeTargets(effectiveMaximum, effectiveMinimum)
    self.configuredMaximum = requestedMaximum
    self.configuredMinimum = requestedMinimum
    self.targetIndex = 1
    for index, target in ipairs(self.targets) do
        if target == current then self.targetIndex = index; break end
    end
    self.overloadFrames = 0
    self.underBudgetSince = nil
    self.tickRemainder = 0
    return self:getTargetFps()
end

function Performance:recordFrame(durationMs, nowSeconds)
    if not finite(durationMs) or durationMs < 0 then return end
    local now = finite(nowSeconds) and nowSeconds or 0
    local target = self:getTargetFps()
    local budget = 1000 / target
    self.frameTimeMs = durationMs
    if self.frameCount == 0 then self.averageFrameTimeMs = durationMs
    else self.averageFrameTimeMs = self.averageFrameTimeMs * 0.8 + durationMs * 0.2 end
    self.frameCount = self.frameCount + 1
    self.windowFrames = self.windowFrames + 1
    if not self.windowStartedAt then self.windowStartedAt = now end
    local elapsed = now - self.windowStartedAt
    if elapsed >= 1 then
        self.actualFps = self.windowFrames / elapsed
        self.windowFrames = 0
        self.windowStartedAt = now
    end

    local missed = math.max(0, math.floor(durationMs / budget) - 1)
    self.droppedFrameCount = self.droppedFrameCount + missed
    if not self.adaptive or #self.targets < 2 then return end

    if self.averageFrameTimeMs > budget * 1.1 then
        self.overloadFrames = self.overloadFrames + 1
        self.underBudgetSince = nil
        if self.overloadFrames >= 3 and self.targetIndex < #self.targets then
            self.targetIndex = self.targetIndex + 1
            self.overloadFrames = 0
            self.lastChangeAt = now
            self.tickRemainder = 0
        end
    else
        self.overloadFrames = 0
        if self.averageFrameTimeMs < budget * 0.55 then
            self.underBudgetSince = self.underBudgetSince or now
            if now - self.underBudgetSince >= 8 and self.targetIndex > 1 and now - self.lastChangeAt >= 8 then
                self.targetIndex = self.targetIndex - 1
                self.underBudgetSince = now
                self.lastChangeAt = now
                self.tickRemainder = 0
            end
        else
            self.underBudgetSince = nil
        end
    end
end

return { new = function(options) return Performance.new(options) end }
