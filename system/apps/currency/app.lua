-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
local _ENV=env
local fileStorage=E.context and E.context.fileService
local function currencySnapshot()
    local snapshot={}
    for key,value in pairs(currencyData) do
        if type(value)=="table" then
            local list={}
            for index,item in pairs(value) do
                if type(item)=="table" then
                    local copy={}; for itemKey,itemValue in pairs(item) do copy[itemKey]=itemValue end
                    list[index]=copy
                else list[index]=item end
            end
            snapshot[key]=list
        else snapshot[key]=value end
    end
    return snapshot
end
local function currencyRestore(snapshot)
    for key in pairs(currencyData) do currencyData[key]=nil end
    for key,value in pairs(snapshot) do currencyData[key]=value end
end
local function saveCurrencyMutation(snapshot)
    local ok,err=currencySave()
    if not ok then currencyRestore(snapshot); errorBox(err); return false end
    return true
end
local Currency={}
function Currency:init()
    self.screen="calc"; self.compactView="calc"; self.compactMode=false; self.selected=1; self.coinSelected=1; self.sortMode="recent"; self.search=""
    self.side="BUY"; self.inputMode="quantity"; self.input="1"; self.fields={quantity="1",money="0",total="0"}
    self.calcLeft=nil; self.calcOp=nil; self.calcResult=nil; self.convertResult=nil; self:refreshItems()
