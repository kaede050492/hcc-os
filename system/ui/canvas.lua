return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local Canvas={}; Canvas.__index=Canvas
local function canvas(list,x,y,w,h,clip,roundClip)
    return setmetatable({list=list,x=x,y=y,w=w,h=h,
        clip=intersect(box(x,y,w,h),clip or box(0,0,Driver.w,Driver.h)) or box(0,0,0,0),roundClip=roundClip},Canvas)
end
function Canvas:getWidth() return self.w end
function Canvas:getHeight() return self.h end
function Canvas:clipping(x,y,w,h) return canvas(self.list,self.x+x,self.y+y,w,h,self.clip,self.roundClip) end
function Canvas:roundedClipping(x,y,w,h,radius)
    local rect=box(self.x+x,self.y+y,w,h)
    return canvas(self.list,rect.x,rect.y,rect.w,rect.h,self.clip,{rect=rect,radius=radius})
end
local function appendClippedFill(list,area,color,roundClip)
    if not roundClip or not geometry or geometry.roundedContainsRect(roundClip.rect,roundClip.radius,area) then
        list[#list+1]={kind="fill",bounds=area,color=color}
        return
    end
    local runTop,runLeft,runRight
    local function flush(bottom)
        if runTop then list[#list+1]={kind="fill",bounds=box(runLeft,runTop,runRight-runLeft,bottom-runTop),color=color} end
        runTop=nil
    end
    for y=area.y,area.y+area.h-1 do
        local left,right
        if geometry then left,right=geometry.roundedRectRow(roundClip.rect,roundClip.radius,y) end
        if left then left=max(left,area.x); right=min(right,area.x+area.w) end
        if not left or right<=left then
            flush(y)
        elseif runTop and left==runLeft and right==runRight then
            -- Extend a run while the rounded clipping edge remains unchanged.
        else
            flush(y); runTop,runLeft,runRight=y,left,right
        end
    end
    flush(area.y+area.h)
end
local function appendClippedLine(list,a,b,c,d,color,roundClip)
    local bounds=box(min(a,c),min(b,d),math.abs(c-a)+1,math.abs(d-b)+1)
    if not roundClip or not geometry or geometry.roundedContainsRect(roundClip.rect,roundClip.radius,bounds) then
        list[#list+1]={kind="line",bounds=bounds,a=a,b=b,c=c,d=d,color=color}
        return
    end
    local dx,dy=c-a,d-b; local steps=max(1,math.ceil(max(math.abs(dx),math.abs(dy))))
    local firstX,firstY,lastX,lastY
    local function flush()
        if firstX then
            local r=box(min(firstX,lastX),min(firstY,lastY),math.abs(lastX-firstX)+1,math.abs(lastY-firstY)+1)
            list[#list+1]={kind="line",bounds=r,a=firstX,b=firstY,c=lastX,d=lastY,color=color}
            firstX=nil
        end
    end
    for i=0,steps do
        local x=floor(a+dx*i/steps+0.5); local y=floor(b+dy*i/steps+0.5)
        if geometry.roundedContains(roundClip.rect,roundClip.radius,x,y) then
            if not firstX then firstX,firstY=x,y end
            lastX,lastY=x,y
        else flush() end
    end
    flush()
end
function Canvas:filledRectangle(x,y,w,h,color)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    local r=intersect(box(self.x+x,self.y+y,w,h),self.clip)
    if r then appendClippedFill(self.list,r,color or P.panelBackground,self.roundClip) end
end
function Canvas:clear(color) self:filledRectangle(0,0,self.w,self.h,color or P.windowBackground) end
function Canvas:pixel(x,y,color) self:filledRectangle(x,y,1,1,color) end
function Canvas:line(x1,y1,x2,y2,color)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local a,b,c,d=clipLine(self.x+x1,self.y+y1,self.x+x2,self.y+y2,self.clip)
    if a then appendClippedLine(self.list,a,b,c,d,color or P.border,self.roundClip) end
end
function Canvas:rectangle(x,y,w,h,color)
    self:line(x,y,x+w-1,y,color); self:line(x,y+h-1,x+w-1,y+h-1,color)
    self:line(x,y,x,y+h-1,color); self:line(x+w-1,y,x+w-1,y+h-1,color)
end
function Canvas:text(x,y,s,color,scale)
    if not (finite(x) and finite(y)) then return end
    scale=finite(scale) and floor(clamp(scale,1,4)) or 1
    x,y=floor(self.x+x),floor(self.y+y); s=ascii(s)
    -- ASCII native font is 8 pixels tall. Reserve 9 to include a safe gutter.
    local height=9*scale
    if y<self.clip.y or y+height>self.clip.y+self.clip.h then return end
    local start,width,out=x,0,{}
    for i=1,#s do
        local ch=s:sub(i,i); local cw=Driver.measure(ch,scale)
        if x+cw>self.clip.x+self.clip.w then break end
        if x>=self.clip.x then
            if #out==0 then start=x end
            out[#out+1]=ch; width=width+cw
        end
        x=x+cw
    end
    if #out>0 then
        local bounds=box(start,y,width,height)
        if not self.roundClip or not geometry or geometry.roundedContainsRect(self.roundClip.rect,self.roundClip.radius,bounds) then
            self.list[#self.list+1]={kind="text",bounds=bounds,value=table.concat(out),color=color or P.textPrimary,scale=scale}
        end
    end
end
function Canvas:nativeImage(x,y,record,mode)
    if type(record)~="table" or not (finite(record.width) and finite(record.height)) then return false end
    local px,py=floor(self.x+x),floor(self.y+y)
    if mode=="center" or mode=="fit" then px=px+floor((self.w-record.width)/2); py=py+floor((self.h-record.height)/2) end
    local bounds=box(px,py,record.width,record.height)
    if not intersect(bounds,self.clip) then return false end
    if self.roundClip and geometry and not geometry.roundedContainsRect(self.roundClip.rect,self.roundClip.radius,bounds) then return false end
    self.list[#self.list+1]={kind="native_image",bounds=bounds,record=record,clip=self.clip}
    return true
end
function Canvas:paragraph(x,y,s,color,maxWidth,maxRows)
    local width=maxWidth or self.w-x; local row=""; local count=0
    for word in (ascii(s).." "):gmatch("(%S+)%s+") do
        if Driver.measure(row..word)>width and row~="" then
            self:text(x,y+count*12,row,color); count=count+1; row=""
            if count>=(maxRows or 10) then return end
        end
        row=row..word.." "
    end
    self:text(x,y+count*12,row,color)
end
E.Canvas=Canvas; E.canvas=canvas

end
