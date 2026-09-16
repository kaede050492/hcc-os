return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local Canvas={}; Canvas.__index=Canvas
local function canvas(list,x,y,w,h,clip)
    return setmetatable({list=list,x=x,y=y,w=w,h=h,clip=intersect(box(x,y,w,h),clip or box(0,0,Driver.w,Driver.h)) or box(0,0,0,0)},Canvas)
end
function Canvas:getWidth() return self.w end
function Canvas:getHeight() return self.h end
function Canvas:clipping(x,y,w,h) return canvas(self.list,self.x+x,self.y+y,w,h,self.clip) end
function Canvas:filledRectangle(x,y,w,h,color)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    local r=intersect(box(self.x+x,self.y+y,w,h),self.clip)
    if r then self.list[#self.list+1]={kind="fill",bounds=r,color=color or P.panelBackground} end
end
function Canvas:clear(color) self:filledRectangle(0,0,self.w,self.h,color or P.windowBackground) end
function Canvas:pixel(x,y,color) self:filledRectangle(x,y,1,1,color) end
function Canvas:line(x1,y1,x2,y2,color)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local a,b,c,d=clipLine(self.x+x1,self.y+y1,self.x+x2,self.y+y2,self.clip)
    if a then self.list[#self.list+1]={kind="line",bounds=box(min(a,c),min(b,d),math.abs(c-a)+1,math.abs(d-b)+1),a=a,b=b,c=c,d=d,color=color or P.border} end
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
    if #out>0 then self.list[#self.list+1]={kind="text",bounds=box(start,y,width,height),value=table.concat(out),color=color or P.textPrimary,scale=scale} end
end
function Canvas:nativeImage(x,y,record,mode)
    if type(record)~="table" or not (finite(record.width) and finite(record.height)) then return false end
    local px,py=floor(self.x+x),floor(self.y+y)
    if mode=="center" or mode=="fit" then px=px+floor((self.w-record.width)/2); py=py+floor((self.h-record.height)/2) end
    if not Driver.nativeImageFits(record,px,py,self.clip) then return false end
    self.list[#self.list+1]={kind="native_image",bounds=box(px,py,record.width,record.height),record=record}
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
