//+------------------------------------------------------------------+
//|                           OB_OS_RSI_STOCH_EA_V6.0_M5.mq5        |
//|                           Overbought/Oversold System              |
//|                           M5 Multi-TF Stoch Confirmation          |
//+------------------------------------------------------------------+
#property copyright "EA V6.0 - Multi-TF Stoch Confirmation"
#property link      ""
#property version   "6.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Entry Indicator Settings
input int      RSI_Period = 14;
input int      Stoch_K = 5;
input int      Stoch_D = 3;
input int      Stoch_Slowing = 3;
input int      EMA_Fast = 50;
input int      EMA_Slow = 200;
input int      ADX_Period = 14;

//--- Overbought/Oversold Thresholds
input double   RSI_Oversold = 28.0;
input double   RSI_Overbought = 72.0;
input double   Stoch_Oversold = 18.0;
input double   Stoch_Overbought = 82.0;
input int      ADX_MinStrength = 18;

//--- Multi-Timeframe Confirmation (NEW V6.0)
input bool     UseMTFConfirmation = true;   // Use Multi-TF Confirmation
input int      MinTFAligned = 3;            // Min TFs that must agree (2-5)

//--- Range Filter Settings
input int      RangeBars = 5;
input double   RangeMaxPercent = 0.5;

//--- Risk Management
input double   LotSize = 0.01;
input double   MaxLotPerOrder = 0.05;

//--- Time Filter
input bool     UseHourTrade = true;
input int      StartHour = 8;
input int      EndHour = 22;

//--- Magic Number
input ulong    MagicNumber = 223344;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         ExtTrade;
CSymbolInfo    ExtSymbolInfo;

int g_tradeCount = 0;
bool g_isBuy = false;
bool g_isSell = false;
datetime g_timeLastBar = 0;

// Indicator handles for each timeframe
int g_rsiHandle_M1 = INVALID_HANDLE;
int g_stochHandle_M1 = INVALID_HANDLE;
int g_emaFastHandle_M1 = INVALID_HANDLE;
int g_emaSlowHandle_M1 = INVALID_HANDLE;
int g_adxHandle_M1 = INVALID_HANDLE;

