-- HCC OS v1.5 bounded widget toolkit.
local W={}
local function add(app,kind,x,y,w,h,value,action)
 local hit={kind=kind,x=x,y=y,w=w,h=h,value=value,action=action or function() end}
 if app and app.win then app.win.buttons[#app.win.buttons+1]=hit end
 return hit
end
function W.panel(c,x,y,w,h,color,edge) c:filledRectangle(x,y,w,h,color); if edge~=false then c:rectangle(x,y,w,h,edge) end end
function W.label(c,x,y,value,color,scale) c:text(x,y,value,color,scale or 1) end
function W.button(app,c,x,y,w,label,action,p)
 p=p or {}; c:filledRectangle(x,y,w,16,p.panelBackground); c:rectangle(x,y,w,16,p.border); c:text(x+4,y+3,label,p.textPrimary); return add(app,"button",x,y,w,16,label,action)
end
function W.iconButton(app,c,x,y,size,draw,action,p) W.panel(c,x,y,size,size,p.panelBackground,p.border); if draw then draw(c,x+2,y+2,size-4) end; return add(app,"icon",x,y,size,size,nil,action) end
function W.textBox(app,c,x,y,w,value,p) W.panel(c,x,y,w,18,p.panelBackground,p.border); c:clipping(x+4,y+4,w-8,10):text(0,0,tostring(value or ""),p.textPrimary); return add(app,"textbox",x,y,w,18,value) end
function W.numberBox(app,c,x,y,w,value,p) return W.textBox(app,c,x,y,w,tostring(value or 0),p) end
function W.checkbox(app,c,x,y,label,value,action,p) W.panel(c,x,y,13,13,p.windowBackground,p.border); if value then c:filledRectangle(x+3,y+3,7,7,p.accent) end; c:text(x+18,y+2,label,p.textPrimary); return add(app,"checkbox",x,y,18+#label*6,14,value,action) end
function W.slider(app,c,x,y,w,value,minimum,maximum,action,p) minimum=minimum or 0; maximum=maximum or 1; value=math.max(minimum,math.min(maximum,value or minimum)); W.panel(c,x,y,w,8,p.windowBackground,p.border); c:filledRectangle(x+1,y+1,math.floor((w-2)*(value-minimum)/math.max(1,maximum-minimum)),6,p.accent); return add(app,"slider",x,y,w,10,value,action) end
function W.listView(app,c,x,y,w,h,rows,selected,p) local view=c:clipping(x,y,w,h); W.panel(view,0,0,w,h,p.windowBackground,p.border); for i,row in ipairs(rows or {}) do local yy=2+(i-1)*14; if yy+13>h then break end; if i==selected then view:filledRectangle(1,yy,w-2,13,p.panelBackground) end; view:text(4,yy+2,tostring(row),p.textPrimary) end; return add(app,"list",x,y,w,h,selected) end
function W.scrollView(c,x,y,w,h) return c:clipping(x,y,w,h) end
function W.dropdown(app,c,x,y,w,value,action,p) W.textBox(app,c,x,y,w,value,p); c:text(x+w-12,y+4,"v",p.accent); return add(app,"dropdown",x,y,w,18,value,action) end
function W.tabs(app,c,x,y,w,items,selected,action,p) local each=math.max(24,math.floor(w/math.max(1,#items))); for i,item in ipairs(items) do W.button(app,c,x+(i-1)*each,y,each-2,item,function() action(i) end,{panelBackground=i==selected and p.border or p.panelBackground,border=p.border,textPrimary=p.textPrimary}) end end
function W.contextMenu(app,c,x,y,w,items,p) local h=#items*18+2; W.panel(c,x,y,w,h,p.windowBackground,p.accent); for i,item in ipairs(items) do c:text(x+6,y+5+(i-1)*18,item.label or item[1],p.textPrimary); add(app,"menu",x+1,y+1+(i-1)*18,w-2,18,item,item.action or item[2]) end end
function W.dialog(c,x,y,w,h,title,message,p) W.panel(c,x,y,w,h,p.windowBackground,p.accent); c:filledRectangle(x+1,y+1,w-2,18,p.panelBackground); c:text(x+7,y+5,title,p.accent); c:paragraph(x+7,y+27,message,p.textPrimary,w-14,math.max(1,math.floor((h-34)/12))) end
function W.tooltip(c,x,y,text,p) local w=math.min(c.w-x,8+#tostring(text)*6); W.panel(c,x,y,w,16,p.panelBackground,p.border); c:text(x+4,y+3,text,p.textPrimary) end
function W.progress(c,x,y,w,h,value,limit,color,bg) limit=limit and limit>0 and limit or 1; value=math.max(0,math.min(limit,value or 0)); W.panel(c,x,y,w,h,bg,nil); if value>0 then c:filledRectangle(x+1,y+1,math.floor((w-2)*value/limit),math.max(1,h-2),color) end end
function W.progressBar(...) return W.progress(...) end
function W.graph(c,x,y,w,h,values,color,limit,p) W.panel(c,x,y,w,h,p.windowBackground,p.border); limit=limit or 1; for i=2,#values do local x1=x+1+math.floor((i-2)*(w-3)/math.max(1,#values-1)); local x2=x+1+math.floor((i-1)*(w-3)/math.max(1,#values-1)); local y1=y+h-2-math.floor(math.max(0,math.min(1,values[i-1]/limit))*(h-3)); local y2=y+h-2-math.floor(math.max(0,math.min(1,values[i]/limit))*(h-3)); c:line(x1,y1,x2,y2,color) end end
function W.splitter(app,c,x,y,w,h,vertical,action,p) c:filledRectangle(x,y,w,h,p.border); return add(app,"splitter",x,y,w,h,vertical,action) end
function W.icon(c,x,y,def,selected) if W.drawIcon then W.drawIcon(c,def,x,y,28,selected and "selected" or "normal") end end
function W.value(c,x,y,label,value,color,p) c:text(x,y,label,p.textSecondary); c:text(x+#label*6+5,y,value,color or p.textPrimary) end
return W
