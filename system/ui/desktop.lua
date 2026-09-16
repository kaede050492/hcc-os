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
 E.HCCV15=context.api; E.HCCV14=context.api; E.Widget=context.ui.widgets; E.palette=E.P; E.modules=modules
 install(E,"ui/gpu_toms.lua",loadSystem)
 install(E,"ui/canvas.lua",loadSystem)
 install(E,"core/window_manager.lua",loadSystem)
 install(E,"ui/icons.lua",loadSystem)
 E.Widget.drawIcon=E.icons.app
 install(E,"core/currency_data.lua",loadSystem)
 install(E,"core/image_codec.lua",loadSystem)
 E.appContext={window={},canvas=E.canvas,widgets=E.Widget,
  scheduler={invalidate=function(win) if E.mark then E.mark(win) end end},
  logger=context.logger,settings=E.cfg,peripherals=E.devices,modules=modules,
  network=context.updater,filesystem=fs}
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
 if E then
  if E.cleanup then pcall(E.cleanup)
  elseif E.shutdownDisplay then pcall(E.shutdownDisplay) end
 end
 if not ok then error(result,0) end
 return result
end
return Desktop
