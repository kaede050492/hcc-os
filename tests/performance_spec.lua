-- Run with Lua 5.2+ from the repository root:
--   lua tests/performance_spec.lua

local moduleChunk,moduleError=loadfile("system/core/performance.lua")
assert(moduleChunk,moduleError)
local Performance=moduleChunk()
local perf=Performance.new({maxFps=60,minFps=10,adaptive=true})
assert(perf:getConfiguredMaxFps()==60 and perf:getConfiguredMinFps()==10 and
    perf:getTimerCeilingFps()==20 and perf:getTargetFps()==20,
    "configured fps limits should be preserved while the timer ceiling is explicit")

local fifteen=Performance.new({maxFps=15,minFps=15,adaptive=false})
local delays={fifteen:nextFrameDelay(),fifteen:nextFrameDelay(),fifteen:nextFrameDelay()}
assert(math.abs(delays[1]+delays[2]+delays[3]-0.2)<1e-9 and
    delays[1]==0.05 and delays[2]==0.05 and delays[3]==0.1,
    "fractional CC:T timer ticks should average to the requested 15 FPS")
local ten=Performance.new({maxFps=10,minFps=10,adaptive=false})
assert(ten:nextFrameDelay()==0.1,"10 FPS should use a two-tick interval")

perf:recordFrame(120,1)
perf:recordFrame(120,2)
assert(perf:getTargetFps()==20,"one or two overloaded frames should not change quality")
perf:recordFrame(120,3)
assert(perf:getTargetFps()==15 and perf:getQualityLevel()==1 and
    perf:getImageSampleStep()==2 and perf:isDegraded(),
    "sustained overload should lower fps and select the matching image quality tier")
perf:recordFrame(120,4)
perf:recordFrame(120,5)
perf:recordFrame(120,6)
assert(perf:getTargetFps()==10 and perf:getQualityLevel()==2 and
    perf:getImageSampleStep()==4,"continued overload should reach the lowest quality tier")
assert(perf:getDroppedFrameCount()>0,"slow frames should be reflected in dropped-frame metrics")

local fixed=Performance.new({maxFps=30,minFps=15,adaptive=false})
fixed:recordFrame(200,1); fixed:recordFrame(200,2); fixed:recordFrame(200,3)
assert(fixed:getTargetFps()==20,"disabled adaptation should hold the current target")

local metrics=Performance.new({maxFps=20,minFps=20,adaptive=false})
metrics:recordFrame(8,0)
metrics:recordFrame(12,1)
assert(metrics:getActualFps()==2 and metrics:getFrameTimeMs()==12 and
    metrics:getAverageFrameTimeMs()==8.8,
    "frame timing and one-second actual fps should use completed frame samples")
local frames=metrics.frameCount
metrics:recordFrame(-1,2); metrics:recordFrame(0/0,2); metrics:recordFrame(math.huge,2)
assert(metrics.frameCount==frames,"negative and non-finite frame durations should be ignored")

local constrained=Performance.new({maxFps=15,minFps=60,adaptive=true})
assert(constrained:getConfiguredMinFps()==15 and constrained:getTargetFps()==15,
    "inverted configured limits should normalize without exceeding the timer ceiling")
assert(constrained:setLimits(60,10)==15 and constrained:getConfiguredMaxFps()==60,
    "changing limits should retain the current feasible target where possible")

print("performance controller specs passed")