end
function Currency:interval() return 2 end
function Currency:refreshItems()
    local list={}; local query=self.search:lower()
    for i,item in ipairs(currencyData.items) do
        if query=="" or item.id:lower():find(query,1,true) or item.name:lower():find(query,1,true) then list[#list+1]=i end
    end
    local recent={}; for i,id in ipairs(currencyData.recent) do recent[id]=i end
    table.sort(list,function(a,b)
        local aa,bb=currencyData.items[a],currencyData.items[b]
        if self.sortMode=="favorite" and aa.favorite~=bb.favorite then return aa.favorite end
        if self.sortMode=="price" then return (currencyItemValue(aa,"buy") or math.huge)<(currencyItemValue(bb,"buy") or math.huge) end
        if self.sortMode=="recent" and (recent[aa.id] or 9999)~=(recent[bb.id] or 9999) then return (recent[aa.id] or 9999)<(recent[bb.id] or 9999) end
        return aa.name:lower()<bb.name:lower()
    end)
    self.visibleItems=list; self.selected=clamp(self.selected,1,max(1,#list))
end
function Currency:selectedItem() local i=self.visibleItems and self.visibleItems[self.selected]; return i and currencyData.items[i] end
function Currency:choose(index)
    if not self.visibleItems[index] then return end
    self.selected=index; local item=self:selectedItem(); if not item then return end
    local recent={item.id}; for _,id in ipairs(currencyData.recent) do if id~=item.id and #recent<12 then recent[#recent+1]=id end end
    currencyData.recent=recent; self.fields.quantity="1"; self.inputMode="quantity"; self.input="1"; self.convertResult=nil
    mark(self.win)
end
function Currency:selectItemId(id)
    id=ascii(id)
    self.screen="calc"; self.compactView="calc"; self.search=""; self:refreshItems()
    for i,dataIndex in ipairs(self.visibleItems) do
        if currencyData.items[dataIndex].id==id then self:choose(i); return true end
    end
    self.search=id; self:refreshItems(); mark(self.win); return false
end
function Currency:setInputMode(mode)
    self.fields[self.inputMode]=self.input; self.inputMode=mode; self.input=self.fields[mode] or "0"; mark(self.win)
end
function Currency:syncInput()
    self.fields[self.inputMode]=self.input
end
function Currency:keypad(token)
    if token=="C" then self.input="0"
    elseif token=="B" then self.input=#self.input>1 and self.input:sub(1,-2) or "0"
    elseif token=="." then if currencyData.allowDecimals and not self.input:find("%.",1,true) then self.input=self.input.."." end
    elseif token=="ENTER" then
        self:syncInput(); if self.calcResult then self.input=tostring(self.calcResult); self:syncInput(); self.calcResult=nil end
    elseif token=="+" or token=="-" or token=="*" or token=="/" or token=="%" then
        local n=tonumber(self.input:gsub(",","")); if not n then return end
        if self.calcLeft==nil then self.calcLeft=n else self:calculateOp(n) end; self.calcOp=token; self.input="0"
    elseif token=="=" then if self.calcLeft and self.calcOp then self:calculateOp(tonumber(self.input) or 0); self.input=tostring(self.calcResult or 0); self.calcLeft=nil; self.calcOp=nil end
    else
        if self.input=="0" then self.input="" end
        if #self.input<18 then self.input=self.input..token end
    end
    self:syncInput(); mark(self.win)
end
function Currency:calculateOp(right)
    local left=self.calcLeft; local op=self.calcOp; local result
    if op=="+" then result=left+right elseif op=="-" then result=left-right
    elseif op=="*" then result=left*right elseif op=="/" and right~=0 then result=left/right
    elseif op=="%" and right~=0 then result=left%right else return end
    if finite(result) then self.calcResult=result end
end
function Currency:stackInput()
    local item=self:selectedItem(); if not item then errorBox("Register or select an item first"); return end
    askFields("Stacks to items",{{"Stacks","1"},{"Remainder items","0"}},function(values)
        local stacks=currencyInteger(values[1]); local rem=currencyInteger(values[2])
        if not stacks or not rem or rem>=item.stack then errorBox("Use whole stacks and a remainder smaller than stack size"); return end
        local total=currencyMultiply(stacks,item.stack)
        if not total or total>999999999999-rem then errorBox("Item quantity is too large"); return end
        self.fields.quantity=tostring(total+rem); self:setInputMode("quantity"); self.input=self.fields.quantity; mark(self.win)
    end)
end
function Currency:convert()
    local coinNames={}; for _,coin in ipairs(currencyData.coins) do coinNames[#coinNames+1]=coin.name end
    if #coinNames<2 then errorBox("Register at least two coins first"); return end
    askFields("Coin conversion",{{"From coin",coinNames[1]},{"Amount", "1"},{"To coin",coinNames[2]}},function(values)
        local from,to=currencyFindCoin(values[1]),currencyFindCoin(values[3]); local count=currencyInteger(values[2])
        if not from or not to or not count then errorBox("Unknown coin or invalid amount"); return end
        local amount=currencyMultiply(count,currencyCoinValue(from))
        if not amount then errorBox("Conversion amount exceeds the safe numeric range"); return end
        local result,remain=currencyBreakdown(amount)
        self.convertResult=values[2].." "..from.name.." = "..currencyBreakdownText(amount)
        if remain>0 then self.convertResult=self.convertResult.." / remainder "..currencyFormat(remain,currencyData.allowDecimals) end
        mark(self.win)
    end)
end
local function askCurrencyFields(title,fields,callback,index,values)
    index=index or 1; values=values or {}
    if not fields[index] then callback(values); return end
    local field=fields[index]
    dialog(title,field[1],{"OK","Cancel"},function(buttonValue,value)
        if buttonValue~="OK" then return end
        values[index]=value; askCurrencyFields(title,fields,callback,index+1,values)
    end,tostring(field[2] or ""))
end
askFields=askCurrencyFields
function Currency:addCoin(edit)
    local old=edit and currencyData.coins[self.coinSelected]
    local fields={{"Coin name",old and old.name or ""},{"Value in base units",old and old.unit or "1"}}
    askFields(edit and "Edit coin" or "Add coin",fields,function(values)
        local coinName=ascii(values[1])
        if not currencyValidName(values[1]) or not currencyValidName(coinName) or currencyFindCoin(coinName) and (not old or old.name~=coinName) then errorBox("Coin name is empty or already used"); return end
        local value=currencyFixed(values[2],currencyData.allowDecimals)
        if not value or value<=0 then errorBox("Value must be a positive number"); return end
        if not old and #currencyData.coins>=currencyMaxCoins then errorBox("Coin limit reached"); return end
        local snapshot=currencySnapshot()
        if old then old.name=coinName; old.unit=values[2] else currencyData.coins[#currencyData.coins+1]={name=coinName,unit=values[2]} end
        if currencyData.baseCoin=="" then currencyData.baseCoin=coinName end
        if saveCurrencyMutation(snapshot) then notify("Coin saved",P.success) end
        mark(self.win)
    end)
end
function Currency:addItem(edit)
    local old=edit and self:selectedItem()
    local fields={{"Item ID",old and old.id or "minecraft:item"},{"Display name",old and old.name or "Item"},
        {"Buy price",old and old.buy or ""},{"Sell price",old and old.sell or ""},{"Stack size",old and tostring(old.stack) or "64"}}
    askFields(edit and "Edit item" or "Add item",fields,function(values)
        local id=ascii(values[1])
        local name=ascii(values[2]~="" and values[2] or values[1])
        if not currencyValidName(values[1]) or not currencyValidName(id) then errorBox("Item ID is empty or invalid"); return end
        if not currencyValidName(values[2]~="" and values[2] or values[1]) or not currencyValidName(name) then errorBox("Display name must be 1..48 printable characters"); return end
        local stack=currencyInteger(values[5]); local buy=values[3]; local sell=values[4]
        if (buy~="" and not currencyFixed(buy,currencyData.allowDecimals)) or (sell~="" and not currencyFixed(sell,currencyData.allowDecimals)) then errorBox("Price is invalid"); return end
        if not stack or stack<1 or stack>999999 then errorBox("Stack size must be 1..999999"); return end
        for _,item in ipairs(currencyData.items) do if item~=old and item.id==id then errorBox("Item ID already used"); return end end
        if not old and #currencyData.items>=currencyMaxItems then errorBox("Item limit reached"); return end
        local snapshot=currencySnapshot()
        if old then old.id=id; old.name=name; old.buy=buy; old.sell=sell; old.stack=stack
        else currencyData.items[#currencyData.items+1]={id=id,name=name,buy=buy,sell=sell,stack=stack,favorite=false} end
        if saveCurrencyMutation(snapshot) then notify("Item saved",P.success) end
        self:refreshItems(); mark(self.win)
    end)
end
function Currency:deleteItem()
    local item=self:selectedItem(); if not item then return end
    dialog("Delete item","Delete "..item.id.." from price dictionary?",{"Yes","No"},function(value)
        if value~="Yes" then return end
        local snapshot=currencySnapshot()
        for i,v in ipairs(currencyData.items) do if v==item then table.remove(currencyData.items,i); break end end
        if saveCurrencyMutation(snapshot) then notify("Item deleted",P.warning) end
        self:refreshItems(); mark(self.win)
    end)
end
function Currency:toggleFavorite()
    local item=self:selectedItem(); if item then local snapshot=currencySnapshot(); item.favorite=not item.favorite; saveCurrencyMutation(snapshot); self:refreshItems(); mark(self.win) end
end
function Currency:searchDialog()
    dialog("Search items","ID or display name; empty shows all",{"OK","Clear"},function(value,text)
        self.search=value=="Clear" and "" or text; self:refreshItems(); mark(self.win)
    end,self.search)
end
function Currency:sort()
    self.sortMode=({recent="name",name="price",price="favorite",favorite="recent"})[self.sortMode] or "recent"; self:refreshItems(); mark(self.win)
end
function Currency:editSettings()
    askFields("Currency settings",{{"Base coin",currencyData.baseCoin},{"Decimals on? yes/no",currencyData.allowDecimals and "yes" or "no"},{"Rounding floor/round/ceil/exact",currencyData.rounding}},function(values)
        local decimals=values[2]:lower(); local rounding=values[3]:lower()
        if decimals~="yes" and decimals~="no" then errorBox("Decimals must be yes or no"); return end
        if not ({floor=true,round=true,ceil=true,exact=true})[rounding] then errorBox("Rounding must be floor, round, ceil or exact"); return end
        if values[1]~="" and not currencyFindCoin(values[1]) then errorBox("Base coin does not exist"); return end
        local snapshot=currencySnapshot()
        currencyData.baseCoin=values[1]; currencyData.allowDecimals=decimals=="yes"; currencyData.rounding=rounding
        if saveCurrencyMutation(snapshot) then notify("Currency settings saved",P.success) end
        mark(self.win)
    end)
end
function Currency:csvExport()
    if not fileStorage then errorBox("Safe file storage is unavailable"); return end
    local lines={"item_id,name,buy,sell,stack"}
    for _,item in ipairs(currencyData.items) do
        lines[#lines+1]=table.concat({currencyCsvField(item.id),currencyCsvField(item.name),
            currencyCsvField(item.buy),currencyCsvField(item.sell),currencyCsvField(item.stack)},",")
    end
    local ok,err=fileStorage:writeTextAtomic(currencyCsvPath,table.concat(lines,"\n").."\n",1048576)
    if ok then notify("CSV exported: "..currencyCsvPath,P.success) else errorBox(err) end
end
function Currency:csvImport()
    if not fileStorage then errorBox("Safe file storage is unavailable"); return end
    local content,readError=fileStorage:readText(currencyCsvPath,1048576)
    if not content then errorBox(readError); return end
    local originalItems=currencyData.items
    local ok,err=pcall(function()
        local first=true
        local importedItems={}
        for i,item in ipairs(originalItems) do
            local copy={}; for key,value in pairs(item) do copy[key]=value end
            importedItems[i]=copy
        end
        currencyData.items=importedItems
        for line in (content.."\n"):gmatch("([^\r\n]+)") do
            if first then
                local header=currencyCsvSplit(line)
                if not header or header[1]~="item_id" or header[2]~="name" or header[3]~="buy" or header[4]~="sell" or header[5]~="stack" then
                    error("CSV header is invalid")
                end
                first=false
            else
                local p=currencyCsvSplit(line)
                if p and #p>=5 then
                    local id=ascii(p[1])
                    local rawName=p[2]~="" and p[2] or p[1]
                    local name=ascii(rawName)
                    local stack=currencyInteger(p[5] or "64")
                    if currencyValidName(p[1]) and currencyValidName(id) and currencyValidName(rawName) and currencyValidName(name) and stack and stack>=1 and stack<=999999 and (p[3]=="" or currencyFixed(p[3],currencyData.allowDecimals)) and (p[4]=="" or currencyFixed(p[4],currencyData.allowDecimals)) then
                        local item=currencyItemById(id); if item then item.name=name; item.buy=p[3]; item.sell=p[4]; item.stack=stack
                        elseif #currencyData.items<currencyMaxItems then currencyData.items[#currencyData.items+1]={id=id,name=name,buy=p[3],sell=p[4],stack=stack,favorite=false}
                        else error("Currency item limit reached") end
                    end
                end
            end
        end
        if first then error("CSV file is empty") end
        local saved,e=currencySave(); if not saved then error(e) end
    end)
    if ok then self:refreshItems(); notify("CSV imported: "..currencyCsvPath,P.success); mark(self.win) else currencyData.items=originalItems; errorBox(err) end
end
function Currency:calcValues()
    local item=self:selectedItem(); local unit=item and currencyItemValue(item,self.side=="BUY" and "buy" or "sell")
    local qty=currencyInteger(self.fields.quantity or "0") or 0; local money=currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0
    local total=0
    if unit then total=currencyMultiply(unit,qty) end
    if self.inputMode=="total" then total=currencyFixed(self.fields.total or "0",currencyData.allowDecimals) or 0 end
    local shownUnit=unit
    if self.inputMode=="total" and qty>0 then shownUnit=total/qty end
    local stack=item and item.stack or 64
    local maxItems=unit and unit>0 and floor(money/unit) or 0
    local buy=currencyItemValue(item,"buy"); local sell=currencyItemValue(item,"sell")
    local purchase=buy and currencyMultiply(buy,qty) or nil; local revenue=sell and currencyMultiply(sell,qty) or nil; local profit=purchase and revenue and revenue-purchase or nil
    local profitItem=buy and sell and sell-buy or nil
    return {item=item,unit=shownUnit,priceUnit=unit,qty=qty,total=total,stack=stack,stacks=floor(qty/stack),remainder=qty%stack,maxItems=maxItems,maxStacks=floor(maxItems/stack),remaining=money-maxItems*(unit or 0),purchase=purchase,revenue=revenue,profit=profit,profitItem=profitItem,profitStack=profitItem and currencyMultiply(profitItem,stack) or nil,margin=profit and purchase>0 and profit/purchase*100 or nil}
end
function Currency:onKey(k)
    if self.compactMode then
        if self.compactView=="coins" or self.screen=="coins" then
            if k==keys.up then self.coinSelected=max(1,self.coinSelected-1)
            elseif k==keys.down then self.coinSelected=min(max(1,#currencyData.coins),self.coinSelected+1)
            elseif k==keys.enter then self:addCoin(true)
            elseif k==keys.delete then self:deleteCoin()
            elseif k==keys.escape then self.compactView="calc"; self.screen="calc" end
        elseif self.compactView=="items" then
            if k==keys.up then self.selected=max(1,self.selected-1); self:choose(self.selected)
            elseif k==keys.down then self.selected=min(#self.visibleItems,self.selected+1); self:choose(self.selected)
            elseif k==keys.pageUp then self.selected=max(1,self.selected-6); self:choose(self.selected)
            elseif k==keys.pageDown then self.selected=min(#self.visibleItems,self.selected+6); self:choose(self.selected)
            elseif k==keys.enter then self.compactView="calc" end
        elseif k==keys.b then self.side=self.side=="BUY" and "SELL" or "BUY"
        elseif k==keys.enter then self:keypad("ENTER") end
        mark(self.win); return
    end
    if self.screen=="coins" then
        if k==keys.up then self.coinSelected=max(1,self.coinSelected-1) elseif k==keys.down then self.coinSelected=min(#currencyData.coins,self.coinSelected+1)
        elseif k==keys.enter then self:addCoin(true) elseif k==keys.delete then self:deleteCoin() elseif k==keys.escape then self.screen="calc" end
    elseif k==keys.up then self.selected=max(1,self.selected-1); self:choose(self.selected)
    elseif k==keys.down then self.selected=min(#self.visibleItems,self.selected+1); self:choose(self.selected)
    elseif k==keys.pageUp then self.selected=max(1,self.selected-6); self:choose(self.selected)
    elseif k==keys.pageDown then self.selected=min(#self.visibleItems,self.selected+6); self:choose(self.selected)
    elseif k==keys.enter and self.inputMode=="quantity" then self:keypad("ENTER")
    elseif k==keys.escape then self.screen="calc"; mark(self.win)
    elseif k==keys.b then self.side=self.side=="BUY" and "SELL" or "BUY"; mark(self.win)
    elseif k==keys.s then self:stackInput()
    end
    mark(self.win)
end
function Currency:deleteCoin()
    local coin=currencyData.coins[self.coinSelected]; if not coin then return end
    dialog("Delete coin","Delete "..coin.name.."?",{"Yes","No"},function(value)
        if value=="Yes" then
            local snapshot=currencySnapshot()
            table.remove(currencyData.coins,self.coinSelected); if currencyData.baseCoin==coin.name then currencyData.baseCoin="" end
            if saveCurrencyMutation(snapshot) then notify("Coin deleted",P.warning) end
            self.coinSelected=clamp(self.coinSelected,1,max(1,#currencyData.coins)); mark(self.win)
        end
    end)
end
function Currency:onMouse(kind,x,y,b)
    if self.compactMode then
        if kind=="scroll" then
            if self.compactView=="coins" then self.coinSelected=clamp(self.coinSelected+b,1,max(1,#currencyData.coins))
            else self.selected=clamp(self.selected+b,1,max(1,#self.visibleItems)); if self.compactView=="items" then self:choose(self.selected) end end
            mark(self.win); return
        elseif kind=="click" and self.compactView=="items" and self.compactListTop and y>=self.compactListTop and y<self.compactListBottom then
            local first=max(1,min(self.selected-1,max(1,#self.visibleItems-2)))
            local index=first+floor((y-self.compactListTop)/12)
            if self.visibleItems[index] then self:choose(index) end
            return
        elseif kind=="click" and self.compactView=="coins" and self.compactListTop and y>=self.compactListTop and y<self.compactListBottom then
            local first=max(1,min(self.coinSelected-1,max(1,#currencyData.coins-2)))
            local index=first+floor((y-self.compactListTop)/12)
            if currencyData.coins[index] then self.coinSelected=index; mark(self.win) end
            return
        end
        return
    end
    if self.screen=="coins" then
        if kind=="scroll" then self.coinSelected=clamp(self.coinSelected+b,1,max(1,#currencyData.coins)); mark(self.win)
        elseif kind=="click" and y>=37 and y<self.win.h-42 then local i=1+floor((y-37)/16); if currencyData.coins[i] then self.coinSelected=i; mark(self.win) end end
        return
    end
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,max(1,#self.visibleItems)); self:choose(self.selected); return end
    if kind~="click" then return end
    if y>=34 and y<self.win.h-80 and x<165 then local i=1+floor((y-34)/17); if self.visibleItems[i] then self:choose(i) end; return end
    for _,item in ipairs(self.win.buttons) do if inside(item,x,y) then local ok,err=pcall(item.action); if not ok then errorBox(err) end; return end end
end
local function currencyButton(app,c,x,y,w,label,fn) button(app,c,x,y,w,label,fn) end
local function compactButton(app,c,x,y,w,h,label,fn,selected)
    c:filledRectangle(x,y,w,h,selected and P.menuSelection or P.panelBackground)
    c:rectangle(x,y,w,h,selected and P.accent or P.border)
    c:clipping(x+1,y+max(0,floor((h-8)/2)),max(1,w-2),max(1,min(8,h))):text(0,0,label,selected and P.textPrimary or P.textSecondary)
    app.win.buttons[#app.win.buttons+1]={x=x,y=y,w=w,h=h,action=fn}
end
function Currency:drawCompact(c)
    local narrow=c.w<243
    local tabs=narrow and {{"items","ITM"},{"calc","CAL"},{"results","OUT"},{"coins","COI"}} or
        {{"items","ITEMS",57},{"calc","CALC",52},{"results","RESULTS",64},{"coins","COINS",57}}
    local tabWidth=narrow and max(24,floor((c.w-17)/4)) or nil
    local x=4
    for _,tab in ipairs(tabs) do
        local view,label=tab[1],tab[2]
        local width=tabWidth or tab[3]
        compactButton(self,c,x,2,width,12,label,function()
            self.compactView=view; self.screen=view=="coins" and "coins" or "calc"; mark(self.win)
        end,self.compactView==view)
        x=x+width+3
    end
    local item=self:selectedItem()
    if self.compactView=="calc" then
        local modes={{"QTY","quantity"},{"MNY","money"},{"TOT","total"},{self.side=="BUY" and "BUY" or "SEL","side"}}
        local modeGap=3; local modeWidth=floor((c.w-10-modeGap*3)/4)
        for i,mode in ipairs(modes) do
            local modeLabel,modeId=mode[1],mode[2]
            local bx=5+(i-1)*(modeWidth+modeGap)
            compactButton(self,c,bx,16,modeWidth,9,modeLabel,function()
                if modeId=="side" then self.side=self.side=="BUY" and "SELL" or "BUY" else self:setInputMode(modeId) end
                mark(self.win)
            end,modeId~="side" and self.inputMode==modeId)
        end
        c:filledRectangle(5,26,c.w-10,9,P.inputBackground or P.panelBackground)
        c:clipping(8,26,c.w-16,9):text(0,0,shortText(self.input or "0",max(1,floor((c.w-16)/8))),P.textPrimary)
        local keypad={{"7","8","9","/","*"},{"4","5","6","-","+"},{"1","2","3","00","000"},{"0",".","B","C","="}}
        local gap=3; local columns=5; local buttonWidth=floor((c.w-10-gap*(columns-1))/columns)
        local buttonHeight=max(8,min(11,floor((c.h-36)/4)))
        for row,values in ipairs(keypad) do for column,label in ipairs(values) do
            local bx=5+(column-1)*(buttonWidth+gap); local by=36+(row-1)*buttonHeight
            compactButton(self,c,bx,by,buttonWidth,buttonHeight,label,function() self:keypad(label) end)
        end end
    elseif self.compactView=="items" then
        c:text(5,17,string.format("%d/%d  %s",#self.visibleItems>0 and self.selected or 0,#self.visibleItems,self.sortMode),P.textSecondary)
        local first=max(1,min(self.selected-1,max(1,#self.visibleItems-2)))
        local y=c.h-13; self.compactListTop=29
        local rows=max(0,floor((y-29)/12))
        self.compactListBottom=self.compactListTop+rows*12
        for row=0,rows-1 do
            local index=first+row
            local dataIndex=self.visibleItems[index]; local entry=dataIndex and currencyData.items[dataIndex]
            if entry then
                local y=29+row*12
                if index==self.selected then c:filledRectangle(4,y,c.w-8,11,P.panelBackground) end
                c:clipping(7,y+1,c.w-14,10):text(0,0,shortText(entry.name,42),P.textPrimary)
            end
        end
        local widths=c.w<205 and {floor((c.w-17)/4),floor((c.w-17)/4),floor((c.w-17)/4),floor((c.w-17)/4)} or {44,44,38,58}
        local controls={{"ADD",widths[1],function() self:addItem(false) end},{"EDIT",widths[2],function() self:addItem(true) end},{"DEL",widths[3],function() self:deleteItem() end},{c.w<205 and "FIND" or "SEARCH",widths[4],function() self:searchDialog() end}}
        local bx=4
        for _,control in ipairs(controls) do compactButton(self,c,bx,y,control[2],12,control[1],control[3]); bx=bx+control[2]+3 end
    elseif self.compactView=="coins" then
        c:clipping(5,17,c.w-10,10):text(0,0,"BASE: "..(currencyData.baseCoin=="" and "NOT SET" or currencyData.baseCoin),P.textSecondary)
        local first=max(1,min(self.coinSelected-1,max(1,#currencyData.coins-2)))
        local y=c.h-13; self.compactListTop=29
        local rows=max(0,floor((y-29)/12))
        self.compactListBottom=self.compactListTop+rows*12
        for row=0,rows-1 do
            local index=first+row
            local coin=currencyData.coins[index]
            if coin then
                local y=29+row*12
                if index==self.coinSelected then c:filledRectangle(4,y,c.w-8,11,P.panelBackground) end
                c:clipping(7,y+1,c.w-14,10):text(0,0,shortText(coin.name.."  "..currencyFormat(currencyCoinValue(coin),currencyData.allowDecimals),42),P.textPrimary)
            end
        end
        local widths=c.w<205 and {floor((c.w-17)/4),floor((c.w-17)/4),floor((c.w-17)/4),floor((c.w-17)/4)} or {44,44,38,50}
        local controls={{"ADD",widths[1],function() self:addCoin(false) end},{"EDIT",widths[2],function() self:addCoin(true) end},{"DEL",widths[3],function() self:deleteCoin() end},{"BASE",widths[4],function()
            local coin=currencyData.coins[self.coinSelected]
            if coin then local snapshot=currencySnapshot(); currencyData.baseCoin=coin.name; saveCurrencyMutation(snapshot); mark(self.win) end
        end}}
        local bx=4
        for _,control in ipairs(controls) do compactButton(self,c,bx,y,control[2],12,control[1],control[3]); bx=bx+control[2]+3 end
    else
        local values=self:calcValues()
        local lines={
            (item and item.name or "No item selected"),
            "UNIT "..(values.unit and currencyFormat(values.unit,currencyData.allowDecimals) or "-").."  QTY "..values.qty,
            "TOTAL "..currencyFormat(values.total,currencyData.allowDecimals).."  STACKS "..values.stacks,
            "BUDGET "..currencyFormat(currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0,currencyData.allowDecimals),
            "MAX ITEMS "..values.maxItems.."  REMAIN "..currencyFormat(values.remaining,currencyData.allowDecimals),
            "PROFIT "..(values.profit and currencyFormat(values.profit,currencyData.allowDecimals) or "-")
        }
        local rows=max(1,min(#lines,floor((c.h-18)/10)))
        for index=1,rows do c:clipping(6,18+(index-1)*10,c.w-12,10):text(0,0,shortText(lines[index],max(1,floor((c.w-12)/8))),index==1 and P.accent or P.textPrimary) end
    end
end
function Currency:drawCoins(c)
    c:text(6,6,"COIN TYPES / BASE: "..(currencyData.baseCoin=="" and "NOT SET" or currencyData.baseCoin),P.accent)
    c:text(6,21,"Value is stored in user-defined base units",P.textSecondary)
    for i,coin in ipairs(currencyData.coins) do
        local y=37+(i-1)*16; if i==self.coinSelected then c:filledRectangle(5,y,c.w-10,15,P.panelBackground) end
        c:text(9,y+3,coin.name,P.textPrimary); c:text(c.w-115,y+3,currencyFormat(currencyCoinValue(coin),currencyData.allowDecimals),P.accent)
    end
    currencyButton(self,c,6,c.h-38,55,"ADD",function() self:addCoin(false) end)
    currencyButton(self,c,65,c.h-38,55,"EDIT",function() self:addCoin(true) end)
    currencyButton(self,c,124,c.h-38,55,"DEL",function() self:deleteCoin() end)
    currencyButton(self,c,183,c.h-38,65,"BASE",function()
        local coin=currencyData.coins[self.coinSelected]
        if coin then local snapshot=currencySnapshot(); currencyData.baseCoin=coin.name; saveCurrencyMutation(snapshot); mark(self.win) end
    end)
    currencyButton(self,c,252,c.h-38,60,"BACK",function() self.screen="calc"; mark(self.win) end)
end
function Currency:draw(c)
    self.compactMode=c.w<500 or c.h<200
    if self.compactMode then self.screen=self.compactView=="coins" and "coins" or "calc"; self:drawCompact(c); return end
    if self.screen=="coins" then self:drawCoins(c); return end
    local left=164; local mid=188; local right=max(130,c.w-left-mid-10)
    c:filledRectangle(0,0,left,c.h,P.windowBackground); c:line(left,0,left,c.h,P.border); c:line(left+mid,0,left+mid,c.h,P.border)
    c:text(5,5,"ITEMS",P.accent); c:text(5,19,self.search=="" and "ALL" or ("SEARCH: "..self.search),P.textSecondary)
    local rows=max(1,floor((c.h-89)/17));
    if self.selected<1 then self.selected=1 end
    for row=0,rows-1 do local idx=self.selected-rows+1+row; if idx<1 then idx=row+1 end; local dataIndex=self.visibleItems[idx]; local item=dataIndex and currencyData.items[dataIndex]
        if item then local y=34+row*17; if idx==self.selected then c:filledRectangle(3,y,left-7,16,P.panelBackground) end
            local markText=item.favorite and "* " or "  "; local name=item.name:sub(1,20); c:text(7,y+3,markText..name,item.favorite and P.warning or P.textPrimary)
            c:text(7,y+11,item.id:sub(1,23),P.textSecondary)
        end
    end
    c:text(5,c.h-52,string.format("%d/%d  %s",#self.visibleItems>0 and self.selected or 0,#self.visibleItems,self.sortMode),P.textSecondary)
    currencyButton(self,c,4,c.h-35,36,"ADD",function() self:addItem(false) end)
    currencyButton(self,c,44,c.h-35,40,"EDIT",function() self:addItem(true) end)
    currencyButton(self,c,88,c.h-35,36,"DEL",function() self:deleteItem() end)
    currencyButton(self,c,128,c.h-35,34,"FAV",function() self:toggleFavorite() end)
    currencyButton(self,c,4,c.h-17,50,"SEARCH",function() self:searchDialog() end)
    currencyButton(self,c,58,c.h-17,41,"SORT",function() self:sort() end)
    currencyButton(self,c,103,c.h-17,53,"COINS",function() self.screen="coins"; mark(self.win) end)
    c:text(left+7,5,"CALCULATOR",P.accent)
    c:text(left+7,20,"B: "..self.side.."  input: "..self.inputMode,P.textSecondary)
    local display=self.input or "0"; c:filledRectangle(left+7,34,mid-14,21,P.panelBackground); c:rectangle(left+7,34,mid-14,21,P.accent)
    local visible=display; while Driver.measure(visible)>mid-24 and #visible>1 do visible=visible:sub(2) end
    c:text(left+13,40,visible,P.textPrimary)
    local keypad={{"7","8","9","/"},{"4","5","6","*"},{"1","2","3","-"},{"0","00","000","+"},{".","B","C","="}}
    for r,row in ipairs(keypad) do for col,label in ipairs(row) do
        local x=left+7+(col-1)*43; local y=61+(r-1)*20
        currencyButton(self,c,x,y,39,label,function() self:keypad(label) end)
    end end
    currencyButton(self,c,left+7,166,54,"QTY",function() self:setInputMode("quantity") end)
    currencyButton(self,c,left+65,166,54,"MONEY",function() self:setInputMode("money") end)
    currencyButton(self,c,left+123,166,54,"TOTAL",function() self:setInputMode("total") end)
    currencyButton(self,c,left+7,185,82,"STACKS",function() self:stackInput() end)
    currencyButton(self,c,left+93,185,84,"CONVERT",function() self:convert() end)
    currencyButton(self,c,left+7,204,54,"SET",function() self:editSettings() end)
    currencyButton(self,c,left+65,204,54,"CSV OUT",function() self:csvExport() end)
    currencyButton(self,c,left+123,204,54,"CSV IN",function() self:csvImport() end)
    local v=self:calcValues(); local rx=left+mid+7
    c:text(rx,5,"RESULT",P.accent); c:text(rx,19,v.item and v.item.name:sub(1,24) or "No item selected",P.textPrimary)
    local unit=v.unit and currencyFormat(v.unit,currencyData.allowDecimals) or "-"
    local total=currencyFormat(v.total,currencyData.allowDecimals)
    local buyText=v.item and (currencyItemValue(v.item,"buy") and currencyFormat(currencyItemValue(v.item,"buy"),currencyData.allowDecimals) or "-") or "-"
    local sellText=v.item and (currencyItemValue(v.item,"sell") and currencyFormat(currencyItemValue(v.item,"sell"),currencyData.allowDecimals) or "-") or "-"
    local stackPrice=v.priceUnit and currencyMultiply(v.priceUnit,v.stack) or nil
    c:text(rx,34,"Buy: "..buyText.."  Sell: "..sellText,P.textSecondary); c:text(rx,46,"Unit Price: "..unit,P.textSecondary)
    c:text(rx,58,"Quantity: "..tostring(v.qty),P.textSecondary); c:text(rx,70,"Total Price: "..total,P.accent)
    c:text(rx,82,"Stacks: "..v.stacks.."  Remainder: "..v.remainder,P.textSecondary); c:text(rx,94,"Price/Stack: "..(stackPrice and currencyFormat(stackPrice,currencyData.allowDecimals) or "-"),P.textSecondary)
    c:text(rx,108,"MONEY / BUY",P.accent); c:text(rx,120,"Available: "..currencyFormat(currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0,currencyData.allowDecimals),P.textSecondary)
    c:text(rx,132,"Max Items: "..v.maxItems,P.textSecondary); c:text(rx,144,"Max Stacks: "..v.maxStacks,P.textSecondary); c:text(rx,156,"Remaining: "..currencyFormat(v.remaining,currencyData.allowDecimals),P.textSecondary)
    c:text(rx,174,"PROFIT",P.accent); local pc=v.profit and (v.profit>=0 and P.success or P.error) or P.textSecondary
    c:text(rx,186,"Purchase Cost: "..(v.purchase and currencyFormat(v.purchase,currencyData.allowDecimals) or "-"),P.textSecondary); c:text(rx,198,"Sale Revenue: "..(v.revenue and currencyFormat(v.revenue,currencyData.allowDecimals) or "-"),P.textSecondary)
    c:text(rx,210,"Profit: "..(v.profit and currencyFormat(v.profit,currencyData.allowDecimals) or "-"),pc); c:text(rx,222,"Profit/Item: "..(v.profitItem and currencyFormat(v.profitItem,currencyData.allowDecimals) or "-"),pc)
    c:text(rx,234,"Profit/Stack: "..(v.profitStack and currencyFormat(v.profitStack,currencyData.allowDecimals) or "-"),pc); c:text(rx,246,"Margin: "..(v.margin and string.format("%.2f%%",v.margin) or "-"),pc)
    c:paragraph(rx,258,self.convertResult or (currencyData.baseCoin=="" and "Set a base coin in COINS or SET" or "Greedy coins: "..currencyBreakdownText(v.total)),P.textSecondary,right,2)
end
register("currency","Currency Calculator","CU",558,292,Currency)

end
