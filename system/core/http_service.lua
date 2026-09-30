-- Own asynchronous CC:T HTTP requests and their URL-only completion events.
local HttpService={}
HttpService.__index=HttpService

local function closeResponse(handle)
    if type(handle)=="table" and type(handle.close)=="function" then pcall(handle.close) end
end

function HttpService.new(api,requests)
    return setmetatable({api=api,requests=type(requests)=="table" and requests or {},limit=64},HttpService)
end

function HttpService:_request(kind,owner,url,body,headers,binary)
    if type(url)~="string" or url=="" or #url>4096 then return false,"invalid HTTP URL" end
    if self.requests[url] then return false,"a request for this URL is already active" end
    local count=0
    for _ in pairs(self.requests) do count=count+1 end
    if count>=self.limit then return false,"HTTP request limit reached" end
    if type(self.api)~="table" or type(self.api.request)~="function" then return false,"HTTP request API unavailable" end
    local ok,accepted,reason=pcall(self.api.request,url,body,headers,binary)
    if not ok then return false,tostring(accepted) end
    if accepted==false or accepted==nil then return false,tostring(reason or "HTTP request failed or was denied") end
    self.requests[url]={kind=kind,owner=owner,cancelled=false}
    if kind=="app" then
        owner.httpRequests=owner.httpRequests or {}
        owner.httpRequests[url]=true
    end
    return true
end

function HttpService:requestApp(owner,url,body,headers,binary)
    if not owner or owner.closed or owner.crash or owner.minimized then return false,"application is not active" end
    return self:_request("app",owner,url,body,headers,binary)
end

function HttpService:requestSystem(owner,url,body,headers,binary)
    if type(owner)~="table" or type(owner.handleHttp)~="function" then return false,"HTTP service handler unavailable" end
    return self:_request("system",owner,url,body,headers,binary)
end

local function cancel(self,kind,owner,url)
    if type(url)~="string" then return false end
    local record=self.requests[url]
    if not record or record.kind~=kind or record.owner~=owner then return false end
    record.owner=nil; record.cancelled=true
    if kind=="app" and owner.httpRequests then owner.httpRequests[url]=nil end
    return true
end

function HttpService:cancelApp(owner,url) return cancel(self,"app",owner,url) end
function HttpService:cancelSystem(owner,url) return cancel(self,"system",owner,url) end

function HttpService:cancelAppOwner(owner)
    if not owner or not owner.httpRequests then return end
    local urls={}
    for url in pairs(owner.httpRequests) do urls[#urls+1]=url end
    for _,url in ipairs(urls) do cancel(self,"app",owner,url) end
end

function HttpService:has(url)
    return type(url)=="string" and self.requests[url]~=nil
end

function HttpService:dispatch(event,dispatchApp,logError)
    if type(event)~="table" or (event[1]~="http_success" and event[1]~="http_failure") or type(event[2])~="string" then
        return false
    end
    local record=self.requests[event[2]]
    if not record then return false end
    self.requests[event[2]]=nil
    local owner=record.owner
    if owner and record.kind=="app" and owner.httpRequests then owner.httpRequests[event[2]]=nil end
    local handle=event[1]=="http_success" and event[3] or event[4]
    if record.cancelled or not owner then closeResponse(handle); return true end
    if record.kind=="system" then
        local ok,claimed=pcall(owner.handleHttp,event[2],event[3])
        if not ok and type(logError)=="function" then pcall(logError,"HTTP service callback failed: "..tostring(claimed)) end
        if event[1]=="http_failure" or not ok or claimed~=true then closeResponse(handle) end
        return true
    end
    local method=event[1]=="http_success" and "onHttpSuccess" or "onHttpFailure"
    local ok,handled=false,false
    if type(dispatchApp)=="function" then ok,handled=pcall(dispatchApp,owner,method,event[2],event[3]) end
    if not ok and type(logError)=="function" then pcall(logError,"Application HTTP callback failed: "..tostring(handled)) end
    if event[1]=="http_failure" or not ok or handled~=true then closeResponse(handle) end
    return true
end

return {new=function(api,requests) return HttpService.new(api,requests) end}
