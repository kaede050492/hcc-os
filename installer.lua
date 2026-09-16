-- HCC OS v1.5.0 standalone installer.
-- Self-contained: no installed HCC OS module is required.
local GITHUB_USER="kaede050492"
local GITHUB_REPOSITORY="hcc-os"
local GITHUB_BRANCH="main"
local RAW_ROOT="https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPOSITORY.."/"..GITHUB_BRANCH
local MANIFEST_URL=RAW_ROOT.."/manifest.lua"
local COMMIT_API_URL="https://api.github.com/repos/"..GITHUB_USER.."/"..GITHUB_REPOSITORY.."/commits/"..GITHUB_BRANCH

local SYSTEM_ROOT="/.hccos/system"
local CONFIG_ROOT="/.hccos/config"
local TEMP_ROOT="/.hccos/temp/installer"
local TEMP_SYSTEM=TEMP_ROOT.."/system"
local TEMP_STARTUP=TEMP_ROOT.."/startup.lua"
local BACKUP_ROOT="/.hccos/backups"
local STARTUP="/startup.lua"
local SAFETY_MARGIN=16384
local DATA_DIRECTORIES={
 "/.hccos",CONFIG_ROOT,"/.hccos/images","/.hccos/cache",
 "/.hccos/downloads","/.hccos/logs",BACKUP_ROOT,"/.hccos/temp"
}

local function safeRelative(path)
 if type(path)~="string" or path=="" or #path>160 then return false end
 if path:find("[%z\\]") or path:sub(1,1)=="/" or path:match("^[A-Za-z]:") then return false end
 for part in path:gmatch("[^/]+") do if part==".." or part=="." or part=="" then return false end end
 return true
end
local function safeVersion(value) return tostring(value or "previous"):gsub("[^%w%._%-]","_"):sub(1,48) end
local function makeDir(path)
 if fs.exists(path) then if not fs.isDir(path) then error("Not a directory: "..path,0) end; return end
 local parent=fs.getDir(path); if parent~="" and parent~=path then makeDir(parent) end; fs.makeDir(path)
end
local function ensureParent(path) local parent=fs.getDir(path); if parent~="" then makeDir(parent) end end
local function readAll(path)
 local f,err=fs.open(path,"r"); if not f then return nil,err end
 local ok,value=pcall(f.readAll); f.close(); if not ok then return nil,value end; return value or ""
end
local function writeAll(path,value)
 ensureParent(path); local f,err=fs.open(path,"w"); if not f then return false,err end
 local ok,writeError=pcall(f.write,value); f.close(); return ok,writeError
end
local function fetch(url,headers)
 if type(http)~="table" or type(http.get)~="function" then return nil,"CC:T HTTP API unavailable" end
 if type(url)~="string" or not url:match("^https://[^%s]+$") then return nil,"unsafe HTTPS URL" end
 local requestOk,handle,err=pcall(http.get,url,headers)
 if not requestOk then return nil,"HTTP failed: "..url..": "..tostring(handle) end
 if not handle then return nil,"HTTP failed: "..url..": "..tostring(err) end
 local readOk,body=pcall(handle.readAll)
 local code=200
 if type(handle.getResponseCode)=="function" then local codeOk,responseCode=pcall(handle.getResponseCode); if codeOk and responseCode then code=responseCode end end
 local closeOk,closeError=pcall(handle.close)
 if not readOk then return nil,"HTTP failed: "..url..": response could not be read: "..tostring(body) end
 if not closeOk then return nil,"HTTP failed: "..url..": response close failed: "..tostring(closeError) end
 if code<200 or code>=300 then return nil,"HTTP failed: "..url..": HTTP "..tostring(code) end
 if type(body)~="string" or #body==0 then return nil,"HTTP failed: "..url..": empty response" end
 return body
end
local function latestCommit()
 local body,err=fetch(COMMIT_API_URL,{["Accept"]="application/vnd.github+json",["User-Agent"]="HCC-OS-Installer"})
 if not body then return nil,err end
 local value
 if textutils and type(textutils.unserializeJSON)=="function" then
  local ok,result=pcall(textutils.unserializeJSON,body); if ok then value=result end
 end
 local sha=type(value)=="table" and value.sha or body:match('"sha"%s*:%s*"([%da-fA-F]+)"')
 if type(sha)~="string" or not sha:match("^[%da-fA-F]+$") then return nil,"GitHub returned no commit SHA" end
 return sha:lower()
end
local function parseManifest(source)
 if type(source)~="string" then return nil,"manifest body is not text" end
 source=source:gsub("^\239\187\191","")
 local chunk,err=load(source,"@remote manifest.lua","t",{})
 if not chunk then chunk,err=load(source,"@remote manifest.lua") end
 if not chunk then return nil,err end
 local ok,value=pcall(chunk)
 if not ok or type(value)~="table" then return nil,ok and "manifest is invalid" or tostring(value) end
 if type(value.version)~="string" or value.version=="" then return nil,"manifest version is missing" end
 if type(value.files)~="table" then return nil,"manifest files list is missing" end
 return value
