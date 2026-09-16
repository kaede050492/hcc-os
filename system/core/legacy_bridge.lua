local Bridge={}
-- Legacy files are data sources only in v1.4. They are never loaded or executed.
function Bridge.find(paths)
 local candidates={paths.legacy,"/hcc_os/legacy/hccos_v1.3.3.lua","/hccos.lua"}
 for _,path in ipairs(candidates) do if fs.exists(path) and not fs.isDir(path) then return path end end
 return nil
end
function Bridge.describe(paths)
 local path=Bridge.find(paths)
 return path and {path=path,mode="migration-data-only"} or nil
end
function Bridge.run()
 return false,"Legacy desktop execution is disabled; v1.4 modules own the desktop"
end
return Bridge

