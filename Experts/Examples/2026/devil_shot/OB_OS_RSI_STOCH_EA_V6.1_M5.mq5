//+------------------------------------------------------------------+
//|                           OB_OS_RSI_STOCH_EA_V6.1_M5.mq5        |
//|                           Overbought/Oversold System              |
//|                           M5 Dynamic Exit Based on Entry Stoch    |
//+------------------------------------------------------------------+
#property copyright "EA V6.1 - Entry Stoch Based Exit"
#property link      ""
#property version   "6.01"

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
input int      ADX_MinStrength = 15;

//--- Multi-Timeframe Confirmation
input bool     UseMTFConfirmation = true;
input int      MinTFAligned = 2;

//--- Range Filter Settings
input int      RangeBars = 5;
input double   RangeMaxPercent = 1.0;

//--- Risk Management
input double   LotSize = 0.01;
input double   MaxLotPerOrder = 0.05;

//--- Time Filter
input bool     UseHourTrade = true;
input int      StartHour = 8;
input int      EndHour = 22;

//--- Magic Number
input ulong    MagicNumber = 334455;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         ExtTrade;
CSymbolInfo    ExtSymbolInfo;

int g_tradeCount = 0;
bool g_isBuy = false;
bool g_isSell = false;
datetime g_timeLastBar = 0;

// V6.1: Store entry Stoch value for each ticket
double g_entryStochValues[];

// Indicator handles
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

   // M1 Indicators
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

   Print("=== OB_OS_RSI_STOCH_EA_V6.1_M5 (MT5) INITIALIZED ===");
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

   Print("=== OB_OS_RSI_STOCH_EA_V6.1_M5 (MT5) DEINITIALIZED ===");
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
//| V6.1: Store Entry Stoch Value                                    |
//+------------------------------------------------------------------+
void StoreEntryStoch(ulong ticket)
{
   double stochK = GetIndicatorValue(g_stochHandle_M1, 0, 1);

   int size = ArraySize(g_entryStochValues);
   ArrayResize(g_entryStochValues, size + 1);
   g_entryStochValues[size] = stochK;

   Print("STORED ENTRY STOCH: Ticket=", ticket, " StochK=", DoubleToString(stochK, 2));
}

//+------------------------------------------------------------------+
//| V6.1: Get Entry Stoch Value for Ticket                           |
//+------------------------------------------------------------------+
double GetEntryStoch(ulong ticket)
{
   // Use comment to find entry stoch - store in position comment
   string comment = PositionGetString(POSITION_COMMENT);

   // Parse comment "V6.1_BUY_92.38" or "V6.1_SELL_15.50"
   int underscorePos = StringFind(comment, "_", 7); // Find second underscore
   if (underscorePos > 0)
   {
      string stochStr = StringSubstr(comment, underscorePos + 1);
      return StringToDouble(stochStr);
   }

   return 0;
}

