//+------------------------------------------------------------------+
//|                                    OB_OS_RSI_STOCH_EA_V1.0.mq5  |
//|                                    Overbought/Oversold System    |
//|                                    High Accuracy Entry System    |
//+------------------------------------------------------------------+
#property copyright "EA V1.0 - Overbought/Oversold"
#property link      ""
#property version   "1.00"

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
input int      Momentum_Period = 14;     // Momentum Period
input int      ADX_Period = 14;          // ADX Period

//--- Overbought/Oversold Thresholds
input double   RSI_Oversold = 30.0;      // RSI Oversold Level
input double   RSI_Overbought = 70.0;    // RSI Overbought Level
input double   Stoch_Oversold = 20.0;    // Stochastic Oversold Level
input double   Stoch_Overbought = 80.0;  // Stochastic Overbought Level
input int      ADX_MinStrength = 20;     // Minimum ADX for trend confirmation

//--- Risk Management
input double   LotSize = 0.05;           // Base Lot Size
input double   MaxLotPerOrder = 0.50;    // Max Lot Per Order
input double   MaxTotalLot = 3.00;       // Max Total Lot
input int      StopLossPoints = 1500;    // Stop Loss (Points)
input int      TakeProfitPoints = 3000;  // Take Profit (Points)
input double   Multiplier = 1.15;        // Martingale Multiplier

//--- Martingale Settings
input int      MaxTrades = 10;           // Max Martingale Orders
input double   MartingaleDistancePoints = 1500.0;  // Distance for New Order

//--- Trailing Stop
input int      TrailingPoints = 1200;    // Trailing Stop Distance
input bool     UseTrailingStop = true;   // Enable Trailing Stop

//--- Margin Risk Management
input bool     UseMarginRiskManagement = true;  // Enable Margin Risk
input double   MarginRiskThreshold = 75.0;      // Margin Risk Threshold %
input double   MarginCriticalThreshold = 90.0;  // Critical Margin Threshold %
input double   TriggerDistance = 500.0;         // Trigger Distance for Risk
input double   RiskTriggerMultiplier = 1.5;     // Risk Trigger Multiplier

//--- Time Filter
input bool     UseHourTrade = true;      // Use Time Filter
input int      StartHour = 8;            // Start Hour
input int      EndHour = 22;             // End Hour

//--- Magic Number
input ulong    MagicNumber = 123456;     // Magic Number

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
datetime g_lastRecoveryTime = 0;
datetime g_lastRunawayCloseTime = 0;

// Indicator handles
int g_rsiHandle = INVALID_HANDLE;
int g_stochHandle = INVALID_HANDLE;
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
int g_adxHandle = INVALID_HANDLE;
int g_momentumHandle = INVALID_HANDLE;

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
   g_momentumHandle = iMomentum(_Symbol, PERIOD_CURRENT, Momentum_Period, PRICE_CLOSE);

   if (g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE ||
       g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE ||
       g_adxHandle == INVALID_HANDLE || g_momentumHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== OB_OS_RSI_STOCH_EA_V1.0 (MT5) INITIALIZED ===");
   Print("Overbought/Oversold High Accuracy System");
   Print("RSI: ", RSI_Period, " | Stoch: ", Stoch_K, ",", Stoch_D, ",", Stoch_Slowing);
   Print("EMA: ", EMA_Fast, "/", EMA_Slow);
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
   if (g_momentumHandle != INVALID_HANDLE) IndicatorRelease(g_momentumHandle);

   Print("=== OB_OS_RSI_STOCH_EA_V1.0 (MT5) DEINITIALIZED ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtSymbolInfo.RefreshRates();

   // 1. Manage Margin Risk FIRST
   if (PositionsTotal() > 0)
      ManageMarginRisk();

   // 2. Time Filter
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

   // 3. New Bar Check
   if (!IsNewBar()) return;

   // 4. Trailing Stop (ALL orders)
   if (UseTrailingStop && PositionsTotal() > 0)
      TrailingStopAllOrders();

   // 5. Position Detection
   DetectPositions();

   // 6. Entry Signal
   int signal = CheckEntrySignal();

   // 7. Martingale Logic
   if (signal != 0 && g_tradeCount == 0)
   {
      OpenFirstOrder(signal);
   }
   else if (g_tradeCount > 0 && g_tradeCount < MaxTrades)
   {
      ManageMartingale();
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
//| CHECK ENTRY SIGNAL - Overbought/Oversold with Crossover         |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   // Get indicator values
   double rsi = GetIndicatorValue(g_rsiHandle, 0, 1);
   double stochK = GetIndicatorValue(g_stochHandle, 0, 1);
   double stochD = GetIndicatorValue(g_stochHandle, 1, 1);

   // Previous bar values for crossover
   double rsiPrev = GetIndicatorValue(g_rsiHandle, 0, 2);
   double stochKPrev = GetIndicatorValue(g_stochHandle, 0, 2);
   double stochDPrev = GetIndicatorValue(g_stochHandle, 1, 2);

   // Trend Confirmation
   double emaFast = GetIndicatorValue(g_emaFastHandle, 0, 1);
   double emaSlow = GetIndicatorValue(g_emaSlowHandle, 0, 1);
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);
   double diPlus = GetIndicatorValue(g_adxHandle, 1, 1);
   double diMinus = GetIndicatorValue(g_adxHandle, 2, 1);

   // Momentum Confirmation
   double momentum = GetIndicatorValue(g_momentumHandle, 0, 1);

   //=== BUY SIGNAL: Oversold + Crossover Up ===
   bool buySignal = false;

   bool rsiOversold = (rsi < RSI_Oversold);
   bool stochOversold = (stochK < Stoch_Oversold);
   bool stochCrossUp = (stochKPrev <= stochDPrev && stochK > stochD);
   bool rsiTurningUp = (rsi > rsiPrev && rsiPrev < RSI_Oversold);
   bool trendBuy = (emaFast > emaSlow);
   bool strongTrend = (adx > ADX_MinStrength && diPlus > diMinus);
   bool momentumUp = (momentum > 100);

   int buyScore = 0;
   if (rsiOversold || rsiTurningUp) buyScore++;
   if (stochOversold) buyScore++;
   if (stochCrossUp) buyScore++;
   if (trendBuy) buyScore++;
   if (strongTrend) buyScore++;
   if (momentumUp) buyScore++;

   if (buyScore >= 4 && stochCrossUp) buySignal = true;

   //=== SELL SIGNAL: Overbought + Crossover Down ===
   bool sellSignal = false;

   bool rsiOverbought = (rsi > RSI_Overbought);
   bool stochOverbought = (stochK > Stoch_Overbought);
   bool stochCrossDown = (stochKPrev >= stochDPrev && stochK < stochD);
   bool rsiTurningDown = (rsi < rsiPrev && rsiPrev > RSI_Overbought);
   bool trendSell = (emaFast < emaSlow);
   bool strongTrendSell = (adx > ADX_MinStrength && diMinus > diPlus);
   bool momentumDown = (momentum < 100);

   int sellScore = 0;
   if (rsiOverbought || rsiTurningDown) sellScore++;
   if (stochOverbought) sellScore++;
   if (stochCrossDown) sellScore++;
   if (trendSell) sellScore++;
   if (strongTrendSell) sellScore++;
   if (momentumDown) sellScore++;

   if (sellScore >= 4 && stochCrossDown) sellSignal = true;

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

      if (ExtTrade.Buy(lot, _Symbol, ask, sl, tp, "OB_OS_BUY"))
         Print("OPEN BUY - Lot:", lot, " SL:", sl, " TP:", tp);
   }
   else if (direction == -1) // SELL
   {
      sl = bid + StopLossPoints * point;
      tp = bid - TakeProfitPoints * point;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      if (ExtTrade.Sell(lot, _Symbol, bid, sl, tp, "OB_OS_SELL"))
         Print("OPEN SELL - Lot:", lot, " SL:", sl, " TP:", tp);
   }
}

