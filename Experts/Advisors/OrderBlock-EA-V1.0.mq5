//+------------------------------------------------------------------+
//|                                       OrderBlock-EA-V1.0.mq5     |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "OrderBlock EA"
#property version "1.00"
#property strict
#property description "Order Block Trading EA V1.0"
#property description ""
#property description "=== ระบบ Order Block ==="
#property description "1. ตรวจจับ Bullish/Bearish Order Block"
#property description "2. ตรวจสอบความถูกต้อง (Take Out + Gap)"
#property description "3. เข้าเทรดเมื่อราคากลับมาที่ OB Zone"
#property description "4. Risk Management แบบ Martingale"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== Order Block Settings ==="
input int OB_LookbackBars = 100;           // จำนวนแท่งเทียนที่ย้อนกลับ
input int OB_MinMovePoints = 500;          // แท่งเทียนขั้นต่ำที่ต้องเคลื่อนไหว (points)
input int OB_MaxAgeBars = 50;              // อายุสูงสุดของ OB (bars)
input bool OB_RequireGap = true;           // ต้องมี Gap หลัง OB
input double OB_MinGapPoints = 50;         // Gap ขั้นต่ำ (points)

input group "=== Trading Parameters ==="
input double Lots = 0.10;                  // ขนาด Lot
input int MaxTrades = 15;                  // จำนวน Order สูงสุด
input double Multiplier = 1.15;            // Martingale Multiplier
input double MaxLotPerOrder = 0.50;        // Lot สูงสุดต่อ Order
input double MaxTotalLot = 3.00;           // Lot รวมสูงสุด

input group "=== TP/SL Settings ==="
input double TakeProfitPoints = 3500.0;    // Take Profit (points)
input double StopLossPoints = 2000.0;      // Stop Loss (points)
input double TrailingPoints = 1200.0;      // Trailing Stop (points)
input double OB_SLBuffer = 200.0;          // Buffer สำหรับ SL (points)

input group "=== Risk Management ==="
input bool UseMarginRiskManagement = true; // ใช้ Margin Risk Management
input double MarginRiskThreshold = 75.0;   // เริ่มจัดการที่ % margin
input double MarginCriticalThreshold = 90.0; // ปิดทั้งหมดที่ % margin
input double TriggerDistance = 500.0;      // Distance สำหรับ Price Runaway
input double RiskTriggerMultiplier = 1.5;  // ตัวคูณ Price Runaway

input group "=== Time Filter ==="
input bool UseHourTrade = true;            // ใช้ Time Filter
input int StartHour = 8;                   // ชั่วโมงเริ่ม
input int EndHour = 23;                    // ชั่วโมงสิ้นสุด
input int MagicNumber = 123456;            // Magic Number

input group "=== Display ==="
input int X_pos = 270;                     // ตำแหน่ง X
input int Y_pos = 35;                      // ตำแหน่ง Y

//--- MT5 Trade Objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CAccountInfo ExtAccountInfo;

//--- Global Variables
datetime g_timeLastBar = 0;
bool g_isBuy = false;
bool g_isSell = false;
bool g_priceRunaway = false;
datetime g_lastRecoveryTime = 0;
datetime g_lastRunawayCloseTime = 0;

//--- Order Block Structure
struct OrderBlock
{
   int barIndex;          // แท่งเทียนที่สร้าง OB
   datetime time;         // เวลา
   double high;           // ราคาสูงสุดของ OB
   double low;            // ราคาต่ำสุดของ OB
   double open;           // ราคาเปิด
   double close;          // ราคาปิด
   int direction;         // 1 = Bullish OB, -1 = Bearish OB
   bool isValid;          // ผ่านการตรวจสอบแล้ว
   bool takeOut;          // มี Take Out
   bool hasGap;           // มี Gap
   double moveSize;       // ขนาดการเคลื่อนไหว
};

