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
local function install(E,path)
 local module=loadModule(BASE..path)
 if type(module)~="function" then error("Invalid GUI module: "..path,0) end
 local ok,err=xpcall(function() return module(E) end,traceback)
 if not ok then error("GUI module failed: "..path.."\n"..tostring(err),0) end
end
local function runDesktop(context,catalog,holder)
 local Runtime=loadModule(BASE.."core/runtime.lua")
 local E=Runtime.new(context); holder.runtime=E
 E.HCCV14=context.api; E.Widget=context.ui.widgets; E.palette=E.P
 install(E,"ui/gpu_toms.lua")
 install(E,"ui/canvas.lua")
 install(E,"core/window_manager.lua")
 install(E,"ui/icons.lua")
 E.Widget.drawIcon=E.drawAppIcon
 install(E,"core/currency_data.lua")
 install(E,"core/image_codec.lua")
 E.appContext={window={},canvas=E.canvas,widgets=E.Widget,
  scheduler={invalidate=function(win) if E.mark then E.mark(win) end end},
  logger=context.logger,settings=E.cfg,peripherals=E.devices,
  network=context.updater,filesystem=fs}
 local AppManager=loadModule(BASE.."core/app_manager.lua")
 AppManager.install(E,catalog,loadModule,BASE)
 if context.config:isFirstBoot() then install(E,"apps/setup.lua") end
 local update=loadModule(BASE.."apps/update_recovery.lua")
 if type(update.attach)=="function" then update.attach(E,context.api) end
 install(E,"ui/desktop_view.lua")
 install(E,"ui/taskbar.lua")
 install(E,"ui/start_menu.lua")
 install(E,"ui/compositor.lua")
 install(E,"core/window_actions.lua")
 install(E,"core/input.lua")
 install(E,"core/scheduler.lua")
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

