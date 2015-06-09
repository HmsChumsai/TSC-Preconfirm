TSCReportUtil={}
local utils = require('utils')
local tim = require('tim')
local dubi = require('dubi')

function TSCReportUtil.GetOrders( depositId, entryFrom, entryTo, handleAfc )
	local options = {}
	if ( entryFrom ~= nil and entryFrom ~= "" ) then
-- new check for AFC
		if handleAfc then
					-- set entryFrom to the previous day 7pm
			local prevDate = tim.TimeStamp(entryFrom):getUtcDate()
			local afcTime = tim.ClockTime("10:00")
			entryFrom = tim.TimeStamp( prevDate, afcTime ):toString( "%Y-%m-%dT%H:%M" )
			print(entryFrom)
		end
		options.entryFrom = entryFrom
	end
	if ( entryTo ~= nil and entryTo ~= "" ) then
		options.entryTo = entryTo
	end
	options.depositId = tostring(depositId)
-- do not yet return orders as we still have to sort out the pending AFC orders
	local orders = {}

local function cb( orderid )
	local order = fo.Order( orderid )
	print('orderid : ',orderid)
	if not handleAfc or order:getAfterCloseOrder() ~= "Pending" then
		orders[#orders+1] = orderid
	end
end
	dubi.getOrders( options, cb )
	return orders
end

function TSCReportUtil.getOrderList(orders,isBillOrder)
	print('----------- Start getOrderList--------')
	local global_seq={}
	local global_highest_price = {}
	global_seq['Buy'] = 0
	global_seq['Sell'] = 0
	local port_seq = {}
	local port_seq_buy ={}
	local port_seq_sell = {}
	local ttfMapping={}
	ttfMapping['NVDR']=2
	ttfMapping['TTF']=1
	local orderMatchStatusToMLMapping = {[true]="M", [false]="P"}
	local orderList= {}
	local totalList={}
	local totalItem={}
	local dealList = {} 
	local net=0.0
	local total_gross = 0.0
	local total_amount_due = 0.0
	for _,no in pairs(orders) do 
		local order = fo.Order( no )
		local ttf=''
		local seq=''
		local isAfc = order:getAfterCloseOrder() ~="Pending"
		print("order no. : "..no)
		--print(" order:getAfterCloseOrder() : "..order:getAfterCloseOrder())
		local orderHandlingType = order:getHandlingType()
		if ((orderHandlingType == 'TradingOrder' or orderHandlingType == 'BlockTrade') and isAfc) then
			local orderlegs = order:getOrderLegs()
			for _,orderleg in pairs(orderlegs) do
				local match_qty = orderleg:getExecQty()

				if (match_qty~=0 or isBillOrder==1 ) then	
					local orderItem = {}
					local vol=0
					local price=0
					local contract=fo.getOrderContract(order)
					local symbol= contract:getSymbol() 

					ttf = contract:getInstrument():getProductCategory()
					local buy_sell = order:getBuySell()
					local execQty = orderleg:getExecQty()
					local status = orderMatchStatusToMLMapping[totalQty == execQty]
					local tran_time=0
					if (isBillOrder==1) then
						local entry=order:getEntryUser():getName()
						vol = orderleg:getTotalQty()
						price = orderleg:getPriceLimit()
						local orderOperations = order:getOrderOperations()
						local deal_seq=0
						for _,op in pairs( orderOperations ) do
							if op:getTransactionType() ~= "Entry" then	
								local opLegs=op:getOrderOperationLegs()
								for _,opLeg in pairs (opLegs) do
									deal_seq=deal_seq+1
									local dealItem = {}
									tran_time=op:getEntryTime():addHours(7):toString("%T")
									local deal_qty = opLeg:getExecQty()
									local deal_price = opLeg:getPrice()
									local deal_time = op:getEntryTime():addHours(7):toString("%T")

									table.insert(dealItem ,{'order_no',no})
									table.insert(dealItem ,{'deal_seq',deal_seq})
									table.insert(dealItem ,{'deal_price',deal_price})
									table.insert(dealItem ,{'deal_qty',deal_qty})
									table.insert(dealItem ,{'deal_time',deal_time})
									table.insert(dealList,dealItem)

								end
							end
						end
						time =order:getEntryTime():addHours(7):toString("%T") 
						local totalQty = orderleg:getOpenQty()
						table.insert(orderItem,{'matched',match_qty})
						table.insert(orderItem,{'entry',entry})
						table.insert(orderItem,{'time',time})
						table.insert(orderItem,{'tran_time',tran_time})
						table.insert(orderItem, {'st', M.getStatus(order:getOrderId())})
					else
						price = orderleg:getAvgExecPrice()
						price = easygetter.EvenAmountToDouble(price)
						vol = execQty
					end
					local comm_vat = getFee(order,orderleg)

					local comm_fee = comm_vat/(1.07)
					local vat=comm_vat-comm_fee
					local gross_amt=vol*price
					local amount_due=0.0

					if (buy_sell=='Buy') then
						amount_due=gross_amt+comm_fee+vat
						total_gross=total_gross-gross_amt
						total_amount_due = total_amount_due-(gross_amt+comm_vat)
						net = net-amount_due
					else
						amount_due=gross_amt+(comm_fee+vat)
						total_amount_due = total_amount_due+(gross_amt-comm_vat)
						total_gross=total_gross+gross_amt
						net = net + amount_due
					end
					if (isBillOrder==1) then 
						table.insert(orderItem,{'matched',match_qty})
						table.insert(orderItem,{'entry',entry})
						table.insert(orderItem,{'time',time})
						table.insert(orderItem,{'tran_time',tran_time})
						table.insert(orderItem, {'st', M.getStatus(order:getOrderId())})
					end

					table.insert (orderItem,{'ttf',ttfMapping[ttf] or '' })
					table.insert (orderItem,{'order_no',no})
					--Mark the highest price of symbol/side with seq
					--print(port_seq[symbol][buy_sell])
					local seq_item = {}
					local seq=''
					seq_item = {['symbol']= symbol,['price']=price}
					--print("seq_item : ",utils.prettystr(seq_item))
					if buy_sell =='Buy' then
						--print("-------------------------- BUY -----------------------")
						if (#port_seq_buy==0) then
							global_seq[buy_sell]=global_seq[buy_sell]+1
							seq=global_seq[buy_sell]
							port_seq_buy[seq]=seq_item
						else
							local Existed = false
							--print("before loop : ",#port_seq_buy)
							for i,j in pairs(port_seq_buy) do
								--print("i : ",i," j : ",utils.prettystr(j))
								if j.symbol==symbol then
									Existed=true
									--print("Duplicated!")
									if j.price<price then
										--print("j.price<price")
										port_seq_buy[i]=seq_item 
										--print("port_seq_buy["..i.."] : ",utils.prettystr(port_seq_buy[i]))
										--print("after replace : ",#port_seq_buy)
									end
								end 
							end
							if Existed==false then
								--print("Existed! : ",Existed)
								global_seq[buy_sell]=global_seq[buy_sell]+1
								seq=global_seq[buy_sell]
								port_seq_buy[seq]=seq_item	
							end
						end
						--print("seq_item",utils.prettystr(seq_item))
						--print("port_seq_buy : "..utils.prettystr(port_seq_buy))
						--print("--------------------------End BUY -----------------------")
					else
					------------------------------------------------
						--print("-------------------------- SELL -----------------------")
					 --if port_seq[buy_sell] ~=nil then -- Swap If current symbol greater than existed
						if (#port_seq_sell==0) then
							global_seq[buy_sell]=global_seq[buy_sell]+1
							seq=global_seq[buy_sell]
							port_seq_sell[seq]=seq_item
						else
							local Existed = false
							--print("before loop : ",#port_seq_sell)
							for i,j in pairs(port_seq_sell) do
								--print("i : ",i," j : ",utils.prettystr(j))
								if j.symbol==symbol then
									Existed=true
									--print("Duplicated!")
									if j.price<price then
										--print("j.price<price")
										port_seq_sell[i]=seq_item 
										--print("port_seq_sell["..i.."] : ",utils.prettystr(port_seq_sell[i]))
										--print("after replace : ",#port_seq_sell)
									end
								end 
							end
							if Existed==false then
								--print("Existed! : ",Existed)
								global_seq[buy_sell]=global_seq[buy_sell]+1
								seq=global_seq[buy_sell]
								port_seq_sell[seq]=seq_item	
							end
						end
					end
					--print("A > B : "..'A'>'B')
					table.insert (orderItem,{'stock',symbol})
					table.insert (orderItem,{'side',buy_sell})
					table.insert (orderItem,{'vol',vol})
					table.insert (orderItem,{'comm_fee',comm_fee})
					table.insert (orderItem,{'vat',vat})
					table.insert (orderItem,{'price',price})
					table.insert (orderItem,{'gross_amt',gross_amt})
					table.insert (orderItem,{'amount_due',amount_due})
					table.insert (orderItem,{'seq',seq})
					table.insert(orderList,orderItem)
				end
				--print("port_seq : " ,utils.prettystr(port_seq))
			end
		end
	end
	table.sort(port_seq_sell, compare)
	table.sort(port_seq_buy, compare)
	--print(utils.prettystr(port_seq_sell))
	setSeq(orderList,port_seq_sell,port_seq_buy)
	--print(utils.prettystr(orderList))

	if (net<0) then
		paid_received = "Paid "

	else
		paid_received = "Received " 
	end
	table.insert(totalItem,{'net',net})
	table.insert(totalItem,{'paid_received',paid_received})
	table.insert(totalItem,{'total_gross',total_gross})
	table.insert(totalItem,{'total_amount_due',total_amount_due})
	table.insert(totalList,totalItem)
	print('----------- End getOrderList--------')
	return orderList,totalList,dealList --dealList for Bill Order(TSC-D7) only
end
function setSeq(orderList,port_seq_sell,port_seq_buy)
	local context_buy = {}
	local context_sell = {}
	for i=1,#port_seq_buy do
		local symbol = port_seq_buy[i]["symbol"]
		local price = port_seq_buy[i]["price"]
		context_buy[symbol..price]=i
	end
	for i=1,#port_seq_sell do
		local symbol = port_seq_sell[i]["symbol"]
		local price = port_seq_sell[i]["price"]
		context_sell[symbol..price]=i
	end	
	for i,j in pairs(orderList) do
		local buy_sell = j[4][2]
		print("i : ",i," j : ",utils.prettystr(j))
		print("j.side",utils.prettystr(j[4][2]))
		if buy_sell=="Buy" then 
			if context_buy[j[3][2]..j[8][2]] and context_buy[j[3][2]..j[8][2]] ~= nil then
				print("Founded",context_buy[j[3][2]..j[8][2]])
				j[11][2] = context_buy[j[3][2]..j[8][2]]
			
			else
				print("Not Founded")
				j[11][2] = ''
			end
		else
			if context_sell[j[3][2]..j[8][2]] and context_sell[j[3][2]..j[8][2]] ~= nil then
				print("Founded",context_sell[j[3][2]..j[8][2]])
				j[11][2] = context_sell[j[3][2]..j[8][2]]
			
			else
				print("Not Founded")
				j[11][2] = ''
			end
		end
	end
end	

function compare(a,b)
	--print(utils.prettystr(a))
  return a.symbol < b.symbol
end

function commonOrderData(orderList,orderItem)
	print('order_no',no)
	table.insert (orderItem,{'order_no',no})
	table.insert (orderItem,{'stock',symbol})
	table.insert (orderItem,{'side',buy_sell})
	table.insert (orderItem,{'vol',vol})
	table.insert (orderItem,{'comm_fee',comm_fee})
	table.insert (orderItem,{'vat',vat})
	table.insert (orderItem,{'price',price})
	table.insert (orderItem,{'gross_amt',gross_amt})
	table.insert (orderItem,{'amount_due',amount_due})
	table.insert(orderList,orderItem)
	return orderList,orderItem
end

function getFee(order, orderLeg, ut)
	local fee = 0
	for _, execution in ipairs(order:getEffectiveExecutions(ut)) do
		local leg = execution:getOrderLeg(ut)
		if leg:getOrder() == order and leg:getLegIndex() == orderLeg:getLegIndex() then
			local data = execution:getData(ut)
			fee = fee + math.abs(data.amountp:asDouble() - data.netAmountP:asDouble())
		end
	end
	return fee
end

function getNextBusDate(stDate)	
	stDate=tim.Date(stDate)
	local nextDate=''
--stDate=tim.TimeStamp(stDate):toString("%d/%m/%y")
	local businesscenter = fo.BusinessCenter("THAILAND")
	local tradingCalendar = businesscenter:getTradingCalendar()
	local nextDate= tradingCalendar:addActiveDays( stDate,1, isNONE ):toString("%d/%m/%y")
return nextDate

end

local hasLimitValue = function(limittype)
local list = {
	Limit = true,
	LimitIceberg = true,
	OrMarketOnClose = true,
	OneCancelsOtherL = true,
	OneCancelsOtherM = true
	}
return list[limittype]
end

function TSCReportUtil.checkBusDate(entryFrom)
	entryFrom = tim.TimeStamp(entryFrom):toString("%d.%m.%y")
	local businesscenter = fo.BusinessCenter("THAILAND")
	local tradingCalendar = businesscenter:getTradingCalendar()
	local temp=tradingCalendar:addActiveDays( tim.Date(entryFrom),-1, isNONE):toString("%Y-%m-%dT17:00:00")
	local ret=tradingCalendar:correctDate( tim.Date(entryFrom),'BACKWARD' ):toString("%Y-%m-%dT17:00:00")
	print("entryFrom Fixed : ",ret)
	return ret
end
return TSCReportUtil