OrderBlock g_orderBlocks[];
int g_obCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints(30);
   ExtTrade.SetTypeFilling(ORDER_FILLING_IOC);
   
   if (!ExtSymbolInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   
   Print("Order Block EA V1.0 initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "OB_");
   Print("Order Block EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtSymbolInfo.RefreshRates();
   
   //--- Manage margin risk first
   if (PositionsTotal() > 0)
      ManageMarginRisk();
   
   //--- Time filter
   if (UseHourTrade)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if (dt.day_of_week == 0 || dt.day_of_week == 6)
         return;
      if (dt.hour < StartHour || dt.hour >= EndHour)
         return;
   }
   
   //--- New bar check
   datetime currentTime[1];
   if (CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime) < 1)
      return;
   
   if (g_timeLastBar == currentTime[0])
      return;
   g_timeLastBar = currentTime[0];
   
   //--- Trailing Stop
   TrailingStopFirstOrder();
   
   //--- Scan for Order Blocks
   ScanOrderBlocks();
   
   //--- Check entry signals
   CheckOrderBlockEntry();
   
   //--- Update display
   DisplayInfo();
}

//+------------------------------------------------------------------+
//| Scan for Order Blocks                                              |
//+------------------------------------------------------------------+
void ScanOrderBlocks()
{
   ArrayResize(g_orderBlocks, 0);
   g_obCount = 0;
   
   MqlRates rates[];
   if (CopyRates(_Symbol, PERIOD_CURRENT, 0, OB_LookbackBars + 10, rates) < OB_LookbackBars + 10)
      return;
   
   ArraySetAsSeries(rates, true);
   
   //--- Look for potential Order Blocks
   for (int i = 3; i < OB_LookbackBars - 3; i++)
   {
      //--- Bullish OB: Last bearish candle before sharp upward move
      if (IsBullishOrderBlock(rates, i))
      {
         OrderBlock ob;
         ob.barIndex = i;
         ob.time = rates[i].time;
         ob.high = rates[i].high;
         ob.low = rates[i].low;
         ob.open = rates[i].open;
         ob.close = rates[i].close;
         ob.direction = 1; // Bullish
         
         //--- Calculate move size (next 2-3 candles)
         double moveSize = rates[i-1].close - rates[i].close;
         ob.moveSize = MathAbs(moveSize) / _Point;
         
         //--- Check Take Out
         ob.takeOut = CheckTakeOut(rates, i, 1);
         
         //--- Check Gap
         ob.hasGap = CheckGap(rates, i, 1);
         
         //--- Validate
         ob.isValid = (ob.takeOut && (!OB_RequireGap || ob.hasGap) && ob.moveSize >= OB_MinMovePoints);
         
         if (ob.isValid && g_obCount < ArraySize(g_orderBlocks) + 1)
         {
            ArrayResize(g_orderBlocks, g_obCount + 1);
            g_orderBlocks[g_obCount] = ob;
            g_obCount++;
         }
      }
      
      //--- Bearish OB: Last bullish candle before sharp downward move
      if (IsBearishOrderBlock(rates, i))
      {
         OrderBlock ob;
         ob.barIndex = i;
         ob.time = rates[i].time;
         ob.high = rates[i].high;
         ob.low = rates[i].low;
         ob.open = rates[i].open;
         ob.close = rates[i].close;
         ob.direction = -1; // Bearish
         
         //--- Calculate move size
         double moveSize = rates[i].close - rates[i-1].close;
         ob.moveSize = MathAbs(moveSize) / _Point;
         
         //--- Check Take Out
         ob.takeOut = CheckTakeOut(rates, i, -1);
         
         //--- Check Gap
         ob.hasGap = CheckGap(rates, i, -1);
         
         //--- Validate
         ob.isValid = (ob.takeOut && (!OB_RequireGap || ob.hasGap) && ob.moveSize >= OB_MinMovePoints);
         
         if (ob.isValid && g_obCount < ArraySize(g_orderBlocks) + 1)
         {
            ArrayResize(g_orderBlocks, g_obCount + 1);
            g_orderBlocks[g_obCount] = ob;
            g_obCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if bar is part of Bullish Order Block                        |
//+------------------------------------------------------------------+
bool IsBullishOrderBlock(const MqlRates &rates[], int index)
{
   //--- Must be a bearish candle (close < open)
   if (rates[index].close >= rates[index].open)
      return false;
   
   //--- Next candle must move up sharply
   if (rates[index-1].close <= rates[index].close)
      return false;
   
   double moveUp = (rates[index-1].close - rates[index].close) / _Point;
   if (moveUp < OB_MinMovePoints)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is part of Bearish Order Block                        |
//+------------------------------------------------------------------+
bool IsBearishOrderBlock(const MqlRates &rates[], int index)
{
   //--- Must be a bullish candle (close > open)
   if (rates[index].close <= rates[index].open)
      return false;
   
   //--- Next candle must move down sharply
   if (rates[index-1].close >= rates[index].close)
      return false;
   
   double moveDown = (rates[index].close - rates[index-1].close) / _Point;
   if (moveDown < OB_MinMovePoints)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check Take Out - Price must break OB high/low                     |
//+------------------------------------------------------------------+
bool CheckTakeOut(const MqlRates &rates[], int obIndex, int direction)
{
   //--- For Bullish OB: price must break above OB high
   if (direction == 1)
   {
      for (int i = obIndex - 1; i >= MathMax(0, obIndex - 5); i--)
      {
         if (rates[i].high > rates[obIndex].high)
            return true;
      }
   }
   //--- For Bearish OB: price must break below OB low
   else if (direction == -1)
   {
      for (int i = obIndex - 1; i >= MathMax(0, obIndex - 5); i--)
      {
         if (rates[i].low < rates[obIndex].low)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Gap - There must be a gap after OB                           |
//+------------------------------------------------------------------+
bool CheckGap(const MqlRates &rates[], int obIndex, int direction)
{
   if (obIndex < 1) return false;
   
   //--- For Bullish OB: Gap up (next candle low > OB high)
   if (direction == 1)
   {
      double gap = (rates[obIndex - 1].low - rates[obIndex].high) / _Point;
      return gap >= OB_MinGapPoints;
   }
   //--- For Bearish OB: Gap down (next candle high < OB low)
   else if (direction == -1)
   {
      double gap = (rates[obIndex].low - rates[obIndex - 1].high) / _Point;
      return gap >= OB_MinGapPoints;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Order Block Entry Signal                                     |
//+------------------------------------------------------------------+
void CheckOrderBlockEntry()
{
   if (CountTrades() >= MaxTrades)
      return;
   
   double currentBid = ExtSymbolInfo.Bid();
   double currentAsk = ExtSymbolInfo.Ask();
   
   //--- Check each valid OB
   for (int i = 0; i < g_obCount; i++)
   {
      if (!g_orderBlocks[i].isValid)
         continue;
      
      //--- Check if OB is still fresh (not too old)
      int barsSinceOB = iBarShift(_Symbol, PERIOD_CURRENT, g_orderBlocks[i].time);
      if (barsSinceOB > OB_MaxAgeBars)
         continue;
      
      //--- Check if price is in OB zone
      if (g_orderBlocks[i].direction == 1) // Bullish OB
      {
         //--- Price should be in the OB zone for buy entry
         if (currentBid >= g_orderBlocks[i].low && currentBid <= g_orderBlocks[i].high)
         {
            //--- Check if we don't already have a position in this zone
            if (!HasPositionInZone(g_orderBlocks[i].low, g_orderBlocks[i].high))
            {
               OpenBuyOrder(g_orderBlocks[i]);
            }
         }
      }
      else if (g_orderBlocks[i].direction == -1) // Bearish OB
      {
         //--- Price should be in the OB zone for sell entry
         if (currentAsk >= g_orderBlocks[i].low && currentAsk <= g_orderBlocks[i].high)
         {
            //--- Check if we don't already have a position in this zone
            if (!HasPositionInZone(g_orderBlocks[i].low, g_orderBlocks[i].high))
            {
               OpenSellOrder(g_orderBlocks[i]);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there's already a position in the zone                    |
//+------------------------------------------------------------------+
bool HasPositionInZone(double zoneLow, double zoneHigh)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if (entryPrice >= zoneLow && entryPrice <= zoneHigh)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder(const OrderBlock &ob)
{
   double lot = GetLotSize();
   if (lot <= 0) return;
   
   double currentAsk = ExtSymbolInfo.Ask();
   double sl = (StopLossPoints > 0) ? currentAsk - StopLossPoints * _Point : 0;
   double tp = (TakeProfitPoints > 0) ? currentAsk + TakeProfitPoints * _Point : 0;
   
   //--- SL should be below OB low with buffer
   if (sl > 0)
      sl = MathMin(sl, ob.low - OB_SLBuffer * _Point);
   
   if (ExtTrade.Buy(lot, _Symbol, currentAsk, sl, tp, "OB-BUY"))
   {
      g_isBuy = true;
      g_isSell = false;
      Print("OB BUY - Lot: ", lot, " Price: ", currentAsk, " SL: ", sl, " TP: ", tp);
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder(const OrderBlock &ob)
{
   double lot = GetLotSize();
   if (lot <= 0) return;
   
   double currentBid = ExtSymbolInfo.Bid();
   double sl = (StopLossPoints > 0) ? currentBid + StopLossPoints * _Point : 0;
   double tp = (TakeProfitPoints > 0) ? currentBid - TakeProfitPoints * _Point : 0;
   
   //--- SL should be above OB high with buffer
   if (sl > 0)
      sl = MathMax(sl, ob.high + OB_SLBuffer * _Point);
   
   if (ExtTrade.Sell(lot, _Symbol, currentBid, sl, tp, "OB-SELL"))
   {
      g_isSell = true;
      g_isBuy = false;
      Print("OB SELL - Lot: ", lot, " Price: ", currentBid, " SL: ", sl, " TP: ", tp);
   }
}

//+------------------------------------------------------------------+
//| Get Lot Size with Martingale                                       |
//+------------------------------------------------------------------+
double GetLotSize()
{
   int tradeCount = CountTrades();
   double lot = Lots * MathPow(Multiplier, tradeCount);
   
   //--- Apply caps
   if (lot > MaxLotPerOrder)
      lot = MaxLotPerOrder;
   
   //--- Check total lot
   double currentTotal = GetCurrentTotalLot();
   if (currentTotal + lot > MaxTotalLot)
      lot = MaxTotalLot - currentTotal;
   
   //--- Normalize
   lot = NormalizeDouble(lot, 2);
   
   //--- Check margin
   double marginRequired = 0;
   if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, ExtSymbolInfo.Ask(), marginRequired))
      return -1;
   if (AccountInfoDouble(ACCOUNT_MARGIN_FREE) < marginRequired)
      return -1;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Count open trades                                                   |
//+------------------------------------------------------------------+
int CountTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get current total lot                                               |
//+------------------------------------------------------------------+
double GetCurrentTotalLot()
{
   double total = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Trailing Stop for First Order                                      |
//+------------------------------------------------------------------+
void TrailingStopFirstOrder()
{
   if (TrailingPoints == 0) return;
   
   ulong firstTicket = FindFirstOrderTicket();
   if (firstTicket == 0) return;
   
   if (!PositionSelectByTicket(firstTicket))
      return;
   
   if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
       PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return;
   
   ExtSymbolInfo.RefreshRates();
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   
   if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      double distance = ExtSymbolInfo.Bid() - entryPrice;
      if (distance >= TrailingPoints * _Point)
      {
         double newSL = ExtSymbolInfo.Bid() - TrailingPoints * _Point;
         if (currentSL < newSL || currentSL == 0)
         {
            ExtTrade.PositionModify(firstTicket, newSL, currentTP);
         }
      }
   }
   else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      double distance = entryPrice - ExtSymbolInfo.Ask();
      if (distance >= TrailingPoints * _Point)
      {
         double newSL = ExtSymbolInfo.Ask() + TrailingPoints * _Point;
         if (currentSL > newSL || currentSL == 0)
         {
            ExtTrade.PositionModify(firstTicket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find First Order Ticket                                            |
//+------------------------------------------------------------------+
ulong FindFirstOrderTicket()
{
   ulong firstTicket = 0;
   datetime firstTime = TimeCurrent();
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if (openTime < firstTime)
      {
         firstTime = openTime;
         firstTicket = ticket;
      }
   }
   return firstTicket;
}

//+------------------------------------------------------------------+
//| Manage Margin Risk                                                 |
//+------------------------------------------------------------------+
void ManageMarginRisk()
{
   if (!UseMarginRiskManagement) return;
   
   double marginUsage = CalculateMarginUsage();
   int tradeCount = CountTrades();
   bool maxedOut = (tradeCount >= MaxTrades);
   
   //--- Price Runaway Detection
   g_priceRunaway = false;
   if (maxedOut && tradeCount > 0)
   {
      double currentPrice = ExtSymbolInfo.Bid();
      double lastBuy = FindLastBuyPrice();
      double lastSell = FindLastSellPrice();
      
      if (lastBuy > 0 && currentPrice < (lastBuy - (TriggerDistance * _Point * RiskTriggerMultiplier)))
      {
         g_priceRunaway = true;
         Print("=== PRICE RUNAWAY DETECTED (BUY) ===");
      }
      if (lastSell > 0 && currentPrice > (lastSell + (TriggerDistance * _Point * RiskTriggerMultiplier)))
      {
         g_priceRunaway = true;
         Print("=== PRICE RUNAWAY DETECTED (SELL) ===");
      }
   }
   
   bool shouldManage = (marginUsage >= MarginRiskThreshold) ||
                       (maxedOut && g_priceRunaway);
   
   if (!shouldManage) return;
   
   //--- Critical: Force close all
   if (marginUsage >= MarginCriticalThreshold)
   {
      Print("MARGIN CRITICAL: ", DoubleToString(marginUsage, 1), "% - Force closing ALL");
      CloseThisSymbolAll();
      return;
   }
   
   //--- Find farthest order
   ulong farthestTicket = FindFarthestOrderTicket();
   if (farthestTicket > 0)
   {
      double loss = GetPositionLoss(farthestTicket);
      double trailingProfit = CalculateProfitableTrailingProfit();
      bool forceClose = maxedOut || g_priceRunaway;
      
      if (trailingProfit >= loss || forceClose)
      {
         if (forceClose && trailingProfit < loss)
         {
            if (g_priceRunaway)
               Print("FORCING CLOSE (Price Runaway Detected)");
            else
               Print("FORCING CLOSE (MaxTrades Reached)");
         }
         
         ExtTrade.PositionClose(farthestTicket);
         Print("Closed farthest order. Margin: ", DoubleToString(marginUsage, 1), "%");
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Margin Usage %                                           |
//+------------------------------------------------------------------+
double CalculateMarginUsage()
{
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   if (margin + freeMargin == 0)
      return 0;
   
   return (margin / (margin + freeMargin)) * 100.0;
}

//+------------------------------------------------------------------+
//| Find Last Buy Price                                                |
//+------------------------------------------------------------------+
double FindLastBuyPrice()
{
   double lastPrice = 0;
   datetime lastTime = 0;
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if (openTime > lastTime)
         {
            lastTime = openTime;
            lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
   }
   return lastPrice;
}

//+------------------------------------------------------------------+
//| Find Last Sell Price                                               |
//+------------------------------------------------------------------+
double FindLastSellPrice()
{
   double lastPrice = 0;
   datetime lastTime = 0;
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if (openTime > lastTime)
         {
            lastTime = openTime;
            lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
   }
   return lastPrice;
}

//+------------------------------------------------------------------+
//| Find Farthest Order Ticket                                         |
//+------------------------------------------------------------------+
ulong FindFarthestOrderTicket()
{
   ulong farthestTicket = 0;
   double maxDistance = 0;
   double currentPrice = ExtSymbolInfo.Bid();
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double distance = MathAbs(entryPrice - currentPrice) / _Point;
      
      if (distance > maxDistance)
      {
         maxDistance = distance;
         farthestTicket = ticket;
      }
   }
   return farthestTicket;
}

//+------------------------------------------------------------------+
//| Get Position Loss                                                  |
//+------------------------------------------------------------------+
double GetPositionLoss(ulong ticket)
{
   if (!PositionSelectByTicket(ticket))
      return 0;
   
   return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

//+------------------------------------------------------------------+
//| Calculate Profitable Trailing Profit                               |
//+------------------------------------------------------------------+
double CalculateProfitableTrailingProfit()
{
   double totalProfit = 0;
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      if (profit > 0)
         totalProfit += profit;
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Close All Orders for Symbol                                        |
//+------------------------------------------------------------------+
void CloseThisSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;
      
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      ExtTrade.PositionClose(ticket);
   }
   g_isBuy = false;
   g_isSell = false;
}

//+------------------------------------------------------------------+
//| Display Info                                                       |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   int tradeCount = CountTrades();
   double marginUsage = CalculateMarginUsage();
   double totalLot = GetCurrentTotalLot();
   
   string displayText = "";
   displayText += "=== Order Block EA V1.0 ===\n";
   displayText += "Active OBs: " + IntegerToString(g_obCount) + "\n";
   displayText += "Positions: " + IntegerToString(tradeCount) + "/" + IntegerToString(MaxTrades) + "\n";
   displayText += "Total Lot: " + DoubleToString(totalLot, 2) + "\n";
   displayText += "Margin: " + DoubleToString(marginUsage, 1) + "%\n";
   
   if (g_priceRunaway)
      displayText += "*** PRICE RUNAWAY ***\n";
   
   Comment(displayText);
}
//+------------------------------------------------------------------+