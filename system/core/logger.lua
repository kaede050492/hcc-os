local Logger = {}
Logger.__index = Logger

local function ascii(value)
    return tostring(value or ""):gsub("[^\032-\126]", "?")
end

function Logger.new(paths, limit)
    local self = setmetatable({}, Logger)
    self.paths = paths
    self.limit = math.max(50, math.min(1000, tonumber(limit) or 400))
    self.sequence = 0
    self.path = paths.logs.."/boot.log"
    local ok,available=pcall(function()
        if not fs.exists(paths.logs) then fs.makeDir(paths.logs) end
        return fs.exists(paths.logs)
    end)
    if not ok or not available then
        self.path="/.hccos/logs/boot.log"
        pcall(function() if not fs.exists("/.hccos/logs") then fs.makeDir("/.hccos/logs") end end)
    end
    return self
end

function Logger:write(level, message)
    level = ({INFO=true, WARN=true, ERROR=true})[level] and level or "INFO"
    local line = string.format("[%s] %s", level, ascii(message))
    self.sequence = self.sequence + 1
    local function persist(path)
        local existing = {}
        if fs.exists(path) then
            local f = fs.open(path, "r")
            if f then
                for lineValue in (f.readAll().."\n"):gmatch("([^\r\n]+)\n") do
                    existing[#existing+1] = lineValue
                end
                f.close()
            end
        end
        existing[#existing+1] = line
        while #existing > self.limit do table.remove(existing, 1) end
        local f, err = fs.open(path, "w")
        if not f then return false, err end
        f.write(table.concat(existing, "\n").."\n")
        f.close()
        return true
    end
    local ok,result=pcall(persist,self.path)
    if ok and result then return true end
    if self.path~="/.hccos/logs/boot.log" then
        self.path="/.hccos/logs/boot.log"
        pcall(function() if not fs.exists("/.hccos/logs") then fs.makeDir("/.hccos/logs") end end)
        local fallbackOk,fallbackResult=pcall(persist,self.path)
        if fallbackOk and fallbackResult then return true end
        return false,tostring(fallbackResult or result)
    end
    return false,tostring(result)
end

function Logger:info(message) return self:write("INFO", message) end
function Logger:warn(message) return self:write("WARN", message) end
function Logger:error(message) return self:write("ERROR", message) end

function Logger:read()
    if not fs.exists(self.path) then return "" end
    local f = fs.open(self.path, "r")
    if not f then return "" end
    local value = f.readAll() or ""
    f.close()
    return value
end

return Logger
