-- HCC OS v1.5 Tom's Peripherals GPU adapter.
-- No UI module should need to know which peripheral name was selected.

local TomGpu = {}

local REQUIRED={"getSize","refreshSize","setSize","filledRectangle","line","drawText","getTextLength","sync","fill"}
local function hasMethods(value,names)
    if not value then return false end
    for _,name in ipairs(names) do if type(value[name])~="function" then return false end end
    return true
end

function TomGpu.isGpu(value)
    return hasMethods(value,REQUIRED)
end

function TomGpu.capabilities(value)
    local result={nativePng=false,font=false}
    if value then
        result.nativePng=type(value.newBuffer)=="function" and type(value.decodeImage)=="function" and type(value.drawImage)=="function"
        result.font=type(value.setFont)=="function"
    end
    return result
end

function TomGpu.find(preferred)
    if type(peripheral)~="table" or type(peripheral.getNames)~="function" then return nil,"peripheral API unavailable" end
    local ok,names=pcall(peripheral.getNames)
    if not ok or type(names)~="table" then return nil,"could not enumerate peripherals" end
    table.sort(names)
    local first
    for _,name in ipairs(names) do
        local wrapped=peripheral.wrap(name)
        if wrapped and TomGpu.isGpu(wrapped) then
            local item={name=name,device=wrapped,capabilities=TomGpu.capabilities(wrapped)}
            if preferred and preferred~="" and name==preferred then return item end
            first=first or item
        end
    end
    return first, first and nil or "Tom's GPU not found"
end

return TomGpu
