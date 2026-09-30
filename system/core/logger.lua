-- Bounded in-memory log with append-first persistence and periodic compaction.
local Logger = {}
Logger.__index = Logger

local MAX_STARTUP_BYTES = 262144

local function safeExists(path)
    local ok, value = pcall(fs.exists, path)
    return ok and value == true
end

local function safeAscii(value)
    local clean = tostring(value or ""):gsub("[\r\n]", " "):gsub("[^\032-\126]", "?")
    return clean
end

local function ensureDirectory(path)
    local ok, isDirectory = pcall(function()
        if not fs.exists(path) then fs.makeDir(path) end
        return fs.isDir(path)
    end)
    return ok and isDirectory == true
end

local function push(self, line)
    if self.count < self.limit then
        local index = ((self.head + self.count - 1) % self.limit) + 1
        self.lines[index] = line
        self.count = self.count + 1
    else
        self.lines[self.head] = line
        self.head = (self.head % self.limit) + 1
    end
end

local function orderedLines(self)
    local result = {}
    for index = 0, self.count - 1 do
        local slot = ((self.head + index - 1) % self.limit) + 1
        result[#result + 1] = self.lines[slot]
    end
    return result
end

local function compact(self)
    local temporary = self.path .. ".compact.tmp"
    local previous = self.path .. ".compact.prev"
    local file, err = fs.open(temporary, "w")
    if not file then return false, err or "could not open log for compaction" end
    local ok, writeError = pcall(function()
        for _, line in ipairs(orderedLines(self)) do
            if type(file.writeLine) == "function" then file.writeLine(line)
            else file.write(line .. "\n") end
        end
    end)
    local closeOk, closeError = pcall(file.close)
    if not ok or not closeOk then
        pcall(fs.delete, temporary)
        return false, writeError or closeError
    end
    if safeExists(previous) then
        local removed, removeError = pcall(fs.delete, previous)
        if not removed then pcall(fs.delete, temporary); return false, removeError end
    end
    local hadOriginal = safeExists(self.path)
    if hadOriginal then
        local moved, moveError = pcall(fs.move, self.path, previous)
        if not moved or not safeExists(previous) then
            pcall(fs.delete, temporary)
            return false, moveError or "could not preserve log before compaction"
        end
    end
    local committed, commitError = pcall(fs.move, temporary, self.path)
    if not committed or not safeExists(self.path) then
        if hadOriginal and not safeExists(self.path) and safeExists(previous) then pcall(fs.move, previous, self.path) end
        pcall(fs.delete, temporary)
        return false, commitError or "could not install compacted log"
    end
    if hadOriginal then pcall(fs.delete, previous) end
    self.persisted = self.count
    self.nextCompactAt = self.persisted + self.limit
    return true
end

local function append(self, path, line)
    local file, err = fs.open(path, "a")
    if not file then return false, err or "could not open log for append" end
    local ok, writeError = pcall(function()
        if type(file.writeLine) == "function" then file.writeLine(line)
        else file.write(line .. "\n") end
    end)
    local closeOk, closeError = pcall(file.close)
    if not ok then return false, writeError end
    if not closeOk then return false, closeError end
    return true
end

local function loadExisting(self)
    if not safeExists(self.path) then return end
    local sizeOk, size = pcall(fs.getSize, self.path)
    if sizeOk and type(size) == "number" and size > MAX_STARTUP_BYTES then
        local oldPath = self.path .. ".oversized." .. tostring(math.floor(os.clock() * 1000))
        local moved = pcall(fs.move, self.path, oldPath)
        if moved then return true end
        -- Avoid an unbounded startup read when an oversized log cannot move.
        return false
    end
    local opened, file = pcall(fs.open, self.path, "r")
    if not opened or not file then return false end
    local readOk = true
    if type(file.readLine) == "function" then
        while true do
            local ok, line = pcall(file.readLine)
            if not ok then readOk = false; break end
            if line == nil then break end
            push(self, safeAscii(line))
        end
    else
        local ok, contents = pcall(file.readAll)
        if not ok then readOk = false
        else
            for line in ((contents or "") .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
                if line ~= "" then push(self, safeAscii(line)) end
            end
        end
    end
    local closed = pcall(file.close)
    if not readOk or not closed then return false end
    self.persisted = self.count
    self.nextCompactAt = self.limit * 2
    return true
end

function Logger.new(paths, limit)
    local self = setmetatable({}, Logger)
    self.paths = paths
    self.limit = math.max(50, math.min(1000, math.floor(tonumber(limit) or 400)))
    self.sequence = 0
    self.head, self.count = 1, 0
    self.lines = {}
    self.persisted = 0
    self.nextCompactAt = self.limit * 2
    self.path = paths.logs .. "/boot.log"
    if not ensureDirectory(paths.logs) then
        self.path = "/.hccos/logs/boot.log"
        ensureDirectory("/.hccos/logs")
    end
    local readable = loadExisting(self)
    if readable == false then
        local fallback = "/.hccos/logs/boot.session." .. tostring(math.floor(os.clock() * 1000)) .. ".log"
        ensureDirectory(fs.getDir(fallback))
        self.path, self.persisted = fallback, 0
    end
    local compactOk, compacted = pcall(compact, self)
    if not compactOk or not compacted then self.nextCompactAt = self.persisted + self.limit end
    return self
end

function Logger:write(level, message)
    level = ({ INFO=true, WARN=true, ERROR=true })[level] and level or "INFO"
    local line = string.format("[%s] %s", level, safeAscii(message))
    self.sequence = self.sequence + 1
    push(self, line)

    local appendOk, appendResult = pcall(append, self, self.path, line)
    local appended = appendOk and appendResult == true
    if not appended then
        local fallback = "/.hccos/logs/boot.log"
        if self.path ~= fallback then
            ensureDirectory("/.hccos/logs")
            self.path = fallback
            appendOk, appendResult = pcall(append, self, self.path, line)
            appended = appendOk and appendResult == true
        end
    end

    if appended then self.persisted = self.persisted + 1 end
    if self.persisted >= self.nextCompactAt then
        local compactCallOk, compacted = pcall(compact, self)
        if not compactCallOk or not compacted then self.nextCompactAt = self.persisted + self.limit end
    end
    if not appended then return false, tostring(appendResult) end
    return true
end

function Logger:info(message) return self:write("INFO", message) end
function Logger:warn(message) return self:write("WARN", message) end
function Logger:error(message) return self:write("ERROR", message) end

function Logger:read()
    return table.concat(orderedLines(self), "\n") .. (self.count > 0 and "\n" or "")
end

return Logger
