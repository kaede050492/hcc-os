-- Run with Lua 5.2+ from the repository root:
--   lua tests/http_service_spec.lua

local moduleChunk,moduleError=loadfile("system/core/http_service.lua")
assert(moduleChunk,moduleError)
local HttpService=moduleChunk()
local requestsMade={}
local api={request=function(url,body,headers,binary)
    requestsMade[#requestsMade+1]={url=url,body=body,headers=headers,binary=binary}
    return true
end}
local service=HttpService.new(api,{})
local owner={httpRequests={}}
assert(service:requestApp(owner,"https://example.test/app","payload",{accept="text/plain"},true))
assert(owner.httpRequests["https://example.test/app"] and service:has("https://example.test/app"),
    "accepted app requests should be owned until completion")
assert(requestsMade[1].body=="payload" and requestsMade[1].binary==true,
    "request options should reach the HTTP API")
local ok,reason=service:requestApp(owner,"https://example.test/app")
assert(not ok and reason:find("already active",1,true),"duplicate URLs should be rejected")
assert(not service:requestApp(owner,""),"empty URLs should be rejected")

local closed=0
local cancelledHandle={close=function() closed=closed+1 end}
service:cancelAppOwner(owner)
local dispatched=service:dispatch({"http_success","https://example.test/app",cancelledHandle},
    function() error("cancelled requests must not reach apps") end)
assert(dispatched and closed==1 and not service:has("https://example.test/app") and
    not owner.httpRequests["https://example.test/app"],
    "cancelled responses should be closed and removed")

local successfulOwner={httpRequests={}}
local successfulHandle={close=function() closed=closed+1 end}
assert(service:requestApp(successfulOwner,"https://example.test/ok"))
assert(service:dispatch({"http_success","https://example.test/ok",successfulHandle},
    function(receivedOwner,method,url,handle)
        assert(receivedOwner==successfulOwner and method=="onHttpSuccess" and
            url=="https://example.test/ok" and handle==successfulHandle)
        return true
    end))
assert(closed==1 and not service:has("https://example.test/ok"),
    "a callback that claims a response owns its handle")

local unclaimedHandle={close=function() closed=closed+1 end}
assert(service:requestApp(successfulOwner,"https://example.test/unclaimed"))
assert(service:dispatch({"http_success","https://example.test/unclaimed",unclaimedHandle},
    function() return false end))
assert(closed==2,"unclaimed responses should be closed")

local failureHandle={close=function() closed=closed+1 end}
assert(service:requestApp(successfulOwner,"https://example.test/failure"))
assert(service:dispatch({"http_failure","https://example.test/failure","denied",failureHandle},
    function(_,method,url,message)
        assert(method=="onHttpFailure" and url=="https://example.test/failure" and message=="denied")
        return true
    end))
assert(closed==3,"failure response handles should be closed even when app callbacks claim them")

local systemErrors={}
local systemHandle={close=function() closed=closed+1 end}
local systemOwner={handleHttp=function(url,handle)
    assert(url=="https://example.test/system" and handle==systemHandle)
    return true
end}
assert(service:requestSystem(systemOwner,"https://example.test/system"))
assert(service:dispatch({"http_success","https://example.test/system",systemHandle},nil,
    function(message) systemErrors[#systemErrors+1]=message end))
assert(closed==3 and #systemErrors==0,"system callbacks may claim successful response handles")

local brokenSystem={handleHttp=function() error("service failure") end}
local brokenHandle={close=function() closed=closed+1 end}
assert(service:requestSystem(brokenSystem,"https://example.test/broken"))
assert(service:dispatch({"http_success","https://example.test/broken",brokenHandle},nil,
    function(message) systemErrors[#systemErrors+1]=message end))
assert(closed==4 and #systemErrors==1,"system callback errors should be logged and release handles")

assert(not service:dispatch({"http_success","https://example.test/unknown",{close=function() error("unknown handle") end}}),
    "unowned completion events should be ignored")

local unavailable=HttpService.new({}, {})
assert(not unavailable:requestApp({httpRequests={}},"https://example.test/offline"),
    "missing HTTP APIs should return an error without recording a request")

print("http service specs passed")