int g_stochHandle_M5 = INVALID_HANDLE;
int g_stochHandle_M15 = INVALID_HANDLE;
int g_stochHandle_M30 = INVALID_HANDLE;
int g_stochHandle_H1 = INVALID_HANDLE;

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

   // M1 Indicators (Entry TF)
   g_rsiHandle_M1 = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);
   g_stochHandle_M1 = iStochastic(_Symbol, PERIOD_M1, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_emaFastHandle_M1 = iMA(_Symbol, PERIOD_M1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle_M1 = iMA(_Symbol, PERIOD_M1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   g_adxHandle_M1 = iADX(_Symbol, PERIOD_M1, ADX_Period);

   // Multi-TF Stochastic Handles
   g_stochHandle_M5 = iStochastic(_Symbol, PERIOD_M5, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_stochHandle_M15 = iStochastic(_Symbol, PERIOD_M15, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_stochHandle_M30 = iStochastic(_Symbol, PERIOD_M30, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_stochHandle_H1 = iStochastic(_Symbol, PERIOD_H1, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

   if (g_rsiHandle_M1 == INVALID_HANDLE || g_stochHandle_M1 == INVALID_HANDLE ||
       g_emaFastHandle_M1 == INVALID_HANDLE || g_emaSlowHandle_M1 == INVALID_HANDLE ||
       g_adxHandle_M1 == INVALID_HANDLE || g_stochHandle_M5 == INVALID_HANDLE ||
       g_stochHandle_M15 == INVALID_HANDLE || g_stochHandle_M30 == INVALID_HANDLE ||
       g_stochHandle_H1 == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== OB_OS_RSI_STOCH_EA_V6.0_M5 (MT5) INITIALIZED ===");
   Print("Multi-TF Stoch Confirmation System");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_rsiHandle_M1 != INVALID_HANDLE) IndicatorRelease(g_rsiHandle_M1);
   if (g_stochHandle_M1 != INVALID_HANDLE) IndicatorRelease(g_stochHandle_M1);
   if (g_emaFastHandle_M1 != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle_M1);
   if (g_emaSlowHandle_M1 != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle_M1);
   if (g_adxHandle_M1 != INVALID_HANDLE) IndicatorRelease(g_adxHandle_M1);
   if (g_stochHandle_M5 != INVALID_HANDLE) IndicatorRelease(g_stochHandle_M5);
   if (g_stochHandle_M15 != INVALID_HANDLE) IndicatorRelease(g_stochHandle_M15);
   if (g_stochHandle_M30 != INVALID_HANDLE) IndicatorRelease(g_stochHandle_M30);
   if (g_stochHandle_H1 != INVALID_HANDLE) IndicatorRelease(g_stochHandle_H1);

   Print("=== OB_OS_RSI_STOCH_EA_V6.0_M5 (MT5) DEINITIALIZED ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtSymbolInfo.RefreshRates();

   if (UseHourTrade)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if (dt.day_of_week == 0 || dt.day_of_week == 6) return;
      if (dt.hour < StartHour || dt.hour > EndHour) return;
   }

   if (!IsNewBar()) return;

   DetectPositions();

   // Check exit first
   if (PositionsTotal() > 0)
      CheckDynamicExit();

   // Check entry
   int signal = CheckEntrySignal();

   if (signal != 0 && g_tradeCount == 0)
      OpenFirstOrder(signal);
}

//+------------------------------------------------------------------+
//| Check if new bar formed (M1)                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentTime[1];
   ArraySetAsSeries(currentTime, true);
   if (CopyTime(_Symbol, PERIOD_M1, 0, 1, currentTime) < 1) return false;

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
//| V6.0: CHECK MULTI-TF STOCH ALIGNMENT                            |
//| For SELL: All TFs Stoch should be heading DOWN from OB           |
//| For BUY: All TFs Stoch should be heading UP from OS              |
//+------------------------------------------------------------------+
int CheckMTFStochAlignment(int direction)
{
   if (!UseMTFConfirmation) return 5; // Skip if disabled

   int aligned = 0;

   // Get M1 Stoch values
   double stochK_M1 = GetIndicatorValue(g_stochHandle_M1, 0, 1);
   double stochD_M1 = GetIndicatorValue(g_stochHandle_M1, 1, 1);

   // Get M5 Stoch values
   double stochK_M5 = GetIndicatorValue(g_stochHandle_M5, 0, 1);
   double stochD_M5 = GetIndicatorValue(g_stochHandle_M5, 1, 1);

   // Get M15 Stoch values
   double stochK_M15 = GetIndicatorValue(g_stochHandle_M15, 0, 1);
   double stochD_M15 = GetIndicatorValue(g_stochHandle_M15, 1, 1);

   // Get M30 Stoch values
   double stochK_M30 = GetIndicatorValue(g_stochHandle_M30, 0, 1);
   double stochD_M30 = GetIndicatorValue(g_stochHandle_M30, 1, 1);

   // Get H1 Stoch values
   double stochK_H1 = GetIndicatorValue(g_stochHandle_H1, 0, 1);
   double stochD_H1 = GetIndicatorValue(g_stochHandle_H1, 1, 1);

   if (direction == -1) // SELL - All should be heading DOWN
   {
      // M1: Stoch K > D (about to cross down) or already overbought
      if (stochK_M1 > stochD_M1 || stochK_M1 > Stoch_Overbought) aligned++;

      // M5: Stoch K > D or overbought
      if (stochK_M5 > stochD_M5 || stochK_M5 > Stoch_Overbought) aligned++;

      // M15: Stoch K > D or overbought
      if (stochK_M15 > stochD_M15 || stochK_M15 > Stoch_Overbought) aligned++;

      // M30: Stoch K > D or overbought
      if (stochK_M30 > stochD_M30 || stochK_M30 > Stoch_Overbought) aligned++;

      // H1: Stoch K > D or overbought
      if (stochK_H1 > stochD_H1 || stochK_H1 > Stoch_Overbought) aligned++;

      Print("MTF SELL CHECK: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
            " M15=", DoubleToString(stochK_M15,1), " M30=", DoubleToString(stochK_M30,1),
            " H1=", DoubleToString(stochK_H1,1), " Aligned=", aligned);
   }
   else if (direction == 1) // BUY - All should be heading UP
   {
      // M1: Stoch K < D (about to cross up) or oversold
      if (stochK_M1 < stochD_M1 || stochK_M1 < Stoch_Oversold) aligned++;

      // M5: Stoch K < D or oversold
      if (stochK_M5 < stochD_M5 || stochK_M5 < Stoch_Oversold) aligned++;

      // M15: Stoch K < D or oversold
      if (stochK_M15 < stochD_M15 || stochK_M15 < Stoch_Oversold) aligned++;

      // M30: Stoch K < D or oversold
      if (stochK_M30 < stochD_M30 || stochK_M30 < Stoch_Oversold) aligned++;

      // H1: Stoch K < D or oversold
      if (stochK_H1 < stochD_H1 || stochK_H1 < Stoch_Oversold) aligned++;

      Print("MTF BUY CHECK: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
            " M15=", DoubleToString(stochK_M15,1), " M30=", DoubleToString(stochK_M30,1),
            " H1=", DoubleToString(stochK_H1,1), " Aligned=", aligned);
   }

   return aligned;
}

//+------------------------------------------------------------------+
//| CHECK IF MARKET IS RANGING                                       |
//+------------------------------------------------------------------+
bool IsMarketRanging()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if (CopyHigh(_Symbol, PERIOD_M1, 1, RangeBars, high) < RangeBars) return true;
   if (CopyLow(_Symbol, PERIOD_M1, 1, RangeBars, low) < RangeBars) return true;

   double highest = high[ArrayMaximum(high)];
   double lowest = low[ArrayMinimum(low)];
   double range = highest - lowest;
   double avgPrice = (highest + lowest) / 2.0;
   double rangePercent = (range / avgPrice) * 100.0;

   if (rangePercent < RangeMaxPercent) return true;

   double adx = GetIndicatorValue(g_adxHandle_M1, 0, 1);
   if (adx < ADX_MinStrength) return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNAL - V6.0                                        |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   if (IsMarketRanging()) return 0;

   // Get M1 indicator values
   double rsi = GetIndicatorValue(g_rsiHandle_M1, 0, 1);
   double stochK = GetIndicatorValue(g_stochHandle_M1, 0, 1);
   double stochD = GetIndicatorValue(g_stochHandle_M1, 1, 1);
   double rsiPrev = GetIndicatorValue(g_rsiHandle_M1, 0, 2);
   double stochKPrev = GetIndicatorValue(g_stochHandle_M1, 0, 2);
   double stochDPrev = GetIndicatorValue(g_stochHandle_M1, 1, 2);

   double emaFast = GetIndicatorValue(g_emaFastHandle_M1, 0, 1);
   double emaSlow = GetIndicatorValue(g_emaSlowHandle_M1, 0, 1);
   double adx = GetIndicatorValue(g_adxHandle_M1, 0, 1);
   double diPlus = GetIndicatorValue(g_adxHandle_M1, 1, 1);
   double diMinus = GetIndicatorValue(g_adxHandle_M1, 2, 1);

   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   double close2 = iClose(_Symbol, PERIOD_M1, 2);
   bool prevBarBullish = (close1 > close2);
   bool prevBarBearish = (close1 < close2);

   //=== BUY SIGNAL ===
   bool rsiOversold = (rsi < RSI_Oversold);
   bool stochOversold = (stochK < Stoch_Oversold);
   bool stochCrossUp = (stochKPrev <= stochDPrev && stochK > stochD);
   bool rsiTurningUp = (rsi > rsiPrev && rsiPrev < RSI_Oversold);

   bool buySignal = (rsiOversold || rsiTurningUp) && stochOversold && stochCrossUp && prevBarBullish;

   //=== SELL SIGNAL ===
   bool rsiOverbought = (rsi > RSI_Overbought);
   bool stochOverbought = (stochK > Stoch_Overbought);
   bool stochCrossDown = (stochKPrev >= stochDPrev && stochK < stochD);
   bool rsiTurningDown = (rsi < rsiPrev && rsiPrev > RSI_Overbought);

   bool sellSignal = (rsiOverbought || rsiTurningDown) && stochOverbought && stochCrossDown && prevBarBearish;

   //=== V6.0: MULTI-TF CONFIRMATION ===
   if (buySignal && !g_isBuy && !g_isSell)
   {
      int aligned = CheckMTFStochAlignment(1);
      if (aligned >= MinTFAligned)
      {
         Print("BUY CONFIRMED: MTF Aligned=", aligned, "/", MinTFAligned);
         return 1;
      }
      else
      {
         Print("BUY REJECTED: MTF Aligned=", aligned, "/", MinTFAligned);
         return 0;
      }
   }

   if (sellSignal && !g_isBuy && !g_isSell)
   {
      int aligned = CheckMTFStochAlignment(-1);
      if (aligned >= MinTFAligned)
      {
         Print("SELL CONFIRMED: MTF Aligned=", aligned, "/", MinTFAligned);
         return -1;
      }
      else
      {
         Print("SELL REJECTED: MTF Aligned=", aligned, "/", MinTFAligned);
         return 0;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| V6.0: DYNAMIC EXIT - Use M1 Stoch for exit                      |
//+------------------------------------------------------------------+
void CheckDynamicExit()
{
   double stochK = GetIndicatorValue(g_stochHandle_M1, 0, 1);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      //=== SELL POSITION ===
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         // TP: Stoch reaches Oversold
         if (stochK < Stoch_Oversold)
         {
            Print("DYNAMIC TP SELL: Stoch=", DoubleToString(stochK, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }

         // SL: Stoch goes back above Overbought
         if (stochK > Stoch_Overbought)
         {
            Print("DYNAMIC SL SELL: Stoch=", DoubleToString(stochK, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }
      }

      //=== BUY POSITION ===
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         // TP: Stoch reaches Overbought
         if (stochK > Stoch_Overbought)
         {
            Print("DYNAMIC TP BUY: Stoch=", DoubleToString(stochK, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }

         // SL: Stoch goes back below Oversold
         if (stochK < Stoch_Oversold)
         {
            Print("DYNAMIC SL BUY: Stoch=", DoubleToString(stochK, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open First Order (No SL/TP - Dynamic Exit)                      |
//+------------------------------------------------------------------+
void OpenFirstOrder(int direction)
{
   double lot = LotSize;
   if (lot > MaxLotPerOrder) lot = MaxLotPerOrder;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (direction == 1)
   {
      if (ExtTrade.Buy(lot, _Symbol, ask, 0, 0, "V6_BUY"))
         Print("OPEN BUY - Lot:", lot);
   }
   else if (direction == -1)
   {
      if (ExtTrade.Sell(lot, _Symbol, bid, 0, 0, "V6_SELL"))
         Print("OPEN SELL - Lot:", lot);
   }
}
//+------------------------------------------------------------------+