end
local function systemUrl(relative)
 if relative=="manifest.lua" then return RAW_ROOT.."/manifest.lua" end
 return RAW_ROOT.."/system/"..relative
end
local function manifestEntries(manifest)
 local entries,seen,versionEntry={},{},nil
 for _,raw in ipairs(manifest.files) do
  local relative=type(raw)=="string" and raw or raw and raw.path
  if not safeRelative(relative) then error("Unsafe manifest path: "..tostring(relative),0) end
  if seen[relative] then error("Duplicate manifest path: "..relative,0) end
  seen[relative]=true
  local entry={path=relative,size=type(raw)=="table" and tonumber(raw.size) or nil}
  if relative=="version.lua" then versionEntry=entry else entries[#entries+1]=entry end
 end
 if versionEntry then entries[#entries+1]=versionEntry end
 if #entries==0 then error("Manifest has no system files",0) end
 return entries
end
local function currentVersion()
 local source=readAll(SYSTEM_ROOT.."/version.lua")
 return source and (source:match("version%s*=%s*['\"]([^'\"]+)") or "previous") or "previous"
end
local function freeSpace()
 if type(fs.getFreeSpace)~="function" then return nil end
 local ok,value=pcall(fs.getFreeSpace,"/"); return ok and type(value)=="number" and value or nil
end
local function fetchFile(url,destination,expectedSize)
 local body,err=fetch(url); if not body then error(err,0) end
 if expectedSize and #body~=expectedSize then error(destination..": size mismatch",0) end
 local ok,writeError=writeAll(destination,body); if not ok then error(destination..": "..tostring(writeError),0) end
 return #body
end
local function downloadSystem(entries,destination,installedLimit,fileLimit)
 makeDir(destination); local downloaded=0
 for index,entry in ipairs(entries) do
  print(string.format("Downloading %d/%d: %s",index,#entries,entry.path))
  local body,err=fetch(systemUrl(entry.path)); if not body then error(entry.path..": "..tostring(err),0) end
  if entry.size and #body~=entry.size then error(entry.path..": size mismatch",0) end
  if #body>fileLimit or downloaded+#body>installedLimit then error(entry.path..": manifest storage limit exceeded",0) end
  local target=fs.combine(destination,entry.path)
  local ok,writeError=writeAll(target,body); if not ok then error(target..": "..tostring(writeError),0) end
  downloaded=downloaded+#body
 end
 return downloaded
end
local function backupPath(label)
 makeDir(BACKUP_ROOT); local path=BACKUP_ROOT.."/"..safeVersion(label or currentVersion())
 if fs.exists(path) then path=path.."-"..tostring(os.epoch("utc")) end
 makeDir(path); return path
end
local function removeEmpty(path)
 if fs.exists(path) and fs.isDir(path) and #fs.list(path)==0 then pcall(fs.delete,path) end
end
local function cleanupTemp()
 if fs.exists(TEMP_ROOT) then pcall(fs.delete,TEMP_ROOT) end
 removeEmpty("/.hccos/temp")
end
local function restoreExisting(state)
 if state.newStartup and fs.exists(STARTUP) then pcall(fs.delete,STARTUP) end
 if state.oldStartup and fs.exists(state.backup.."/startup.lua") then pcall(fs.move,state.backup.."/startup.lua",STARTUP) end
 if state.newSystem and fs.exists(SYSTEM_ROOT) then pcall(fs.delete,SYSTEM_ROOT) end
 if state.oldSystem and fs.exists(state.backup.."/system") then pcall(fs.move,state.backup.."/system",SYSTEM_ROOT) end
end
local function placeExisting()
 local state={backup=backupPath(currentVersion()),oldSystem=false,newSystem=false,oldStartup=false,newStartup=false}
 local ok,err=pcall(function()
  if fs.exists(SYSTEM_ROOT) then fs.move(SYSTEM_ROOT,state.backup.."/system"); state.oldSystem=true end
  if fs.exists(STARTUP) then fs.move(STARTUP,state.backup.."/startup.lua"); state.oldStartup=true end
  fs.move(TEMP_SYSTEM,SYSTEM_ROOT); state.newSystem=true
  if not fs.exists(TEMP_STARTUP) then error("startup.lua was not staged") end
  fs.move(TEMP_STARTUP,STARTUP); state.newStartup=true
 end)
 if not ok then restoreExisting(state); error(err,0) end
 return state.backup
end
local function placeClean()
 local state={backup=nil,oldStartup=false,newStartup=false}
 if fs.exists(STARTUP) then
   state.backup=backupPath("pre-v1.5")
  fs.move(STARTUP,state.backup.."/startup.lua"); state.oldStartup=true
 end
 local ok,err=pcall(function()
  if not fs.exists(TEMP_STARTUP) then error("startup.lua was not staged") end
  fs.move(TEMP_STARTUP,STARTUP); state.newStartup=true
 end)
 if not ok then
  if state.newStartup and fs.exists(STARTUP) then pcall(fs.delete,STARTUP) end
  if state.oldStartup and fs.exists(state.backup.."/startup.lua") then pcall(fs.move,state.backup.."/startup.lua",STARTUP) end
  error(err,0)
 end
 return state.backup
end
local function removeInstaller()
 if type(shell)~="table" or type(shell.getRunningProgram)~="function" then return end
 local ok,path=pcall(shell.getRunningProgram); if not ok or type(path)~="string" then return end
 path=fs.combine("/",path)
 if path=="/installer.lua" and fs.exists(path) and not fs.isDir(path) then pcall(fs.delete,path) end
end
local function install()
 term.clear(); term.setCursorPos(1,1)
 print("HCC OS v1.5.0 Standalone Installer")
 print("GitHub: "..RAW_ROOT)
 print("User data is kept outside /.hccos/system."); print("")
 cleanupTemp()
 local manifestBody,manifestError=fetch(MANIFEST_URL)
 if not manifestBody then error("manifest.lua: "..tostring(manifestError),0) end
 local manifest,parseError=parseManifest(manifestBody)
 if not manifest then error("manifest.lua: "..tostring(parseError),0) end
 local commitSha,commitError=latestCommit()
 local entries=manifestEntries(manifest)
 local existing=fs.exists(SYSTEM_ROOT) and fs.isDir(SYSTEM_ROOT)
 local installedSize=math.max(0,math.floor(tonumber(manifest.installedSize) or 0))
 local startupSize=math.max(1,math.floor(tonumber(manifest.startupSize) or 4096))
 local maximumFileSize=math.max(1,math.floor(tonumber(manifest.maxFileSize) or 40000))
 local temporarySize=existing and (installedSize+startupSize) or startupSize
 local requiredAdditional=installedSize+startupSize+SAFETY_MARGIN
 local free=freeSpace()
 print("Release: "..manifest.version.." / build "..tostring(manifest.build or "unknown"))
 print("GitHub commit: "..(commitSha and commitSha:sub(1,12) or "unavailable"))
 if commitError then print("Commit lookup: "..tostring(commitError)) end
 print("Manifest revision: "..tostring(manifest.revision or "unknown"))
 print("Mode: "..(existing and "SAFE UPDATE" or "MINIMAL CLEAN INSTALL"))
 print("Free space: "..tostring(free or "unavailable").." bytes")
 print("Required temporary space: "..temporarySize.." bytes")
 print("Installed size: "..installedSize.." bytes")
 print("Estimated free after installation: "..tostring(free and math.max(0,free-installedSize-startupSize) or "unavailable").." bytes")
 if installedSize<=0 then error("Manifest installedSize is missing",0) end
 if free and free<requiredAdditional then
  error("Not enough free space: need "..requiredAdditional.." bytes including safety margin; existing system was not changed",0)
 end
 for _,path in ipairs(DATA_DIRECTORIES) do makeDir(path) end
 makeDir(TEMP_ROOT)
 local backup
 if existing then
  downloadSystem(entries,TEMP_SYSTEM,installedSize,maximumFileSize)
  print("Downloading: startup.lua")
  fetchFile(RAW_ROOT.."/startup.lua",TEMP_STARTUP,startupSize)
  backup=placeExisting()
 else
  local createdSystem=false
  local ok,err=pcall(function()
   if fs.exists(SYSTEM_ROOT) then error("System target is not a directory",0) end
   makeDir(SYSTEM_ROOT); createdSystem=true
   downloadSystem(entries,SYSTEM_ROOT,installedSize,maximumFileSize)
   print("Downloading: startup.lua")
   fetchFile(RAW_ROOT.."/startup.lua",TEMP_STARTUP,startupSize)
   backup=placeClean()
  end)
  if not ok then
   if createdSystem and fs.exists(SYSTEM_ROOT) then pcall(fs.delete,SYSTEM_ROOT) end
   error(err,0)
  end
 end
 cleanupTemp()
  print(""); print("Installation complete: HCC OS v"..manifest.version)
 if backup then print("Backup: "..backup) else print("Backup: not required for clean install") end
 print("Reboot or run /startup.lua.")
 removeInstaller()
end
local ok,err=pcall(install)
if not ok then
 cleanupTemp()
 print("Installation failed: "..tostring(err))
 print("The existing system and user data were not removed.")
end
