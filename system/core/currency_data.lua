return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local dataPaths=E.context and E.context.paths or {}
local currencyPath=dataPaths.currency or "/.hccos/currency"
local currencyBackupPath=dataPaths.currencyBackup or "/.hccos/currency.bak"
local currencyCsvPath="/.hccos/currency.csv"
local fileStorage=E.context and E.context.fileService
local MAX_CURRENCY_BYTES=1048576
local MAX_CURRENCY_ITEMS=5000
local MAX_CURRENCY_COINS=128
local MAX_CURRENCY_RECENT=12
local MAX_SAFE_INTEGER=9007199254740991
local CURRENCY_SCALE=1000000 -- fixed-point micro units, never Lua floats
local currencyWarning
local currencyData
local currencyDefaults={version=1,baseCoin="",allowDecimals=false,rounding="floor",
    coins={},items={},recent={}}
local function currencyCopy(t)
    local r={}; for k,v in pairs(t) do r[k]=v end; return r
end
local function currencyRead(path)
    if not fileStorage then error("Safe file storage is unavailable") end
    local data,err=fileStorage:readText(path,MAX_CURRENCY_BYTES)
    if not data then error(err or "Cannot read currency data") end
    local good,value=pcall(textutils.unserialize,data or "")
    if not good or type(value)~="table" then error("Currency data is invalid") end
    return value,data
end
local function currencyValidName(s)
    return type(s)=="string" and #s>=1 and #s<=48 and not s:find("[%z\001-\031\127]")
end
local function currencyFixed(text,allowFraction)
    if type(text)=="number" then text=tostring(text) end
    if type(text)~="string" then return nil end
    text=text:gsub(",",""):gsub("%s+","")
    if text=="" or text:sub(1,1)=="-" or text:sub(1,1)=="+" then return nil end
    if not text:match("^%d*%.?%d*$") or text=="." then return nil end
    local whole,frac=text:match("^(%d*)%.?(%d*)$")
    whole=whole=="" and "0" or whole
    if #whole>12 then return nil end
    frac=frac or ""
    if not allowFraction and frac:gsub("0","")~="" then return nil end
    if #frac>6 then return nil end
    frac=(frac.."000000"):sub(1,6)
    local n=tonumber(whole)*CURRENCY_SCALE+tonumber(frac)
    if not finite(n) or n<0 or n>9000000000000000 then return nil end
    return floor(n)
end
local function currencyInteger(text)
    if type(text)=="number" then text=tostring(text) end
    if type(text)~="string" then return nil end
    text=text:gsub(",",""):gsub("%s+","")
    if not text:match("^%d+$") or #text>12 then return nil end
    local n=tonumber(text); if not finite(n) or n<0 or n>900000000000 then return nil end
    return floor(n)
end
local function currencyMultiply(left,right)
    if type(left)~="number" or type(right)~="number" or left~=left or right~=right then return nil end
    local a,b=math.abs(left),math.abs(right)
    if a==math.huge or b==math.huge then return nil end
    if a>0 and b>MAX_SAFE_INTEGER/a then return nil end
    local product=left*right
    if product~=floor(product) then return nil end
    return product
end
local function currencyFormat(value,allowDecimals)
    if type(value)~="number" or value~=value or math.abs(value)>MAX_SAFE_INTEGER then return "-" end
    local negative=value<0
    value=floor(math.abs(value)+0.5)
    local whole=floor(value/CURRENCY_SCALE); local rem=value% CURRENCY_SCALE
    local mode=currencyData and currencyData.rounding or "floor"
    if not allowDecimals and mode~="exact" then
        if mode=="ceil" and rem>0 then whole=whole+1 end
        if mode=="round" and rem>=CURRENCY_SCALE/2 then whole=whole+1 end
        local result=tostring(whole):reverse():gsub("(%d%d%d)","%1,"):gsub(",*$",""):reverse()
        return (negative and "-" or "")..result
    end
    local digits=string.format("%06d",rem):gsub("0+$","")
    local result=tostring(whole)
    if digits~="" then result=result.."."..digits end
    local left,tail=result:match("^(%d+)(.*)$")
    left=left:reverse():gsub("(%d%d%d)","%1,"):gsub(",*$",""):reverse()
    return (negative and "-" or "")..left..tail
