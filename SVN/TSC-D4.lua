-- Last Modified Date: 20140608-00
require "ocs"

local cmdln = require "cmdline"
local fo = require "fo"
local tim = require "tim"
local maps = require "maps"
local accpos = require "accpos"
local mandator = require "mandator"

local depositId = ""
local entryFrom = ""
local entryTo = ""
local log_file = ""
local db_file = ""
local format = "PDF"

cmdln.add{ name="--logFile", descr="", func=function(x) log_file=x end }
cmdln.add{ name="--dbFile", descr="", func=function(x) db_file=x end }
cmdln.add{ name="--depositid", descr="", func=function(x) depositId=x end }
--cmdln.add{ name="--format", descr="", func=function(x) format=x end }
cmdln.add{ name="--from", descr="", func=function(x) entryFrom=x end }
cmdln.add{ name="--to", descr="",  func=function(x) entryTo=x end }

cmdln.parse( arg, true )
print("depositId: "..depositId, "|entryFrom: "..entryFrom, "|entryTo: "..entryTo, "|log_file: "..log_file, "|log_file: "..log_file, "|db_file: "..db_file, "|format: "..format)

ocs.createInstance( "LUA" )
local function process()
  local dubi = require "dubi"
  --self defined common module
  local common = require "common"
  local easygetter = require "easygetter"
  local confirmreport = require "confirmreport"

  common.CheckValidTimeRange(entryFrom, entryTo)

  local CallForceMapping = {["Call"]="Call", ["Force"]="Force", ["None"]=""}
  local debug_mode = false

  local sql_column_text = ' TEXT DEFAULT "" '
  local sql_column_integer = ' INTEGER DEFAULT 0'
  local sql_column_real = ' REAL DEFAULT 0.0'
  local table_name_deposit = "deposit"
  local table_name_order = "DECIDE_order"
  local table_name_order2 = "DECIDE_order2"
  local database_tables = {
    {table_name_deposit, {'account_no'..sql_column_text,
      'account_name'..sql_column_text,
      'account_type'..sql_column_text,
      'trader_id'..sql_column_text,
      --use the trade date in order
      'trade_date'..sql_column_text,
      'settlement_date'..sql_column_text,
      --there only have a field named cash_balance not begin_cash_bal and end_cash_bal, need to confirm with BA
      'begin_cash_bal'..sql_column_real,
      'end_cash_bal'..sql_column_real,
      'non_cash_collateral'..sql_column_real,
      'begin_equity_bal'..sql_column_real,
      'end_equity_bal'..sql_column_real,
      'initial_margin'..sql_column_real,
      'maintenance_margin'..sql_column_real,
      'excess_insufficient'..sql_column_real,
      'net_customer_paid'..sql_column_real,
    }},

    {table_name_order, {'series'..sql_column_text,
      'buy_sell'..sql_column_text,
      'pos'..sql_column_text,
      'no_of_contract'..sql_column_text,
      'deal_price'..sql_column_real,
      'premium_amount'..sql_column_real,
      'brokerage_fee'..sql_column_real,
      'vat'..sql_column_real,
      'WH'..sql_column_real,
      'long'..sql_column_text,
      'short'..sql_column_text,
      'charge_amount'..sql_column_real,
      'trade_date'..sql_column_text,
      'future_realized_pl'..sql_column_real,
      'option_realized_pl'..sql_column_real,
      'long_short'..sql_column_text,
      'final_settlement_price'..sql_column_real,
      'settlement_amount'..sql_column_real,
      'settlement_date'..sql_column_text,
    }},
    {table_name_order2, {'series'..sql_column_text,
      'long'..sql_column_text,
      'short'..sql_column_text,
      'last_price'..sql_column_real,
      'unrealized_pl'..sql_column_real,
      'options_value_long'..sql_column_real,
      'options_value_short'..sql_column_real,
    }}
  }

  common.CreateTables(db_file, log_file,  database_tables, debug_mode)

  local DECIDE_deposit_obj = fo.Deposit( tonumber(depositId) )

  local depositList = {}
  local depositItem = {}
  local client_obj = DECIDE_deposit_obj:getClient()

  table.insert (depositItem, {'account_no', DECIDE_deposit_obj:getNumber()})
  table.insert (depositItem, {'account_name', DECIDE_deposit_obj:getName()})
  if (DECIDE_deposit_obj:hasAccountType()) then
    table.insert (depositItem, {'account_type', DECIDE_deposit_obj:getAccountType():getName() })
  end

  if( client_obj:hasAccountManager() ) then
    local account_manager = client_obj:getAccountManager()
    local trader_id = dubi.getSETTraderId( account_manager:getShortName())
    if( trader_id ~= nil) then
      -- ** pending to dev for multiple exchange
      table.insert (depositItem, {'trader_id', trader_id })
    end
  end

  local clientFeeCategories = client_obj:getClientFeeCategories()
  for _, category in pairs(clientFeeCategories) do
    local categoryName = category:getName()
    local whtPos = string.find( categoryName, "WHT" )
    if ( whtPos ~= nil) then
      table.insert (depositItem, {'WH', string.sub(categoryName, whtPos+4, -2) })
      -- should be only configured one WHT, so if founded, should quit loop
      break
    end
  end

  local orderVolLimit = easygetter.GetFirstActiveOVL(depositId)

  local orderVolumeRisk = nil

  if ( orderVolLimit ~= nil ) then
     table.insert (depositItem, {'begin_equity_bal', easygetter.EvenAmountToDouble(orderVolLimit:getPreviousEquityBalance())})
     table.insert (depositItem, {'non_cash_collateral', easygetter.EvenAmountToDouble(orderVolLimit:getNonCashCollateral())})
  end

  if(orderVolumeRisk ~= nil) then
    table.insert (depositItem, {'end_cash_bal',easygetter.EvenAmountToDouble(orderVolumeRisk:getCashBalance()) })
    table.insert (depositItem, {'end_equity_bal', easygetter.EvenAmountToDouble(orderVolumeRisk:getEquityBalance())})
    table.insert (depositItem, {'initial_margin', easygetter.EvenAmountToDouble(orderVolumeRisk:getPositionMargin()) })
    table.insert (depositItem, {'maintenance_margin', easygetter.EvenAmountToDouble(orderVolumeRisk:getMaintenanceMargin()) })
    table.insert (depositItem, {'excess_insufficient',easygetter.EvenAmountToDouble(orderVolumeRisk:getExcessEquityBalance()) })
    table.insert (depositItem, {'net_customer_paid',easygetter.EvenAmountToDouble(orderVolumeRisk:getForceMargin()) })
  end

  --      table.insert (depositItem, {'begin_cash_bal',easygetter.EvenAmountToDouble() }) --not available for now in Limit & Risk

  local orders = easygetter.GetOrders( depositId, entryFrom, entryTo )

  local orderList = {}
  local have_get_trade_settlement_day = false

  for _,no in pairs( orders ) do
    local order = fo.Order( no )
    local orderHandlingType = order:getHandlingType()
    if (orderHandlingType == 'TradingOrder' or orderHandlingType == 'BlockTrade') then
      local orderlegs = order:getOrderLegs()
      for _,orderLeg in pairs(orderlegs) do
        local orderItem = {}
        --need to confirm this cdate is in front of report?
        local tradeDate = order:getEntryTime():getDateInUtcOffset(common.offsetTimeZoneSecs):toString("%Y%m%d")
        table.insert (orderItem, {'trade_date', tradeDate})
        local cdate = common.GetSettlementDateFromOrder(order);
        if( cdate ~= nil) then
          table.insert (orderItem, {'settlement_date', cdate:toString("%Y%m%d")})
          if( have_get_trade_settlement_day == false) then
            table.insert (depositItem, {'trade_date', tradeDate})
            table.insert (depositItem, {'settlement_date', cdate:toString("%Y%m%d")})
            have_get_trade_settlement_day = true
          end
        end

        table.insert (orderItem, {'series', orderLeg:getContract():getContractCode()})

        local Buysell = common.BuySellToBSMapping[orderLeg:getOrderKind()] or ''
        table.insert (orderItem, {'buy_sell', Buysell})

        LongShort = common.BuySellToLSMapping[orderLeg:getOrderKind()] or ''
        table.insert (orderItem, {'long_short', LongShort})
        table.insert (orderItem, {'pos', orderLeg:getOpenClose()})

        local no_of_contract = orderLeg:getExecQty()
        table.insert (orderItem, {'no_of_contract', no_of_contract})

        if( LongShort == 'L' )  then
          table.insert (orderItem, {'long', no_of_contract})
        elseif ( LongShort == 'S' ) then
          table.insert (orderItem, {'short', no_of_contract})
        end
        
        if (no_of_contract ~= 0 ) then
          local match_avg_price =  orderLeg:getAvgExecPrice()
          table.insert (orderItem, {'deal_price', match_avg_price})
        end

        local vat = 0
        for _,op in pairs( order:getOrderOperations() ) do
          if op:getTransactionType() == "Match" then
            local oplegs = op:getOrderOperationLegs()
            if (#oplegs ~= 1) then
              confirmreport.announceGenerationFailure("One order operation should and only should have one order opeation legs!")
              print("One order operation should and only should have one order opeation legs!")
              os.exit(1)
            elseif(oplegs[1]:getContract():getContractCode() == orderLeg:getContract():getContractCode()) then
              local opleg = oplegs[1]
              if (opleg:hasTransaction()) then
                local ta = opleg:getEffectiveTransaction()
                local posting = fo.Posting(ta,1)
                local vat = easygetter.EvenAmountToDouble(posting:getFeeAccountCurr(nil,maps.NameToFee("Settlement")))
              end
            end
          end
        end
        table.insert (orderItem, {'vat', vat})

        --      table.insert (orderItem, {'premium_amount', }) --not available for now in trade date
        --      table.insert (orderItem, {'brokerage_fee', }) --not available for now in trade date
        --      table.insert (orderItem, {'future_realized_pl', }) --not available for now in Limit & Risk
        --      table.insert (orderItem, {'option_realized_pl', }) --not available for now in Limit & Risk
        --      table.insert (orderItem, {'final_settlement_price', }) --not have any information in mapping
        --      table.insert (orderItem, {'settlement_amount', --Settlement Amount = contract number x settlement price}) --not have any information in position
        --table.insert (orderItem, {'charge_amount', premium_amount + brokerage_fee + vat + WH})



        table.insert (orderList, orderItem)
      end
    end
  end
  table.insert (depositList, depositItem)

  local orderList2 = {}
  local from = tim.TimeStamp( entryFrom )
  local to = tim.TimeStamp( entryTo )

  local position_list = DECIDE_deposit_obj:getAccPositions()   -- get a list of positions
  for _,position in pairs ( position_list ) do
    local data = accpos.getPositionValues( position, from , to, DECIDE_deposit_obj:getGeneralLedgerCurrencyType() )
    local data_effective_status = data.effective
    if ( data_effective_status == "Yes" ) then
      local orderItem2 = {}
      local contract = position:getContract()
      table.insert (orderItem2, {'series', contract:getContractCode()})
      
      table.insert (orderItem2, {'last_price', easygetter.EvenAmountToDouble(data.LastUnchecked)})

      local long = easygetter.EvenAmountToDouble(data.buyQuantity)
      table.insert (orderItem2, {'long', long})

      local short = easygetter.EvenAmountToDouble(data.sellQuantity)
      table.insert (orderItem2, {'short', short})
      
      local unrealized = easygetter.EvenAmountToDouble(data.endUPL)
      table.insert (orderItem2, {'unrealized_pl', unrealized})

      local act_cost = easygetter.EvenAmountToDouble(data.endPosBookValue)
      if ( LongShort == 'L') then
        table.insert (orderItem2, {'options_value_long', act_cost})
      elseif ( Long_Short == 'S') then
        table.insert (orderItem2, {'options_value_short', act_cost})
      end
      table.insert (orderList2, orderItem2)
    end
  end

  common.InsertRecords(db_file, log_file, table_name_order2, orderList2, debug_mode)
  common.InsertRecords(db_file, log_file, table_name_deposit, depositList, debug_mode)
  common.InsertRecords(db_file, log_file, table_name_order, orderList, debug_mode)
end
local inst = os.getenv( "OCSINST" )
local mand = mandator.Mandator( inst )
mandator.changeTo( mand, process )