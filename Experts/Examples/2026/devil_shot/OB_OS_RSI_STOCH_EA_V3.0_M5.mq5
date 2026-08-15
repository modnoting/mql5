//+------------------------------------------------------------------+
//|                           OB_OS_RSI_STOCH_EA_V3.0_M5.mq5        |
//|                           Overbought/Oversold System              |
//|                           M5 High Accuracy + Range Filter         |
//+------------------------------------------------------------------+
#property copyright "EA V3.0 - Overbought/Oversold M5 High Accuracy"
#property link      ""
#property version   "3.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Entry Indicator Settings
input int      RSI_Period = 14;           // RSI Period
input int      Stoch_K = 5;              // Stochastic %K Period
input int      Stoch_D = 3;              // Stochastic %D Period
input int      Stoch_Slowing = 3;        // Stochastic Slowing
input int      EMA_Fast = 50;            // EMA Fast Period
input int      EMA_Slow = 200;           // EMA Slow Period
input int      ADX_Period = 14;          // ADX Period
input int      ATR_Period = 14;          // ATR Period

//--- Overbought/Oversold Thresholds (V3.0 Strict)
input double   RSI_Oversold = 25.0;      // RSI Oversold Level (stricter)
input double   RSI_Overbought = 75.0;    // RSI Overbought Level (stricter)
input double   Stoch_Oversold = 12.0;    // Stochastic Oversold Level (stricter)
input double   Stoch_Overbought = 88.0;  // Stochastic Overbought Level (stricter)
input int      ADX_MinStrength = 25;     // Minimum ADX for trend (stricter)

//--- Range Filter Settings (NEW)
input double   ADX_RangeMax = 20.0;      // ADX below this = ranging market (NO TRADE)
input int      BB_Period = 20;           // Bollinger Bands Period
input double   BB_Width_Min = 0.005;     // Min BB Width to trade (avoid squeeze)

//--- Risk Management (V3.0 Conservative)
input double   LotSize = 0.01;           // Base Lot Size
input double   MaxLotPerOrder = 0.05;    // Max Lot Per Order (reduced)
input double   MaxTotalLot = 0.20;       // Max Total Lot (reduced)
input int      StopLossPoints = 2000;    // Stop Loss (Points)
input int      TakeProfitPoints = 3000;  // Take Profit (Points)
input double   Multiplier = 1.0;         // Martingale Multiplier (DISABLED)

//--- Martingale Settings
input int      MaxTrades = 1;            // Max Martingale Orders (DISABLED - only 1 trade)

//--- Trailing Stop
input int      TrailingPoints = 1500;    // Trailing Stop Distance
input bool     UseTrailingStop = true;   // Enable Trailing Stop

//--- Margin Risk Management
input bool     UseMarginRiskManagement = true;
input double   MarginRiskThreshold = 75.0;
input double   MarginCriticalThreshold = 90.0;
input double   TriggerDistance = 500.0;
input double   RiskTriggerMultiplier = 1.5;

//--- Time Filter
input bool     UseHourTrade = true;
input int      StartHour = 8;
input int      EndHour = 22;

//--- Magic Number
input ulong    MagicNumber = 789012;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         ExtTrade;
CSymbolInfo    ExtSymbolInfo;

int g_tradeCount = 0;
bool g_isBuy = false;
bool g_isSell = false;
datetime g_timeLastBar = 0;
bool g_priceRunaway = false;

