-- Canonical HCC OS paths. Boot-critical system files remain on the computer
-- filesystem, while removable writable mounts are used for user data.

local function usableDisk(path)
    if not fs.exists(path) or not fs.isDir(path) then return false end
    local readOnlyOk,readOnly=pcall(fs.isReadOnly,path)
    if readOnlyOk and readOnly then return false end
    local freeOk,free=pcall(fs.getFreeSpace,path)
    return freeOk and (free=="unlimited" or (type(free)=="number" and free>=65536))
end

local mounts={}
for _,name in ipairs(fs.list("/")) do
    if tostring(name):match("^disk%d*$") then
        local path=fs.combine("/",name)
        if usableDisk(path) then mounts[#mounts+1]=path end
    end
end
table.sort(mounts,function(a,b)
    local an=tonumber(a:match("/disk(%d+)$")) or 0
    local bn=tonumber(b:match("/disk(%d+)$")) or 0
    return an<bn
end)

local function userPath(name,slot)
    if #mounts==0 then return "/.hccos/"..name end
    local mount=mounts[((math.max(1,slot or 1)-1)%#mounts)+1]
    return fs.combine(mount,"hccos/"..name)
end

local updateTemps={}
if #mounts==0 then
    updateTemps[1]="/.hccos/temp/update"
else
    for _,mount in ipairs(mounts) do updateTemps[#updateTemps+1]=fs.combine(mount,"hccos/temp/update") end
end

local backupRoots={}
if #mounts==0 then
    backupRoots[1]="/.hccos/backups"
else
    for _,mount in ipairs(mounts) do backupRoots[#backupRoots+1]=fs.combine(mount,"hccos/backups") end
end

return {
    version = "1.5.0",
    system = "/.hccos/system",
    core = "/.hccos/system/core",
    ui = "/.hccos/system/ui",
    apps = "/.hccos/system/apps",
    versionFile = "/.hccos/system/version.lua",
    config = "/.hccos/config",
    settings = "/.hccos/config/settings",
    legacySettings = "/.hccos/settings",
    storageMounts = mounts,
    storageMinimum = 65536,
    images = userPath("images",1),
    cache = userPath("cache",2),
    downloads = userPath("downloads",3),
    logs = userPath("logs",4),
    backupRoots = backupRoots,
    backups = backupRoots[1],
    temp = userPath("temp",4),
    updateTemps = updateTemps,
    updateTemp = updateTemps[1],
    currency = "/.hccos/currency",
    currencyBackup = "/.hccos/currency.bak",
    startup = "/startup.lua",
    manifest = "/.hccos/system/manifest.lua"
}
