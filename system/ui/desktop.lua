local Desktop={}
local BASE="/.hccos/system/"
local function traceback(reason) return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason) end
local function loadModule(path)
 local f,err=fs.open(path,"r"); if not f then error(err or ("Missing module: "..path),0) end
 local source=f.readAll() or ""; f.close()
 local chunk,loadError=load(source,"@"..path,"t",_ENV)
 if not chunk then error(loadError or ("Could not load module: "..path),0) end
 local ok,value=xpcall(chunk,traceback); if not ok then error(value,0) end
 return value
end
local function install(E,path,loader)
 local module=loader and loader(path) or loadModule(BASE..path)
 if type(module)~="function" then error("Invalid GUI module: "..path,0) end
 local ok,err=xpcall(function() return module(E) end,traceback)
 if not ok then error("GUI module failed: "..path.."\n"..tostring(err),0) end
end
local function runDesktop(context,catalog,holder)
 local modules=context.modules
 local function loadSystem(path)
  if modules then return modules:loadPath(BASE..path, _ENV, path) end
  return loadModule(BASE..path)
 end
 local Runtime=loadSystem("core/runtime.lua")
 local E=Runtime.new(context); holder.runtime=E
 E.paths=context.paths
 E.Widget=context.ui.widgets; E.palette=E.P; E.modules=modules
 install(E,"ui/gpu_toms.lua",loadSystem)
 install(E,"ui/canvas.lua",loadSystem)
 install(E,"core/window_manager.lua",loadSystem)
 context.httpDispatcher=function(event)
  if type(event)~="table" then return false end
  return E.dispatchHttpEvent(event)
 end
 if context.updater and context.httpService then
  context.updater.httpAvailable=function(url) return not context.httpService:has(url) end
  context.updater.requestHttp=function(url,body,headers,binary)
   return context.httpService:requestSystem(context.api,url,body,headers,binary)
  end
  context.updater.cancelHttpRequest=function(url)
   return context.httpService:cancelSystem(context.api,url)
  end
 end
 install(E,"ui/icons.lua",loadSystem)
 E.Widget.drawIcon=E.icons.app
 install(E,"core/currency_data.lua",loadSystem)
 install(E,"core/image_codec.lua",loadSystem)
 E.makeAppContext=function(win)
 return {window=win,canvas=E.canvas,widgets=E.Widget,
   scheduler={
    invalidate=function(target) if E.mark then E.mark(target or win) end end,
    after=function(delay,callback) return E.scheduleOwnedTimer(win,delay,callback) end,
    cancel=function(token) return E.cancelOwnedTimer(win,token) end},
   http={
    request=function(url,body,headers,binary) return E.requestHttp(win,url,body,headers,binary) end,
    cancel=function(url) return E.cancelHttpRequest(win,url) end},
   logger=context.logger,settings=E.cfg,configuration=context.config,updater=context.updater,
   takeAutoUpdatePending=function()
    local api=context.api
    if not api or api.autoUpdatePending~=true then return false end
    api.autoUpdatePending=false
    return true
   end,
   ui={
    mark=function(target) if E.mark then return E.mark(target or win) end end,
    button=function(...) return E.button(...) end,
    requestRecovery=function() if E.requestRecovery then return E.requestRecovery() end end,
    palette=function() return E.P end
   },
   peripherals=E.devices,modules=modules,storage=context.fileService,
   network=context.updater,filesystem=fs}
 end
 E.require=function(name)
  if modules then return modules:load(name) end
  error("external modules are unavailable",0)
 end
 local AppManager=loadSystem("core/app_manager.lua")
 local function loadApp(path)
  if modules then return modules:loadPath(path, _ENV, path) end
  return loadModule(path)
 end
 AppManager.install(E,context.appRegistry,loadApp,BASE)
 if context.config:isFirstBoot() then AppManager.installBoot(E,context.appRegistry,loadApp) end
 install(E,"ui/desktop_view.lua",loadSystem)
 install(E,"ui/taskbar.lua",loadSystem)
 install(E,"ui/start_menu.lua",loadSystem)
 install(E,"ui/cursor.lua",loadSystem)
 install(E,"ui/compositor.lua",loadSystem)
 install(E,"core/window_actions.lua",loadSystem)
 install(E,"core/input.lua",loadSystem)
 install(E,"core/scheduler.lua",loadSystem)
 context.runtime=E
 return E.run()
end
function Desktop.run(context,catalog)
 local holder={}
 local ok,result=xpcall(function() return runDesktop(context,catalog,holder) end,traceback)
 local E=holder.runtime
 local recoveryRequested=E and E.OS and E.OS.recoveryRequested==true
 if E then
  if E.cleanup then pcall(E.cleanup)
  elseif E.shutdownDisplay then pcall(E.shutdownDisplay) end
 end
 if context.updater then context.updater.httpAvailable=nil end
 -- Return the failure to bootstrap instead of raising it again. Re-raising a
 -- traceback here hides the original startup reason behind CraftOS's internal
 -- exception screen and prevents the normal Recovery UI from opening.
 if not ok then return false,result end
 if recoveryRequested then return false,"manual recovery request" end
 return true,result
end
return Desktop