// Indicator handles
int g_rsiHandle = INVALID_HANDLE;
int g_stochHandle = INVALID_HANDLE;
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
int g_adxHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;
int g_bbHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints(30);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);

   if (!ExtSymbolInfo.Name(_Symbol))
   {
      Print("ERROR: Cannot initialize symbol info");
      return(INIT_FAILED);
   }

   // Create indicator handles
   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   g_stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   g_bbHandle = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, 2.0, PRICE_CLOSE);

   if (g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE ||
       g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE ||
       g_adxHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE ||
       g_bbHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== OB_OS_RSI_STOCH_EA_V3.0_M5 (MT5) INITIALIZED ===");
   Print("High Accuracy M5 System with Range Filter");
   Print("RSI: ", RSI_Period, " | Stoch: ", Stoch_K, ",", Stoch_D, ",", Stoch_Slowing);
   Print("EMA: ", EMA_Fast, "/", EMA_Slow, " | BB: ", BB_Period);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if (g_stochHandle != INVALID_HANDLE) IndicatorRelease(g_stochHandle);
   if (g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if (g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if (g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if (g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if (g_bbHandle != INVALID_HANDLE) IndicatorRelease(g_bbHandle);

   Print("=== OB_OS_RSI_STOCH_EA_V3.0_M5 (MT5) DEINITIALIZED ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtSymbolInfo.RefreshRates();

   if (PositionsTotal() > 0)
      ManageMarginRisk();

   if (UseHourTrade)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if (dt.day_of_week == 0 || dt.day_of_week == 6) return;
      if (dt.hour < StartHour || dt.hour > EndHour)
      {
         if (PositionsTotal() < 1) return;
      }
   }

   if (!IsNewBar()) return;

   if (UseTrailingStop && PositionsTotal() > 0)
      TrailingStopAllOrders();

   DetectPositions();

   int signal = CheckEntrySignal();

   if (signal != 0 && g_tradeCount == 0)
   {
      OpenFirstOrder(signal);
   }
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentTime[1];
   ArraySetAsSeries(currentTime, true);
   if (CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime) < 1) return false;

   if (currentTime[0] == g_timeLastBar) return false;
   g_timeLastBar = currentTime[0];
   return true;
}

//+------------------------------------------------------------------+
//| Detect current positions                                         |
//+------------------------------------------------------------------+
void DetectPositions()
{
   g_tradeCount = 0;
   g_isBuy = false;
   g_isSell = false;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      g_tradeCount++;

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         g_isBuy = true;
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         g_isSell = true;
   }
}

//+------------------------------------------------------------------+
//| Get indicator value from buffer                                  |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int buffer, int shift)
{
   double value[1];
   if (CopyBuffer(handle, buffer, shift, 1, value) < 1) return 0;
   return value[0];
}

//+------------------------------------------------------------------+
//| CHECK IF MARKET IS RANGING (NEW - V3.0)                         |
//+------------------------------------------------------------------+
bool IsMarketRanging()
{
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);

   // If ADX is below threshold, market is ranging - DON'T TRADE
   if (adx < ADX_RangeMax)
   {
      Print("RANGE DETECTED: ADX=", DoubleToString(adx, 2), " < ", DoubleToString(ADX_RangeMax, 2));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| CHECK BOLLINGER BANDS WIDTH (NEW - V3.0)                        |
//+------------------------------------------------------------------+
double GetBBWidth()
{
   double bbUpper = GetIndicatorValue(g_bbHandle, 1, 1);
   double bbLower = GetIndicatorValue(g_bbHandle, 2, 1);
   double bbMiddle = GetIndicatorValue(g_bbHandle, 0, 1);

   if (bbMiddle <= 0) return 0;

   double width = (bbUpper - bbLower) / bbMiddle;
   return width;
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNAL - V3.0 High Accuracy                         |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   //=== V3.0: RANGE FILTER - DON'T TRADE IN RANGING MARKET ===
   if (IsMarketRanging()) return 0;

   //=== V3.0: BOLLINGER BANDS WIDTH FILTER ===
   double bbWidth = GetBBWidth();
   if (bbWidth < BB_Width_Min)
   {
      Print("BB SQUEEZE: Width=", DoubleToString(bbWidth, 4), " < ", DoubleToString(BB_Width_Min, 4));
      return 0;
   }

   // Get indicator values
   double rsi = GetIndicatorValue(g_rsiHandle, 0, 1);
   double stochK = GetIndicatorValue(g_stochHandle, 0, 1);
   double stochD = GetIndicatorValue(g_stochHandle, 1, 1);

   double rsiPrev = GetIndicatorValue(g_rsiHandle, 0, 2);
   double stochKPrev = GetIndicatorValue(g_stochHandle, 0, 2);
   double stochDPrev = GetIndicatorValue(g_stochHandle, 1, 2);

   double emaFast = GetIndicatorValue(g_emaFastHandle, 0, 1);
   double emaSlow = GetIndicatorValue(g_emaSlowHandle, 0, 1);
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);
   double diPlus = GetIndicatorValue(g_adxHandle, 1, 1);
   double diMinus = GetIndicatorValue(g_adxHandle, 2, 1);

   double atr = GetIndicatorValue(g_atrHandle, 0, 1);

   //=== V3.0: CHECK PREVIOUS BAR CLOSURE DIRECTION ===
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double close3 = iClose(_Symbol, PERIOD_CURRENT, 3);
   bool prevBarBullish = (close1 > close2);
   bool prevBarBearish = (close1 < close2);

   //=== BUY SIGNAL: Oversold + Strong Trend + Confirmation ===
   bool buySignal = false;

   bool rsiOversold = (rsi < RSI_Oversold);
   bool stochOversold = (stochK < Stoch_Oversold);
   bool stochCrossUp = (stochKPrev <= stochDPrev && stochK > stochD);
   bool rsiTurningUp = (rsi > rsiPrev && rsiPrev < RSI_Oversold);
   bool trendBuy = (emaFast > emaSlow);
   bool strongTrend = (adx > ADX_MinStrength && diPlus > diMinus);
   bool priceAboveEMA = (close1 > emaFast);

   int buyScore = 0;
   if (rsiOversold || rsiTurningUp) buyScore++;
   if (stochOversold) buyScore++;
   if (stochCrossUp) buyScore++;
   if (trendBuy) buyScore++;
   if (strongTrend) buyScore++;
   if (prevBarBullish) buyScore++;

   // V3.0: Require 5 out of 6 + Stoch Cross + Trend
   if (buyScore >= 5 && stochCrossUp && trendBuy && strongTrend)
      buySignal = true;

   //=== SELL SIGNAL: Overbought + Strong Trend + Confirmation ===
   bool sellSignal = false;

   bool rsiOverbought = (rsi > RSI_Overbought);
   bool stochOverbought = (stochK > Stoch_Overbought);
   bool stochCrossDown = (stochKPrev >= stochDPrev && stochK < stochD);
   bool rsiTurningDown = (rsi < rsiPrev && rsiPrev > RSI_Overbought);
   bool trendSell = (emaFast < emaSlow);
   bool strongTrendSell = (adx > ADX_MinStrength && diMinus > diPlus);
   bool priceBelowEMA = (close1 < emaFast);

   int sellScore = 0;
   if (rsiOverbought || rsiTurningDown) sellScore++;
   if (stochOverbought) sellScore++;
   if (stochCrossDown) sellScore++;
   if (trendSell) sellScore++;
   if (strongTrendSell) sellScore++;
   if (prevBarBearish) sellScore++;

   // V3.0: Require 5 out of 6 + Stoch Cross + Trend
   if (sellScore >= 5 && stochCrossDown && trendSell && strongTrendSell)
      sellSignal = true;

   if (buySignal && !g_isBuy && !g_isSell) return 1;
   if (sellSignal && !g_isBuy && !g_isSell) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Open First Order with SL/TP                                     |
//+------------------------------------------------------------------+
void OpenFirstOrder(int direction)
{
   double lot = LotSize;
   if (lot > MaxLotPerOrder) lot = MaxLotPerOrder;

   double sl = 0, tp = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (direction == 1) // BUY
   {
      sl = ask - StopLossPoints * point;
      tp = ask + TakeProfitPoints * point;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      if (ExtTrade.Buy(lot, _Symbol, ask, sl, tp, "V3_BUY"))
         Print("OPEN BUY - Lot:", lot, " SL:", sl, " TP:", tp);
   }
   else if (direction == -1) // SELL
   {
      sl = bid + StopLossPoints * point;
      tp = bid - TakeProfitPoints * point;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      if (ExtTrade.Sell(lot, _Symbol, bid, sl, tp, "V3_SELL"))
         Print("OPEN SELL - Lot:", lot, " SL:", sl, " TP:", tp);
   }
}

//+------------------------------------------------------------------+
//| Find Last Buy Price                                              |
//+------------------------------------------------------------------+
double FindLastBuyPrice()
{
   double lastPrice = 0;
   datetime lastTime = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

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
//| Find Last Sell Price                                             |
//+------------------------------------------------------------------+
double FindLastSellPrice()
{
   double lastPrice = 0;
   datetime lastTime = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

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
//| Trailing Stop - ALL Orders                                      |
//+------------------------------------------------------------------+
void TrailingStopAllOrders()
{
   if (TrailingPoints == 0) return;

   ExtSymbolInfo.RefreshRates();
   double bid = ExtSymbolInfo.Bid();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double trailDist = TrailingPoints * point;

   int trailed = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double distance = bid - entryPrice;
         if (distance >= trailDist)
         {
            double newSL = NormalizeDouble(bid - trailDist, digits);

            bool shouldModify = (currentSL < newSL || currentSL == 0);

            if (shouldModify)
            {
               if (ExtTrade.PositionModify(ticket, newSL, currentTP))
               {
                  trailed++;
                  Print("TRAIL BUY #", ticket, " Entry:", DoubleToString(entryPrice, digits),
                        " SL:", DoubleToString(currentSL, digits), " -> ", DoubleToString(newSL, digits));
               }
            }
         }
      }
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double distance = entryPrice - bid;
         if (distance >= trailDist)
         {
            double newSL = NormalizeDouble(bid + trailDist, digits);

            bool shouldModify = (currentSL > newSL || currentSL == 0);

            if (shouldModify)
            {
               if (ExtTrade.PositionModify(ticket, newSL, currentTP))
               {
                  trailed++;
                  Print("TRAIL SELL #", ticket, " Entry:", DoubleToString(entryPrice, digits),
                        " SL:", DoubleToString(currentSL, digits), " -> ", DoubleToString(newSL, digits));
               }
            }
         }
      }
   }

   if (trailed > 0)
      Print("TrailingStop: Trailed ", trailed, " orders");
}

//+------------------------------------------------------------------+
//| Manage Margin Risk                                               |
//+------------------------------------------------------------------+
void ManageMarginRisk()
{
   if (!UseMarginRiskManagement) return;

   double marginUsage = CalculateMarginUsage();
   bool maxedOut = (g_tradeCount >= MaxTrades);

   g_priceRunaway = false;
   if (maxedOut && g_tradeCount > 0)
   {
      ExtSymbolInfo.RefreshRates();
      double currentPrice = ExtSymbolInfo.Bid();
      double lastBuy = FindLastBuyPrice();
      double lastSell = FindLastSellPrice();
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if (lastBuy > 0 && currentPrice < (lastBuy - (TriggerDistance * point * RiskTriggerMultiplier)))
      {
         g_priceRunaway = true;
         Print("=== PRICE RUNAWAY DETECTED (BUY) ===");
      }
      if (lastSell > 0 && currentPrice > (lastSell + (TriggerDistance * point * RiskTriggerMultiplier)))
      {
         g_priceRunaway = true;
         Print("=== PRICE RUNAWAY DETECTED (SELL) ===");
      }
   }

   bool shouldManage = (marginUsage >= MarginRiskThreshold) ||
                       (maxedOut && g_priceRunaway);

   if (!shouldManage) return;

   if (marginUsage >= MarginCriticalThreshold)
   {
      Print("MARGIN CRITICAL: ", DoubleToString(marginUsage, 1), "% - Force closing ALL");
      CloseThisSymbolAll();
      return;
   }

   double trailingProfit = CalculateProfitableTrailingProfit();

   ulong farthestTicket = FindFarthestOrderTicket();
   if (farthestTicket > 0)
   {
      double loss = GetPositionLoss(farthestTicket);
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

         if (ExtTrade.PositionClose(farthestTicket))
         {
            Print("Closed farthest order. Margin: ", DoubleToString(marginUsage, 1), "%");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Margin Usage %                                         |
//+------------------------------------------------------------------+
double CalculateMarginUsage()
{
   double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double totalEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if (totalEquity <= 0) return 0;
   return (usedMargin / totalEquity) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate Profitable Trailing Profit                             |
//+------------------------------------------------------------------+
double CalculateProfitableTrailingProfit()
{
   double profit = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double positionProfit = PositionGetDouble(POSITION_PROFIT);
      if (positionProfit > 0)
         profit += positionProfit;
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Find Farthest Order Ticket                                       |
//+------------------------------------------------------------------+
ulong FindFarthestOrderTicket()
{
   ulong farthestTicket = 0;
   double maxDistance = 0;
   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double distance = MathAbs(currentPrice - entryPrice);

      if (distance > maxDistance)
      {
         maxDistance = distance;
         farthestTicket = ticket;
      }
   }
   return farthestTicket;
}

//+------------------------------------------------------------------+
//| Get Position Loss                                                |
//+------------------------------------------------------------------+
double GetPositionLoss(ulong ticket)
{
   if (PositionSelectByTicket(ticket))
      return MathAbs(PositionGetDouble(POSITION_PROFIT));
   return 0;
}

//+------------------------------------------------------------------+
//| Close This Symbol All                                            |
//+------------------------------------------------------------------+
void CloseThisSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ExtTrade.PositionClose(ticket);
   }
}
//+------------------------------------------------------------------+
