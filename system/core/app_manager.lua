local AppManager={}
function AppManager.install(E,catalog,loadModule,base)
 if type(catalog)~="table" then error("v1.4 application catalog is missing",0) end
 for _,entry in ipairs(catalog) do
  if entry.id~="updates" then
   local path=base.."apps/"..tostring(entry.module or entry.id)..".lua"
   local module=loadModule(path)
   if type(module)~="function" then error("Invalid application module: "..path,0) end
   local ok,err=xpcall(function() return module(E) end,function(reason)
    return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason)
   end)
   if not ok then error("Application module failed: "..path.."\n"..tostring(err),0) end
  end
 end
end
return AppManager