end
local function currencyRatio(n,d,mode)
    if not n or not d or d<=0 then return nil end
    if mode=="ceil" then return floor((n+d-1)/d) end
    if mode=="round" then return floor((n+d/2)/d) end
    if mode=="exact" then return n/d end
    return floor(n/d)
end
local function currencySanitize(raw)
    local data=currencyCopy(currencyDefaults)
    data.coins={}; data.items={}; data.recent={}
    if type(raw)~="table" then return data end
    data.baseCoin=currencyValidName(raw.baseCoin) and ascii(raw.baseCoin) or ""
    data.allowDecimals=raw.allowDecimals==true
    data.rounding=({floor=true,round=true,ceil=true,exact=true})[raw.rounding] and raw.rounding or "floor"
    if (type(raw.coins)=="table" and #raw.coins>MAX_CURRENCY_COINS) or
        (type(raw.items)=="table" and #raw.items>MAX_CURRENCY_ITEMS) then
        currencyWarning="Currency data was trimmed to its supported size limits"
    end
    local seenCoins={}
    if type(raw.coins)=="table" then
        for _,coin in ipairs(raw.coins) do
            if #data.coins>=MAX_CURRENCY_COINS then break end
            if type(coin)=="table" and currencyValidName(coin.name) then
                local name=ascii(coin.name); local key=name:lower()
                local unit=tostring(coin.unit or coin.value or "")
                if currencyValidName(name) and not seenCoins[key] and currencyFixed(unit,data.allowDecimals) and currencyFixed(unit,data.allowDecimals)>0 then
                    seenCoins[key]=true
                    data.coins[#data.coins+1]={name=name,unit=unit}
                end
            end
        end
    end
    if data.baseCoin~="" then
        local matched
        for _,coin in ipairs(data.coins) do
            if coin.name:lower()==data.baseCoin:lower() then matched=coin.name; break end
        end
        data.baseCoin=matched or ""
    end
    local seenItems={}
    if type(raw.items)=="table" then
        for _,item in ipairs(raw.items) do
            if #data.items>=MAX_CURRENCY_ITEMS then break end
            if type(item)=="table" and currencyValidName(item.id) then
                local id=ascii(item.id)
                local stack=currencyInteger(tostring(item.stack or 64)) or 64
                local buy=tostring(item.buy or ""); local sell=tostring(item.sell or "")
                local name=tostring(item.name or item.id)
                if not currencyValidName(name) then name=item.id end
                name=ascii(name)
                if (buy=="" or currencyFixed(buy,data.allowDecimals)) and
                    (sell=="" or currencyFixed(sell,data.allowDecimals)) and stack>=1 and stack<=999999 and
                    currencyValidName(id) and currencyValidName(name) and not seenItems[id] then
                    seenItems[id]=true
                    data.items[#data.items+1]={id=id,name=name,buy=buy,sell=sell,
                        stack=stack,favorite=item.favorite==true}
                end
            end
        end
    end
    if type(raw.recent)=="table" then
        for _,id in ipairs(raw.recent) do
            if #data.recent>=MAX_CURRENCY_RECENT then break end
            if currencyValidName(id) then data.recent[#data.recent+1]=ascii(id) end
        end
    end
    return data
end
local function currencyLoad()
    local data
    local primaryOk,primaryExists=pcall(fs.exists,currencyPath)
    local backupOk,backupExists=pcall(fs.exists,currencyBackupPath)
    if not primaryOk or not backupOk then currencyWarning="Currency storage could not be checked" end
    if primaryOk and primaryExists then
        local ok,value=pcall(currencyRead,currencyPath); if ok then data=value end
    end
    if not data and backupOk and backupExists then
        local ok,value=pcall(currencyRead,currencyBackupPath); if ok then data=value; currencyWarning="Currency data restored from backup" end
    end
    if not data then
        data=currencyCopy(currencyDefaults)
        if (primaryOk and primaryExists) or (backupOk and backupExists) then
            currencyWarning="Currency data and backup are invalid; using an empty dictionary"
        end
    end
    return currencySanitize(data)
end
currencyData=currencyLoad()
E.currencyWarning=currencyWarning
local function currencySave()
    local ok,err=pcall(function()
        if not fileStorage then error("Safe file storage is unavailable") end
        if not fs.exists("/.hccos") then fs.makeDir("/.hccos") end
        if fs.exists(currencyPath) then
            local oldOk,old,oldRaw=pcall(currencyRead,currencyPath)
            if oldOk then
                local backedUp,backupError=fileStorage:writeManagedAtomic(currencyBackupPath,oldRaw or textutils.serialize(old),MAX_CURRENCY_BYTES)
                if not backedUp then error(backupError or "Cannot write currency backup") end
            end
        end
        local serialized=textutils.serialize(currencyData)
        local saved,saveError=fileStorage:writeManagedAtomic(currencyPath,serialized,MAX_CURRENCY_BYTES)
        if not saved then error(saveError or "Cannot save currency data") end
    end)
    return ok,err
end
local function currencyCoinValue(coin)
    return currencyFixed(coin and coin.unit,currencyData.allowDecimals)
end
local function currencyItemValue(item,side)
    return currencyFixed(item and item[side],currencyData.allowDecimals)
end
local function currencyCoinsByValue()
    local coins={}; for _,coin in ipairs(currencyData.coins) do
        if currencyCoinValue(coin) then coins[#coins+1]=coin end
    end
    table.sort(coins,function(a,b) return currencyCoinValue(a)>currencyCoinValue(b) end); return coins
end
local function currencyBreakdown(amount)
    local result={}; local remain=max(0,floor(amount or 0));
    for _,coin in ipairs(currencyCoinsByValue()) do
        local value=currencyCoinValue(coin); local count=floor(remain/value)
        if count>0 then result[#result+1]={name=coin.name,count=count,value=value}; remain=remain-count*value end
    end
    return result,remain
end
local function currencyBreakdownText(amount)
    local result,remain=currencyBreakdown(amount); local lines={}
    for _,part in ipairs(result) do lines[#lines+1]=part.name.." x"..part.count end
    if remain>0 then lines[#lines+1]="Remainder "..currencyFormat(remain,currencyData.allowDecimals) end
    return #lines>0 and table.concat(lines," / ") or "No coins registered"
end
local function currencyItemById(id)
    for _,item in ipairs(currencyData.items) do if item.id==id then return item end end
end
local function currencyFindCoin(name)
    for _,coin in ipairs(currencyData.coins) do if coin.name:lower()==tostring(name or ""):lower() then return coin end end
end
local function currencyCsvSplit(line)
    local parts={}; local index,length=1,#line
    while index<=length do
        local value
        if line:sub(index,index)=='"' then
            index=index+1; local chars={}; local closed=false
            while index<=length do
                local char=line:sub(index,index)
                if char=='"' then
                    if line:sub(index+1,index+1)=='"' then chars[#chars+1]='"'; index=index+2
                    else index=index+1; closed=true; break end
                else chars[#chars+1]=char; index=index+1 end
            end
            if not closed or (index<=length and line:sub(index,index)~=',') then return nil,"Invalid CSV quoting" end
            value=table.concat(chars)
        else
            local comma=line:find(",",index,true)
            if comma then value=line:sub(index,comma-1); index=comma
            else value=line:sub(index); index=length+1 end
        end
        parts[#parts+1]=value
        if index<=length and line:sub(index,index)==',' then index=index+1; if index>length then parts[#parts+1]="" end end
    end
    if length==0 then return {""} end
    return parts
end
local function currencyCsvField(value)
    return '"'..tostring(value or ""):gsub('"','""')..'"'
end
E.currencyData=currencyData; E.currencyPath=currencyPath; E.currencyBackupPath=currencyBackupPath; E.currencyCsvPath=currencyCsvPath
E.currencySave=currencySave; E.currencyFixed=currencyFixed; E.currencyInteger=currencyInteger; E.currencyMultiply=currencyMultiply; E.currencyFormat=currencyFormat; E.currencyRatio=currencyRatio; E.currencyCoinValue=currencyCoinValue; E.currencyItemValue=currencyItemValue; E.currencyCoinsByValue=currencyCoinsByValue; E.currencyBreakdown=currencyBreakdown; E.currencyBreakdownText=currencyBreakdownText; E.currencyItemById=currencyItemById; E.currencyFindCoin=currencyFindCoin; E.currencyCsvSplit=currencyCsvSplit; E.currencyCsvField=currencyCsvField; E.currencyMaxItems=MAX_CURRENCY_ITEMS; E.currencyMaxCoins=MAX_CURRENCY_COINS

end
