-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Currency={}
function Currency:init()
    self.screen="calc"; self.selected=1; self.coinSelected=1; self.sortMode="recent"; self.search=""
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
    self.screen="calc"; self.search=""; self:refreshItems()
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
        self.fields.quantity=tostring(stacks*item.stack+rem); self:setInputMode("quantity"); self.input=self.fields.quantity; mark(self.win)
    end)
end
function Currency:convert()
    local coinNames={}; for _,coin in ipairs(currencyData.coins) do coinNames[#coinNames+1]=coin.name end
    if #coinNames<2 then errorBox("Register at least two coins first"); return end
    askFields("Coin conversion",{{"From coin",coinNames[1]},{"Amount", "1"},{"To coin",coinNames[2]}},function(values)
        local from,to=currencyFindCoin(values[1]),currencyFindCoin(values[3]); local count=currencyInteger(values[2])
        if not from or not to or not count then errorBox("Unknown coin or invalid amount"); return end
        local amount=count*currencyCoinValue(from); local result,remain=currencyBreakdown(amount)
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
        if not currencyValidName(values[1]) or currencyFindCoin(values[1]) and (not old or old.name~=values[1]) then errorBox("Coin name is empty or already used"); return end
        local value=currencyFixed(values[2],currencyData.allowDecimals)
        if not value or value<=0 then errorBox("Value must be a positive number"); return end
        if old then old.name=ascii(values[1]); old.unit=values[2] else currencyData.coins[#currencyData.coins+1]={name=ascii(values[1]),unit=values[2]} end
        if currencyData.baseCoin=="" then currencyData.baseCoin=ascii(values[1]) end
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Coin saved",P.success) end
        mark(self.win)
    end)
end
function Currency:addItem(edit)
    local old=edit and self:selectedItem()
    local fields={{"Item ID",old and old.id or "minecraft:item"},{"Display name",old and old.name or "Item"},
        {"Buy price",old and old.buy or ""},{"Sell price",old and old.sell or ""},{"Stack size",old and tostring(old.stack) or "64"}}
    askFields(edit and "Edit item" or "Add item",fields,function(values)
        if not currencyValidName(values[1]) then errorBox("Item ID is empty or invalid"); return end
        local stack=currencyInteger(values[5]); local buy=values[3]; local sell=values[4]
        if (buy~="" and not currencyFixed(buy,currencyData.allowDecimals)) or (sell~="" and not currencyFixed(sell,currencyData.allowDecimals)) then errorBox("Price is invalid"); return end
        if not stack or stack<1 or stack>999999 then errorBox("Stack size must be 1..999999"); return end
        for _,item in ipairs(currencyData.items) do if item~=old and item.id==values[1] then errorBox("Item ID already used"); return end end
        if old then old.id=ascii(values[1]); old.name=ascii(values[2]); old.buy=buy; old.sell=sell; old.stack=stack
        else currencyData.items[#currencyData.items+1]={id=ascii(values[1]),name=ascii(values[2]),buy=buy,sell=sell,stack=stack,favorite=false} end
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Item saved",P.success) end
        self:refreshItems(); mark(self.win)
    end)
end
function Currency:deleteItem()
    local item=self:selectedItem(); if not item then return end
    dialog("Delete item","Delete "..item.id.." from price dictionary?",{"Yes","No"},function(value)
        if value~="Yes" then return end
        for i,v in ipairs(currencyData.items) do if v==item then table.remove(currencyData.items,i); break end end
        currencySave(); self:refreshItems(); notify("Item deleted",P.warning); mark(self.win)
    end)
end
function Currency:toggleFavorite()
    local item=self:selectedItem(); if item then item.favorite=not item.favorite; currencySave(); self:refreshItems(); mark(self.win) end
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
        currencyData.baseCoin=values[1]; currencyData.allowDecimals=decimals=="yes"; currencyData.rounding=rounding
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Currency settings saved",P.success) end
        mark(self.win)
    end)
end
function Currency:csvExport()
    local ok,err=pcall(function()
        local f,e=fs.open(currencyCsvPath,"w"); if not f then error(e or "Cannot open CSV") end
        f.write("item_id,name,buy,sell,stack\n")
        for _,item in ipairs(currencyData.items) do f.write(table.concat({item.id,item.name,item.buy,item.sell,tostring(item.stack)},",").."\n") end
        f.close()
    end)
    if ok then notify("CSV exported: "..currencyCsvPath,P.success) else errorBox(err) end
end
function Currency:csvImport()
    if not fs.exists(currencyCsvPath) then errorBox("No CSV at "..currencyCsvPath); return end
    local ok,err=pcall(function()
        local f,e=fs.open(currencyCsvPath,"r"); if not f then error(e or "Cannot read CSV") end
        local content=f.readAll(); f.close(); local first=true
        for line in (content.."\n"):gmatch("([^\r\n]+)") do
            if first then first=false else
                local p=currencyCsvSplit(line); local stack=currencyInteger(p[5] or "64")
                if #p>=5 and currencyValidName(p[1]) and stack and (p[3]=="" or currencyFixed(p[3],currencyData.allowDecimals)) and (p[4]=="" or currencyFixed(p[4],currencyData.allowDecimals)) then
                    local item=currencyItemById(p[1]); if item then item.name=ascii(p[2]); item.buy=p[3]; item.sell=p[4]; item.stack=stack
                    else currencyData.items[#currencyData.items+1]={id=ascii(p[1]),name=ascii(p[2]),buy=p[3],sell=p[4],stack=stack,favorite=false} end
                end
            end
        end
        local saved,e=currencySave(); if not saved then error(e) end
    end)
    if ok then self:refreshItems(); notify("CSV imported: "..currencyCsvPath,P.success); mark(self.win) else errorBox(err) end
end
function Currency:calcValues()
    local item=self:selectedItem(); local unit=item and currencyItemValue(item,self.side=="BUY" and "buy" or "sell")
    local qty=currencyInteger(self.fields.quantity or "0") or 0; local money=currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0
    local total=unit and unit*qty or 0
    if self.inputMode=="total" then total=currencyFixed(self.fields.total or "0",currencyData.allowDecimals) or 0 end
    local shownUnit=unit
    if self.inputMode=="total" and qty>0 then shownUnit=total/qty end
    local stack=item and item.stack or 64
    local maxItems=unit and unit>0 and floor(money/unit) or 0
    local buy=currencyItemValue(item,"buy"); local sell=currencyItemValue(item,"sell")
    local purchase=buy and buy*qty or nil; local revenue=sell and sell*qty or nil; local profit=purchase and revenue and revenue-purchase or nil
    return {item=item,unit=shownUnit,priceUnit=unit,qty=qty,total=total,stack=stack,stacks=floor(qty/stack),remainder=qty%stack,maxItems=maxItems,maxStacks=floor(maxItems/stack),remaining=money-maxItems*(unit or 0),purchase=purchase,revenue=revenue,profit=profit,profitItem=buy and sell and sell-buy or nil,profitStack=buy and sell and (sell-buy)*stack or nil,margin=purchase and purchase>0 and profit*100/purchase or nil}
end
function Currency:onKey(k)
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
        if value=="Yes" then table.remove(currencyData.coins,self.coinSelected); if currencyData.baseCoin==coin.name then currencyData.baseCoin="" end; currencySave(); self.coinSelected=clamp(self.coinSelected,1,max(1,#currencyData.coins)); notify("Coin deleted",P.warning); mark(self.win) end
    end)
end
function Currency:onMouse(kind,x,y,b)
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
    currencyButton(self,c,183,c.h-38,65,"BASE",function() local coin=currencyData.coins[self.coinSelected]; if coin then currencyData.baseCoin=coin.name; currencySave(); mark(self.win) end end)
    currencyButton(self,c,252,c.h-38,60,"BACK",function() self.screen="calc"; mark(self.win) end)
end
function Currency:draw(c)
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
    c:text(rx,34,"Buy: "..buyText.."  Sell: "..sellText,P.textSecondary); c:text(rx,46,"Unit Price: "..unit,P.textSecondary)
    c:text(rx,58,"Quantity: "..tostring(v.qty),P.textSecondary); c:text(rx,70,"Total Price: "..total,P.accent)
    c:text(rx,82,"Stacks: "..v.stacks.."  Remainder: "..v.remainder,P.textSecondary); c:text(rx,94,"Price/Stack: "..(v.priceUnit and currencyFormat(v.priceUnit*v.stack,currencyData.allowDecimals) or "-"),P.textSecondary)
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