//+------------------------------------------------------------------+
//| V6.1: DYNAMIC EXIT - Based on Entry Stoch Value                 |
//| SELL: Close when Stoch > entry Stoch (price went against us)     |
//| BUY: Close when Stoch < entry Stoch (price went against us)      |
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

      double entryStoch = GetEntryStoch(ticket);

      //=== SELL POSITION ===
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         // Close when Stoch goes above entry value (price rose against us)
         if (entryStoch > 0 && stochK > entryStoch)
         {
            Print("EXIT SELL: Stoch=", DoubleToString(stochK, 2),
                  " > EntryStoch=", DoubleToString(entryStoch, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }
      }

      //=== BUY POSITION ===
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         // Close when Stoch goes below entry value (price fell against us)
         if (entryStoch > 0 && stochK < entryStoch)
         {
            Print("EXIT BUY: Stoch=", DoubleToString(stochK, 2),
                  " < EntryStoch=", DoubleToString(entryStoch, 2));
            ExtTrade.PositionClose(ticket);
            continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK MULTI-TF STOCH ALIGNMENT                                   |
//+------------------------------------------------------------------+
int CheckMTFStochAlignment(int direction)
{
   if (!UseMTFConfirmation) return 5;

   int aligned = 0;

   double stochK_M1 = GetIndicatorValue(g_stochHandle_M1, 0, 1);
   double stochK_M5 = GetIndicatorValue(g_stochHandle_M5, 0, 1);
   double stochK_M15 = GetIndicatorValue(g_stochHandle_M15, 0, 1);
   double stochK_M30 = GetIndicatorValue(g_stochHandle_M30, 0, 1);
   double stochK_H1 = GetIndicatorValue(g_stochHandle_H1, 0, 1);

   if (direction == -1) // SELL
   {
      if (stochK_M1 > Stoch_Overbought) aligned++;
      if (stochK_M5 > Stoch_Overbought) aligned++;
      if (stochK_M15 > Stoch_Overbought) aligned++;
      if (stochK_M30 > Stoch_Overbought) aligned++;
      if (stochK_H1 > Stoch_Overbought) aligned++;

      Print("MTF SELL: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
            " M15=", DoubleToString(stochK_M15,1), " M30=", DoubleToString(stochK_M30,1),
            " H1=", DoubleToString(stochK_H1,1), " Aligned=", aligned);
   }
   else if (direction == 1) // BUY
   {
      if (stochK_M1 < Stoch_Oversold) aligned++;
      if (stochK_M5 < Stoch_Oversold) aligned++;
      if (stochK_M15 < Stoch_Oversold) aligned++;
      if (stochK_M30 < Stoch_Oversold) aligned++;
      if (stochK_H1 < Stoch_Oversold) aligned++;

      Print("MTF BUY: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
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
//| CHECK ENTRY SIGNAL                                                |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   double rsi = GetIndicatorValue(g_rsiHandle_M1, 0, 1);
   double stochK = GetIndicatorValue(g_stochHandle_M1, 0, 1);
   double stochD = GetIndicatorValue(g_stochHandle_M1, 1, 1);
   double rsiPrev = GetIndicatorValue(g_rsiHandle_M1, 0, 2);
   double stochKPrev = GetIndicatorValue(g_stochHandle_M1, 0, 2);
   double stochDPrev = GetIndicatorValue(g_stochHandle_M1, 1, 2);
   double adx = GetIndicatorValue(g_adxHandle_M1, 0, 1);

   Print("ENTRY CHECK: RSI=", DoubleToString(rsi,2),
         " StochK=", DoubleToString(stochK,2),
         " StochD=", DoubleToString(stochD,2),
         " StochKPrev=", DoubleToString(stochKPrev,2),
         " StochDPrev=", DoubleToString(stochDPrev,2),
         " ADX=", DoubleToString(adx,2),
         " Ranging=", IsMarketRanging());

   if (IsMarketRanging()) return 0;

   //=== BUY SIGNAL ===
   bool rsiOversold = (rsi < RSI_Oversold);
   bool rsiTurningUp = (rsi > rsiPrev && rsiPrev < RSI_Oversold);
   bool stochOversold = (stochK < Stoch_Oversold);
   bool stochCrossUp = (stochKPrev <= stochDPrev && stochK > stochD);
   bool stochWasLow = (stochKPrev < Stoch_Oversold);

   // BUY: Stoch in oversold zone + (cross up OR turning up from oversold)
   bool buySignal = !g_isBuy && !g_isSell &&
                    stochOversold &&
                    (stochCrossUp || stochWasLow || rsiTurningUp);

   //=== SELL SIGNAL ===
   bool rsiOverbought = (rsi > RSI_Overbought);
   bool rsiTurningDown = (rsi < rsiPrev && rsiPrev > RSI_Overbought);
   bool stochOverbought = (stochK > Stoch_Overbought);
   bool stochCrossDown = (stochKPrev >= stochDPrev && stochK < stochD);
   bool stochWasHigh = (stochKPrev > Stoch_Overbought);

   // SELL: Stoch in overbought zone + (cross down OR turning down from overbought)
   bool sellSignal = !g_isBuy && !g_isSell &&
                     stochOverbought &&
                     (stochCrossDown || stochWasHigh || rsiTurningDown);

   Print("SIGNALS: buySignal=", buySignal,
         " sellSignal=", sellSignal,
         " rsiOS=", rsiOversold, " rsiTU=", rsiTurningUp,
         " stochOS=", stochOversold, " stochCU=", stochCrossUp,
         " stochWL=", stochWasLow,
         " rsiOB=", rsiOverbought, " rsiTD=", rsiTurningDown,
         " stochOB=", stochOverbought, " stochCD=", stochCrossDown,
         " stochWH=", stochWasHigh);

   //=== MTF CONFIRMATION ===
   if (buySignal)
   {
      int aligned = CheckMTFStochAlignment(1);
      Print("BUY MTF Aligned=", aligned, " need=", MinTFAligned);
      if (aligned >= MinTFAligned)
      {
         Print("BUY CONFIRMED: MTF Aligned=", aligned);
         return 1;
      }
   }

   if (sellSignal)
   {
      int aligned = CheckMTFStochAlignment(-1);
      Print("SELL MTF Aligned=", aligned, " need=", MinTFAligned);
      if (aligned >= MinTFAligned)
      {
         Print("SELL CONFIRMED: MTF Aligned=", aligned);
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Open First Order (V6.1: Store entry Stoch in comment)           |
//+------------------------------------------------------------------+
void OpenFirstOrder(int direction)
{
   double lot = LotSize;
   if (lot > MaxLotPerOrder) lot = MaxLotPerOrder;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stochK = GetIndicatorValue(g_stochHandle_M1, 0, 1);

   // Create comment with entry stoch value
   string comment = "";
   if (direction == 1)
      comment = "V6.1_BUY_" + DoubleToString(stochK, 2);
   else
      comment = "V6.1_SELL_" + DoubleToString(stochK, 2);

   if (direction == 1)
   {
      if (ExtTrade.Buy(lot, _Symbol, ask, 0, 0, comment))
         Print("OPEN BUY - Lot:", lot, " EntryStoch=", DoubleToString(stochK, 2));
   }
   else if (direction == -1)
   {
      if (ExtTrade.Sell(lot, _Symbol, bid, 0, 0, comment))
         Print("OPEN SELL - Lot:", lot, " EntryStoch=", DoubleToString(stochK, 2));
   }
}
//+------------------------------------------------------------------+