//+------------------------------------------------------------------+
//| Manage Martingale - Distance Based                              |
//+------------------------------------------------------------------+
void ManageMartingale()
{
   if (g_tradeCount >= MaxTrades) return;

   ExtSymbolInfo.RefreshRates();
   double bid = ExtSymbolInfo.Bid();
   double ask = ExtSymbolInfo.Ask();

   if (g_isBuy)
   {
      double lastBuy = FindLastBuyPrice();
      if (lastBuy > 0)
      {
         double pointDiff = (lastBuy - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if (pointDiff >= MartingaleDistancePoints)
         {
            double lot = fGetLots(POSITION_TYPE_BUY);
            if (lot > 0)
            {
               if (ExtTrade.Buy(lot, _Symbol, ask, 0, 0, "MART_BUY"))
               {
                  Print("MART BUY - Distance:", DoubleToString(pointDiff, 0), " Lot:", lot);
                  UpdateMartingaleTP();
               }
            }
         }
      }
   }
   else if (g_isSell)
   {
      double lastSell = FindLastSellPrice();
      if (lastSell > 0)
      {
         double pointDiff = (bid - lastSell) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if (pointDiff >= MartingaleDistancePoints)
         {
            double lot = fGetLots(POSITION_TYPE_SELL);
            if (lot > 0)
            {
               if (ExtTrade.Sell(lot, _Symbol, bid, 0, 0, "MART_SELL"))
               {
                  Print("MART SELL - Distance:", DoubleToString(pointDiff, 0), " Lot:", lot);
                  UpdateMartingaleTP();
               }
            }
         }
      }
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
//| Calculate Lot Size with Multiplier                               |
//+------------------------------------------------------------------+
double fGetLots(ENUM_POSITION_TYPE type)
{
   double lot = NormalizeDouble(LotSize * MathPow(Multiplier, g_tradeCount), 2);

   if (lot > MaxLotPerOrder) lot = MaxLotPerOrder;

   double currentTotal = GetCurrentTotalLot();
   if (currentTotal + lot > MaxTotalLot)
      lot = MaxTotalLot - currentTotal;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if (lot < minLot) lot = minLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Get Current Total Lot                                            |
//+------------------------------------------------------------------+
double GetCurrentTotalLot()
{
   double totalLot = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      totalLot += PositionGetDouble(POSITION_VOLUME);
   }
   return totalLot;
}

//+------------------------------------------------------------------+
//| Update Martingale TP - Weighted Average                         |
//+------------------------------------------------------------------+
void UpdateMartingaleTP()
{
   double avgEntry = CalculateAverageEntryPrice();
   if (avgEntry <= 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tpDistance = TakeProfitPoints * point;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double tp = NormalizeDouble(avgEntry + tpDistance, digits);
         if (MathAbs(currentTP - tp) > point)
            ExtTrade.PositionModify(ticket, currentSL, tp);
      }
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double tp = NormalizeDouble(avgEntry - tpDistance, digits);
         if (MathAbs(currentTP - tp) > point)
            ExtTrade.PositionModify(ticket, currentSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Average Entry Price                                    |
//+------------------------------------------------------------------+
double CalculateAverageEntryPrice()
{
   double weightedSum = 0;
   double totalVolume = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      weightedSum += entryPrice * volume;
      totalVolume += volume;
   }

   if (totalVolume > 0)
      return NormalizeDouble(weightedSum / totalVolume, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   return 0;
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

   // Price Runaway Detection
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