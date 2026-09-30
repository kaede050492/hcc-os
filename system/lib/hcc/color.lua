-- Small, deterministic color operations used by the opaque Mica surface theme.
local Color = {}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function unsignedColor(value)
    if not finite(value) or value ~= math.floor(value) then return nil end
    -- Lua 5.3 runtimes may represent 0xAARRGGBB literals as signed 32-bit
    -- integers. Normalize those bit patterns while keeping Lua 5.2 numbers.
    if value < 0 and value >= -2147483648 then value=value+4294967296 end
    if value < 0 or value > 4294967295 then return nil end
    return value
end

function Color.isColor(value) return unsignedColor(value) ~= nil end

local function channel(color, divisor)
    return math.floor(color/divisor)%256
end

function Color.sample(data, columns, rows)
    if type(data) ~= "table" or type(data.pixels) ~= "table" then return nil end
    local width,height=tonumber(data.width),tonumber(data.height)
    if not finite(width) or not finite(height) or width<1 or height<1 or
        width~=math.floor(width) or height~=math.floor(height) or width*height>4194304 then
        return nil
    end
    columns=tonumber(columns); if not finite(columns) then columns=8 end
    rows=tonumber(rows); if not finite(rows) then rows=6 end
    columns=math.max(1,math.min(32,math.floor(columns)))
    rows=math.max(1,math.min(32,math.floor(rows)))
    local red,green,blue,weight=0,0,0,0
    for row=0,rows-1 do
        local y=math.max(1,math.min(height,math.floor((row+0.5)*height/rows)+1))
        for columnIndex=0,columns-1 do
            local x=math.max(1,math.min(width,math.floor((columnIndex+0.5)*width/columns)+1))
            local pixel=data.pixels[(y-1)*width+x]
            pixel=unsignedColor(pixel)
            if pixel then
                local alpha=channel(pixel,16777216)
                if alpha>0 then
                    red=red+channel(pixel,65536)*alpha
                    green=green+channel(pixel,256)*alpha
                    blue=blue+(pixel%256)*alpha
                    weight=weight+alpha
                end
            end
        end
    end
    if weight==0 then return nil end
    red=math.floor(red/weight+0.5); green=math.floor(green/weight+0.5); blue=math.floor(blue/weight+0.5)
    return (0xFF000000+red*65536+green*256+blue)%4294967296
end

function Color.blend(base,tint,amount,maxChannelShift)
    local originalBase=base
    base,tint=unsignedColor(base),unsignedColor(tint)
    if base==nil or tint==nil then return originalBase end
    amount=tonumber(amount)
    if not finite(amount) then amount=0 end
    amount=math.max(0,math.min(1,amount))
    maxChannelShift=tonumber(maxChannelShift)
    if not finite(maxChannelShift) then maxChannelShift=255 end
    maxChannelShift=math.max(0,math.min(255,maxChannelShift))
    if amount==0 or maxChannelShift==0 then return originalBase end
    local function mix(divisor)
        local original=channel(base,divisor)
        local target=channel(tint,divisor)
        local value=original+(target-original)*amount
        value=math.max(original-maxChannelShift,math.min(original+maxChannelShift,value))
        return math.floor(value+0.5)
    end
    return (0xFF000000+mix(65536)*65536+mix(256)*256+mix(1))%4294967296
end

return Color
