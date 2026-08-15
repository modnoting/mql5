//+------------------------------------------------------------------+
//|                          Devilmod-Robot-2026-V5.0.21.mq5         |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "5.021"
#property strict
#property description "Devilmod Robot Martingale EA V5.0.21"
#property description ""
#property description "=== ระบบการทำงาน ==="
#property description "1. Entry Signal: 3-Layer (Trend + Momentum + Price Action)"
#property description "2. Entry Signal: OB/OS (Overbought/Oversold RSI+Stoch MTF)"
#property description "3. Martingale Open: เปิด Order ใหม่เมื่อราคาห่าง >= MartingaleDistancePoints"
#property description "4. Runaway Close: ปิด Order เก่าสุดเมื่อครบทั้ง MaxTrades + ราคาไหลเกิน TriggerDistance"
#property description "5. Trailing Stop: เลื่อน SL สำหรับทุก Order เมื่อกำไร >= TrailingPoints"
#property description "6. UpdateMartingaleTP: ตั้ง TP เท่ากันทุก Order จาก Weighted Average"
#property description "7. Margin Critical: ปิดทั้งหมดเมื่อ Margin >= 90"


#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- CSV Authentication
input string CSV_Password = "123456";
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

//--- Trading Parameters
input double Lots = 0.03;
input int MaxTrades = 15;
input double Multiplier = 1.15;
input int MaxLotDecimals = 2;
input double MaxLotPerOrder = 0.50;
input double MaxTotalLot = 3.00;

//--- TP/SL (Points)
input double TakeProfitPoints = 2000.0;
input double StopLossPoints = 1500.0;
input double TrailingPoints = 600.0;
input double DistancePoints = 1000.0;

//--- Margin Risk Management (V4.0)
input bool UseMarginRiskManagement = true;
input double MarginRiskThreshold = 75.0;
input double MarginCriticalThreshold = 90.0;
input double MinTrailingProfitToOffset = 10.0;

//--- Price Runaway Detection (V4.0)
input double TriggerDistance = 500.0;
input double RiskTriggerMultiplier = 1.5;

//--- Martingale Distance (V4.15 - เปิด Order ใหม่เมื่อราคาห่าง)
input double MartingaleDistancePoints = 1000.0;

//--- Runaway Recovery (V4.01)
input bool UseRunawayRecovery = true;
input double RecoveryDistancePoints = 800.0;

//--- Entry Signal (V4.0 - 3 Layer System)
input bool UseEasyMode = true;
input bool UseADXFilter = false;
input double ADX_Threshold = 20.0;
input int ADX_Period = 14;
input int RSI_Period = 14;
input int RequiredLayers = 1;

//--- OB/OS Entry Signal (V5.0 - From V6.1)
input bool UseOBOS_Signal = true;
input double RSI_Oversold = 28.0;
input double RSI_Overbought = 72.0;
input double Stoch_Oversold = 18.0;
input double Stoch_Overbought = 82.0;
input int OBOS_Stoch_K = 5;
input int OBOS_Stoch_D = 3;
input int OBOS_Stoch_Slowing = 3;
input bool UseMTFConfirmation = true;
input int MinTFAligned = 3;
input int RangeBars = 5;
input double RangeMaxPercent = 0.5;
input int OBOS_ADX_MinStrength = 18;
input bool UseOBOS_TrendFilter = true;

//--- Time Filter
input bool UseHourTrade = true;
input int StartHour = 8;
input int EndHour = 23;
input int MagicNumber = 0;
input int MaxPositionHours = 48;

//--- Display
input int X_trend = 270;
input int Y_trend = 35;

//--- Indicator Parameters (3-Layer System)
int MACD_Fast = 12;
int MACD_Slow = 26;
int MACD_Signal = 9;
int Sto_K = 14;
int Sto_D = 3;
int Sto_Slowing = 3;

//--- MT5 Trade Objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CAccountInfo ExtAccountInfo;

//--- Indicator Handles (3-Layer System)
int HandleMACD_H4, HandleMACD_H1, HandleMACD_M30, HandleMACD_M15, HandleMACD_M5, HandleMACD_M1;
int HandleSto_H4, HandleSto_H1, HandleSto_M30, HandleSto_M15, HandleSto_M5, HandleSto_M1;
int HandleRSI_H4, HandleRSI_H1, HandleRSI_M30, HandleRSI_M15, HandleRSI_M5, HandleRSI_M1;
int HandleATR_H4, HandleATR_H1, HandleATR_M30, HandleATR_M15, HandleATR_M5, HandleATR_M1;
int HandleADX_H4, HandleADX_H1, HandleADX_M30, HandleADX_M15;

//--- Indicator Handles (OB/OS System - From V6.1)
int HandleOBOS_RSI_M1;
int HandleOBOS_Stoch_M1;
int HandleOBOS_ADX_M1;
int HandleOBOS_Stoch_M5, HandleOBOS_Stoch_M15, HandleOBOS_Stoch_M30, HandleOBOS_Stoch_H1;

//--- Global Variables
string EA_Version = "V5.0.21";
datetime g_timeLastBar = 0;
int g_tradeCount = 0;
bool g_isBuy = false;
bool g_isSell = false;
bool g_marginRiskActive = false;
bool g_priceRunaway = false;
bool g_recoveryActive = false;
datetime g_lastRecoveryTime = 0;
datetime g_lastRunawayCloseTime = 0;

//--- CSV Data Structure
struct CSVData
{
   string username;
   string passwordHash;
   datetime expDate;
};

CSVData csvRecords[];
int totalRecords = 0;
bool isCSVAuthenticated = false;
bool isChecked = false;
int csvDaysRemaining = 0;

//+------------------------------------------------------------------+
//| Calculate MD5 Hash                                               |
//+------------------------------------------------------------------+
string MD5Hash(string inputStr)
{
   uchar data[];
   uchar hash[];
   StringToCharArray(inputStr, data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(data, ArraySize(data) - 1);
   uchar key[];
   if (CryptEncode(CRYPT_HASH_MD5, data, key, hash))
   {
      string result = "";
      for (int i = 0; i < ArraySize(hash); i++)
         result += StringFormat("%02x", hash[i]);
      return result;
   }
   return SimpleHash(inputStr);
}

//+------------------------------------------------------------------+
//| Simple Hash (Fallback)                                           |
//+------------------------------------------------------------------+
string SimpleHash(string inputStr)
{
   ulong hashValue = 5381;
   int len = StringLen(inputStr);
   for (int i = 0; i < len; i++)
   {
      string charStr = StringSubstr(inputStr, i, 1);
      uchar charArray[];
      StringToCharArray(charStr, charArray, 0, WHOLE_ARRAY, CP_UTF8);
      if (ArraySize(charArray) > 0)
      {
         ulong c = (ulong)charArray[0];
         hashValue = ((hashValue << 5) + hashValue) + c;
      }
   }
   return StringFormat("%016I64X", hashValue);
}

//+------------------------------------------------------------------+
//| Get Indicator Values (Generic)                                   |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int buffer, int shift)
{
   double value[1];
   if (CopyBuffer(handle, buffer, shift, 1, value) < 1) return 0;
   return value[0];
}

//+------------------------------------------------------------------+
//| Get Indicator Values (3-Layer System)                            |
//+------------------------------------------------------------------+
double GetMACD(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetMACDSignal(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetStochastic(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetRSI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetATR(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetADX(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetPlusDI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetMinusDI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 2, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetClose(ENUM_TIMEFRAMES timeframe, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyClose(_Symbol, timeframe, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetHigh(ENUM_TIMEFRAMES timeframe, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyHigh(_Symbol, timeframe, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

double GetLow(ENUM_TIMEFRAMES timeframe, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyLow(_Symbol, timeframe, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Layer 1: Trend Confirmation (V5.0.20 - MACD Multi-TF + Sign)    |
//+------------------------------------------------------------------+
int CheckTrendLayer()
{
   double macdH4 = GetMACD(HandleMACD_H4, 1);
   double macdH4_prev = GetMACD(HandleMACD_H4, 2);
   double macdH1 = GetMACD(HandleMACD_H1, 1);
   double macdH1_prev = GetMACD(HandleMACD_H1, 2);
   double macdM15 = GetMACD(HandleMACD_M15, 1);
   double macdM15_prev = GetMACD(HandleMACD_M15, 2);

   bool h4_bull = (macdH4 > 0);
   bool h4_bear = (macdH4 < 0);
   bool h4_mom_bull = (macdH4 > macdH4_prev);
   bool h4_mom_bear = (macdH4 < macdH4_prev);

   bool h1_bull = (macdH1 > 0);
   bool h1_bear = (macdH1 < 0);
   bool h1_mom_bull = (macdH1 > macdH1_prev);
   bool h1_mom_bear = (macdH1 < macdH1_prev);

   bool m15_bull = (macdM15 > 0);
   bool m15_bear = (macdM15 < 0);
   bool m15_mom_bull = (macdM15 > macdM15_prev);
   bool m15_mom_bear = (macdM15 < macdM15_prev);

   bool bullishStructure, bearishStructure;

   if (UseEasyMode)
   {
      bullishStructure = h4_bull && h4_mom_bull && h1_bull && (h1_mom_bull || m15_mom_bull);
      bearishStructure = h4_bear && h4_mom_bear && h1_bear && (h1_mom_bear || m15_mom_bear);
   }
   else
   {
      bullishStructure = h4_bull && h4_mom_bull && h1_bull && h1_mom_bull && m15_bull && m15_mom_bull;
      bearishStructure = h4_bear && h4_mom_bear && h1_bear && h1_mom_bear && m15_bear && m15_mom_bear;
   }

   if (!bullishStructure && !bearishStructure)
      return 0;

   if (UseADXFilter)
   {
      double adxH4 = GetADX(HandleADX_H4, 1);
      double adxH1 = GetADX(HandleADX_H1, 1);
      double plusDI_H4 = GetPlusDI(HandleADX_H4, 1);
      double minusDI_H4 = GetMinusDI(HandleADX_H4, 1);
      double plusDI_H1 = GetPlusDI(HandleADX_H1, 1);
      double minusDI_H1 = GetMinusDI(HandleADX_H1, 1);

      bool adxStrong;
      if (UseEasyMode)
         adxStrong = (adxH4 > 15.0 || adxH1 > 15.0);
      else
         adxStrong = (adxH4 > ADX_Threshold && adxH1 > ADX_Threshold);

      if (bullishStructure && adxStrong && (plusDI_H4 > minusDI_H4) && (plusDI_H1 > minusDI_H1))
         return 1;
      if (bearishStructure && adxStrong && (minusDI_H4 > plusDI_H4) && (minusDI_H1 > plusDI_H1))
         return -1;
   }
   else
   {
      if (bullishStructure) return 1;
      if (bearishStructure) return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Layer 2: Momentum Confirmation                                  |
//+------------------------------------------------------------------+
int CheckMomentumLayer(int trendDirection)
{
   double macdH4 = GetMACD(HandleMACD_H4, 1);
   double macdH4_prev = GetMACD(HandleMACD_H4, 2);
   double macdH1 = GetMACD(HandleMACD_H1, 1);
   double macdH1_prev = GetMACD(HandleMACD_H1, 2);
   double macdM15 = GetMACD(HandleMACD_M15, 1);
   double macdM15_prev = GetMACD(HandleMACD_M15, 2);

   double rsiH1 = GetRSI(HandleRSI_H1, 1);
   double rsiM15 = GetRSI(HandleRSI_M15, 1);

   if (trendDirection == 1)
   {
      bool macdBullish, rsiBullish;

      if (UseEasyMode)
      {
         macdBullish = (macdH4 > macdH4_prev) || (macdH1 > macdH1_prev) || (macdM15 > macdM15_prev);
         rsiBullish = (rsiH1 < 75 && rsiM15 < 80);
      }
      else
      {
         macdBullish = (macdH4 > 0 && macdH4 > macdH4_prev) &&
                       (macdH1 > 0 && macdH1 > macdH1_prev) &&
                       (macdM15 > macdM15_prev);
         rsiBullish = (rsiH1 > 50 && rsiH1 < 70) && (rsiM15 > 50 && rsiM15 < 75);
      }

      if (macdBullish && rsiBullish) return 1;
   }
   else if (trendDirection == -1)
   {
      bool macdBearish, rsiBearish;

      if (UseEasyMode)
      {
         macdBearish = (macdH4 < macdH4_prev) || (macdH1 < macdH1_prev) || (macdM15 < macdM15_prev);
         rsiBearish = (rsiH1 > 25 && rsiM15 > 20);
      }
      else
      {
         macdBearish = (macdH4 < 0 && macdH4 < macdH4_prev) &&
                       (macdH1 < 0 && macdH1 < macdH1_prev) &&
                       (macdM15 < macdM15_prev);
         rsiBearish = (rsiH1 < 50 && rsiH1 > 30) && (rsiM15 < 50 && rsiM15 > 25);
      }

      if (macdBearish && rsiBearish) return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Layer 3: Price Action                                           |
//+------------------------------------------------------------------+
int CheckPriceActionLayer(int trendDirection)
{
   double h1_open = iOpen(_Symbol, PERIOD_H1, 1);
   double h1_close = iClose(_Symbol, PERIOD_H1, 1);
   double h1_high = iHigh(_Symbol, PERIOD_H1, 1);
   double h1_low = iLow(_Symbol, PERIOD_H1, 1);
   double h1_body = MathAbs(h1_close - h1_open);
   double h1_range = h1_high - h1_low;

   if (h1_range == 0) return 0;

   double h4_high = GetHigh(PERIOD_H4, 0);
   double h4_low = GetLow(PERIOD_H4, 0);
   double h4_range = h4_high - h4_low;

   ExtSymbolInfo.RefreshRates();
   double ask = ExtSymbolInfo.Ask();
   double bid = ExtSymbolInfo.Bid();

   if (trendDirection == 1)
   {
      bool bullishCandle, nearSupport;

      if (UseEasyMode)
      {
          bullishCandle = (h1_close > h1_open) && (h1_body > h1_range * 0.15);
          nearSupport = (h4_range > 0) && ((bid - h4_low) < h4_range * 0.25) && (GetMACD(HandleMACD_H1, 1) > 0);
       }
       else
       {
          bullishCandle = (h1_close > h1_open) && (h1_body > h1_range * 0.3);
          nearSupport = (h4_range > 0) && ((bid - h4_low) < h4_range * 0.15) && (GetMACD(HandleMACD_H1, 1) > 0);
       }

       if (bullishCandle || nearSupport) return 1;
   }
   else if (trendDirection == -1)
   {
      bool bearishCandle, nearResistance;

      if (UseEasyMode)
      {
          bearishCandle = (h1_close < h1_open) && (h1_body > h1_range * 0.15);
          nearResistance = (h4_range > 0) && ((h4_high - ask) < h4_range * 0.25) && (GetMACD(HandleMACD_H1, 1) < 0);
       }
       else
       {
          bearishCandle = (h1_close < h1_open) && (h1_body > h1_range * 0.3);
          nearResistance = (h4_range > 0) && ((h4_high - ask) < h4_range * 0.15) && (GetMACD(HandleMACD_H1, 1) < 0);
       }

       if (bearishCandle || nearResistance) return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| 3-Layer Entry Signal                                            |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   int trendScore = CheckTrendLayer();
   if (trendScore == 0) return 0;

   int momentumScore = CheckMomentumLayer(trendScore);
   int priceActionScore = CheckPriceActionLayer(trendScore);

   int buyScore = 0, sellScore = 0;

   if (trendScore == 1) buyScore++;
   else if (trendScore == -1) sellScore++;

   if (momentumScore == 1) buyScore++;
   else if (momentumScore == -1) sellScore++;

   if (priceActionScore == 1) buyScore++;
   else if (priceActionScore == -1) sellScore++;

   int required = RequiredLayers;
   if (required < 2) required = 2;
   if (required > 3) required = 3;

   Print("3Layer Signal - BuyScore:", buyScore, " SellScore:", sellScore,
         " Trend:", trendScore, " Momentum:", momentumScore, " PA:", priceActionScore,
         " Required:", required);

   if (buyScore >= required) return 1;
   if (sellScore >= required) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| OB/OS: Check if Market is Ranging (From V6.1)                   |
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

   double adx = GetIndicatorValue(HandleOBOS_ADX_M1, 0, 1);
   if (adx < OBOS_ADX_MinStrength) return true;

   return false;
}

//+------------------------------------------------------------------+
//| OB/OS: Check Multi-TF Stochastic Alignment (From V6.1)          |
//+------------------------------------------------------------------+
int CheckMTFStochAlignment(int direction)
{
   if (!UseMTFConfirmation) return 5;

   int aligned = 0;

   double stochK_M1 = GetIndicatorValue(HandleOBOS_Stoch_M1, 0, 1);
   double stochD_M1 = GetIndicatorValue(HandleOBOS_Stoch_M1, 1, 1);

   double stochK_M5 = GetIndicatorValue(HandleOBOS_Stoch_M5, 0, 1);
   double stochD_M5 = GetIndicatorValue(HandleOBOS_Stoch_M5, 1, 1);

   double stochK_M15 = GetIndicatorValue(HandleOBOS_Stoch_M15, 0, 1);
   double stochD_M15 = GetIndicatorValue(HandleOBOS_Stoch_M15, 1, 1);

   double stochK_M30 = GetIndicatorValue(HandleOBOS_Stoch_M30, 0, 1);
   double stochD_M30 = GetIndicatorValue(HandleOBOS_Stoch_M30, 1, 1);

   double stochK_H1 = GetIndicatorValue(HandleOBOS_Stoch_H1, 0, 1);
   double stochD_H1 = GetIndicatorValue(HandleOBOS_Stoch_H1, 1, 1);

   if (direction == -1) // SELL
   {
      if (stochK_M1 > Stoch_Overbought && stochK_M1 < stochD_M1) aligned++;
      if (stochK_M5 > Stoch_Overbought && stochK_M5 < stochD_M5) aligned++;
      if (stochK_M15 > Stoch_Overbought && stochK_M15 < stochD_M15) aligned++;
      if (stochK_M30 > Stoch_Overbought && stochK_M30 < stochD_M30) aligned++;
      if (stochK_H1 > Stoch_Overbought && stochK_H1 < stochD_H1) aligned++;

      Print("MTF SELL: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
            " M15=", DoubleToString(stochK_M15,1), " M30=", DoubleToString(stochK_M30,1),
            " H1=", DoubleToString(stochK_H1,1), " Aligned=", aligned);
   }
   else if (direction == 1) // BUY
   {
      if (stochK_M1 < Stoch_Oversold && stochK_M1 > stochD_M1) aligned++;
      if (stochK_M5 < Stoch_Oversold && stochK_M5 > stochD_M5) aligned++;
      if (stochK_M15 < Stoch_Oversold && stochK_M15 > stochD_M15) aligned++;
      if (stochK_M30 < Stoch_Oversold && stochK_M30 > stochD_M30) aligned++;
      if (stochK_H1 < Stoch_Oversold && stochK_H1 > stochD_H1) aligned++;

      Print("MTF BUY: M1=", DoubleToString(stochK_M1,1), " M5=", DoubleToString(stochK_M5,1),
            " M15=", DoubleToString(stochK_M15,1), " M30=", DoubleToString(stochK_M30,1),
            " H1=", DoubleToString(stochK_H1,1), " Aligned=", aligned);
   }

   return aligned;
}

//+------------------------------------------------------------------+
//| OB/OS: Check Entry Signal (From V6.1)                           |
//+------------------------------------------------------------------+
int CheckOBOS_Signal()
{
   if (!UseOBOS_Signal) return 0;
   if (IsMarketRanging()) return 0;

   double rsi = GetIndicatorValue(HandleOBOS_RSI_M1, 0, 1);
   double stochK = GetIndicatorValue(HandleOBOS_Stoch_M1, 0, 1);
   double stochD = GetIndicatorValue(HandleOBOS_Stoch_M1, 1, 1);
   double rsiPrev = GetIndicatorValue(HandleOBOS_RSI_M1, 0, 2);
   double stochKPrev = GetIndicatorValue(HandleOBOS_Stoch_M1, 0, 2);
   double stochDPrev = GetIndicatorValue(HandleOBOS_Stoch_M1, 1, 2);

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

   //=== MTF CONFIRMATION ===
   if (buySignal && !g_isBuy && !g_isSell)
   {
      // V5.0.21: OB/OS BUY requires H4+H1 MACD > 0 to prevent counter-trend entries
      if (UseOBOS_TrendFilter)
      {
         double macdH4 = GetMACD(HandleMACD_H4, 1);
         double macdH1 = GetMACD(HandleMACD_H1, 1);
         if (macdH4 <= 0 || macdH1 <= 0)
         {
            Print("OB/OS BUY REJECTED - Trend filter: H4MACD=", DoubleToString(macdH4,1),
                  " H1MACD=", DoubleToString(macdH1,1));
            return 0;
         }
      }

      int aligned = CheckMTFStochAlignment(1);
      if (aligned >= MinTFAligned)
      {
         Print("OB/OS BUY CONFIRMED: RSI=", DoubleToString(rsi,1),
               " StochK=", DoubleToString(stochK,1),
               " MTF Aligned=", aligned);
         return 1;
      }
   }

   if (sellSignal && !g_isBuy && !g_isSell)
   {
      // V5.0.21: OB/OS SELL requires H4+H1 MACD < 0 to prevent counter-trend entries
      if (UseOBOS_TrendFilter)
      {
         double macdH4 = GetMACD(HandleMACD_H4, 1);
         double macdH1 = GetMACD(HandleMACD_H1, 1);
         if (macdH4 >= 0 || macdH1 >= 0)
         {
            Print("OB/OS SELL REJECTED - Trend filter: H4MACD=", DoubleToString(macdH4,1),
                  " H1MACD=", DoubleToString(macdH1,1));
            return 0;
         }
      }

      int aligned = CheckMTFStochAlignment(-1);
      if (aligned >= MinTFAligned)
      {
         Print("OB/OS SELL CONFIRMED: RSI=", DoubleToString(rsi,1),
               " StochK=", DoubleToString(stochK,1),
               " MTF Aligned=", aligned);
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Combined Entry Signal (3-Layer + OB/OS)                         |
//+------------------------------------------------------------------+
int CheckCombinedEntrySignal()
{
   // Try 3-Layer signal first
   int signal3L = CheckEntrySignal();
   if (signal3L != 0) return signal3L;

   // Try OB/OS signal
   int signalOBOS = CheckOBOS_Signal();
   if (signalOBOS != 0) return signalOBOS;

   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Margin Usage                                           |
//+------------------------------------------------------------------+
double CalculateMarginUsage()
{
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if (equity <= 0) return 100.0;
   return (margin / equity) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate Profitable Trailing Profit                             |
//+------------------------------------------------------------------+
double CalculateProfitableTrailingProfit()
{
   double totalProfit = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         double profit = PositionGetDouble(POSITION_PROFIT);
         if (profit > 0)
            totalProfit += profit;
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Find Farthest Order Ticket                                      |
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
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double distance = 0;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            distance = currentPrice - entryPrice;
         else
            distance = entryPrice - currentPrice;

         if (distance > maxDistance)
         {
            maxDistance = distance;
            farthestTicket = ticket;
         }
      }
   }
   return farthestTicket;
}

//+------------------------------------------------------------------+
//| Find Oldest Buy/Sell Ticket                                     |
//+------------------------------------------------------------------+
ulong FindOldestBuyTicket()
{
   ulong oldestTicket = 0;
   datetime earliestTime = TimeCurrent();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
            continue;

         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if (openTime < earliestTime)
         {
            earliestTime = openTime;
            oldestTicket = ticket;
         }
      }
   }
   return oldestTicket;
}

ulong FindOldestSellTicket()
{
   ulong oldestTicket = 0;
   datetime earliestTime = TimeCurrent();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL)
            continue;

         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if (openTime < earliestTime)
         {
            earliestTime = openTime;
            oldestTicket = ticket;
         }
      }
   }
   return oldestTicket;
}

//+------------------------------------------------------------------+
//| Manage Runaway Recovery                                         |
//+------------------------------------------------------------------+
void ManageRunawayRecovery()
{
   if (!UseRunawayRecovery) return;
   if (CountTrades() < MaxTrades) return;

   ExtSymbolInfo.RefreshRates();
   double currentBid = ExtSymbolInfo.Bid();
   double currentAsk = ExtSymbolInfo.Ask();

   if (g_isBuy)
   {
      double lastBuyPrice = FindLastBuyPrice();
      if (lastBuyPrice <= 0) return;

      double distancePoints = (lastBuyPrice - currentBid) / _Point;
      if (distancePoints < RecoveryDistancePoints) return;

      ulong oldestBuy = FindOldestBuyTicket();
      if (oldestBuy == 0) return;

      if (!PositionSelectByTicket(oldestBuy)) return;

      double oldestEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldestProfit = PositionGetDouble(POSITION_PROFIT);

      if (TimeCurrent() - g_lastRecoveryTime < 300) return;

      if (ExtTrade.PositionClose(oldestBuy))
      {
         g_lastRecoveryTime = TimeCurrent();
         g_recoveryActive = true;
         Print("RECOVERY: Closed oldest BUY at ", DoubleToString(oldestEntry, _Digits),
               " | Distance: ", DoubleToString(distancePoints, 0), " pts | Profit: ", DoubleToString(oldestProfit, 2));
      }
   }
   else if (g_isSell)
   {
      double lastSellPrice = FindLastSellPrice();
      if (lastSellPrice <= 0) return;

      double distancePoints = (currentAsk - lastSellPrice) / _Point;
      if (distancePoints < RecoveryDistancePoints) return;

      ulong oldestSell = FindOldestSellTicket();
      if (oldestSell == 0) return;

      if (!PositionSelectByTicket(oldestSell)) return;

      double oldestEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldestProfit = PositionGetDouble(POSITION_PROFIT);

      if (TimeCurrent() - g_lastRecoveryTime < 300) return;

      if (ExtTrade.PositionClose(oldestSell))
      {
         g_lastRecoveryTime = TimeCurrent();
         g_recoveryActive = true;
         Print("RECOVERY: Closed oldest SELL at ", DoubleToString(oldestEntry, _Digits),
               " | Distance: ", DoubleToString(distancePoints, 0), " pts | Profit: ", DoubleToString(oldestProfit, 2));
      }
   }
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
//| Manage Margin Risk (V4.12 - Fixed)                               |
//+------------------------------------------------------------------+
void ManageMarginRisk()
{
   if (!UseMarginRiskManagement) return;

   double marginUsage = CalculateMarginUsage();
   int tradeCount = CountTrades();
   bool maxedOut = (tradeCount >= MaxTrades);

   // Critical margin: Close all
   if (marginUsage >= MarginCriticalThreshold)
   {
      Print("MARGIN CRITICAL: ", DoubleToString(marginUsage, 1), "% - Force closing ALL");
      CloseThisSymbolAll();
      return;
   }

   // ไม่มี position -> ไม่ต้องทำอะไร
   if (tradeCount == 0) return;

   // Price Runaway Detection - ตรวจสอบทุก tick
   g_priceRunaway = false;
   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   // หาราคา Order สุดท้าย (ล่าสุด)
   double lastOrderPrice = 0;
   if (g_isBuy)
      lastOrderPrice = FindLastBuyPrice();
   else if (g_isSell)
      lastOrderPrice = FindLastSellPrice();

   if (lastOrderPrice > 0)
   {
      double distanceFromLast = 0;
      if (g_isBuy)
         distanceFromLast = (lastOrderPrice - currentPrice) / _Point;
      else if (g_isSell)
         distanceFromLast = (currentPrice - lastOrderPrice) / _Point;

      // ราคาไหลจาก Order สุดท้ายเกิน TriggerDistance
      if (distanceFromLast > TriggerDistance)
      {
         g_priceRunaway = true;
         Print("PRICE RUNAWAY DETECTED: Distance from last order: ",
               DoubleToString(distanceFromLast, 0), " points");
      }
   }

   // V4.15: Runaway Close - ต้องครบ 2 เงื่อนไข: maxedOut + ราคาไหลเกิน TriggerDistance
   // ปิด Order เก่าสุด 1 รายการ + Cooldown 120s
   if (maxedOut && g_priceRunaway)
   {
      int cooldownSeconds = 120;
      if (TimeCurrent() - g_lastRunawayCloseTime > cooldownSeconds)
      {
         Print("RUNAWAY CLOSE - MaxTrades (", tradeCount, "/", MaxTrades,
               ") + Distance (", DoubleToString(TriggerDistance, 0), " pts) - Closing oldest order");
         ulong oldestTicket = FindFirstOrderTicket();
         if (oldestTicket > 0)
         {
            if (ExtTrade.PositionClose(oldestTicket))
            {
               g_lastRunawayCloseTime = TimeCurrent();
               Print("SUCCESS: Closed oldest order - Next close in ", cooldownSeconds, "s");
            }
            else
               Print("FAILED: Close oldest order error: ", GetLastError());
            return;
         }
      }
      else
      {
         int remaining = cooldownSeconds - (int)(TimeCurrent() - g_lastRunawayCloseTime);
         Print("RUNAWAY CLOSE detected but cooldown: ", remaining, "s remaining");
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Dynamic TP/SL                                         |
//+------------------------------------------------------------------+
void CalculateDynamicTPSL(double &takeProfit, double &stopLoss)
{
   double atrH4 = GetATR(HandleATR_H4, 1);
   double atrH1 = GetATR(HandleATR_H1, 1);
   double atrM30 = GetATR(HandleATR_M30, 1);

   double avgATR = (atrH4 * 2 + atrH1 + atrM30) / 4.0;
   double atrPoints = avgATR / _Point;

   stopLoss = MathMax(StopLossPoints, atrPoints * 1.8);
   takeProfit = MathMax(TakeProfitPoints, atrPoints * 3.5);

   if (takeProfit < stopLoss * 1.5)
      takeProfit = stopLoss * 1.8;

   stopLoss = MathMin(stopLoss, 2500.0);
   takeProfit = MathMin(takeProfit, 5000.0);
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Distance                                       |
//+------------------------------------------------------------------+
double CalculateDynamicDistance()
{
   double atrH4 = GetATR(HandleATR_H4, 1);
   double atrH1 = GetATR(HandleATR_H1, 1);
   double atrM15 = GetATR(HandleATR_M15, 1);

   double avgATR = (atrH4 * 2 + atrH1 + atrM15) / 4.0;
   double dynamicDist = (avgATR / _Point) * 2.5;

   dynamicDist = MathMax(dynamicDist, 800.0);
   dynamicDist = MathMin(dynamicDist, 3000.0);

   return dynamicDist;
}

//+------------------------------------------------------------------+
//| Get Lots with Caps                                              |
//+------------------------------------------------------------------+
double fGetLots(int orderType)
{
   double lot = Lots;

   lot = NormalizeDouble(Lots * MathPow(Multiplier, g_tradeCount), MaxLotDecimals);

   if (lot > MaxLotPerOrder)
      lot = MaxLotPerOrder;

   double currentTotalLot = GetCurrentTotalLot();
   if (currentTotalLot + lot > MaxTotalLot)
      lot = MaxTotalLot - currentTotalLot;

   ExtSymbolInfo.Refresh();
   double minlot = ExtSymbolInfo.LotsMin();
   double maxlot = ExtSymbolInfo.LotsMax();
   double lotstep = ExtSymbolInfo.LotsStep();

   if (lot < minlot) lot = minlot;
   if (lot > maxlot) lot = maxlot;
   lot = NormalizeDouble(MathFloor(lot / lotstep) * lotstep, MaxLotDecimals);

   if (lot <= 0) return -1;

   double margin_required = 0;
   if (!OrderCalcMargin((ENUM_ORDER_TYPE)orderType, _Symbol, lot, ExtSymbolInfo.Ask(), margin_required))
      return -1;

   if (AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_required)
      return -1;

   return lot;
}

//+------------------------------------------------------------------+
//| Get Current Total Lot                                           |
//+------------------------------------------------------------------+
double GetCurrentTotalLot()
{
   double totalLot = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            totalLot += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return totalLot;
}

//+------------------------------------------------------------------+
//| Count Trades                                                    |
//+------------------------------------------------------------------+
int CountTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ||
                PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Find Last Buy/Sell Price                                        |
//+------------------------------------------------------------------+
double FindLastBuyPrice()
{
   double price = 0;
   ulong lastTicket = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            if (ticket > lastTicket)
            {
               lastTicket = ticket;
               price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return price;
}

double FindLastSellPrice()
{
   double price = 0;
   ulong lastTicket = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            if (ticket > lastTicket)
            {
               lastTicket = ticket;
               price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return price;
}

//+------------------------------------------------------------------+
//| Check Position Time Limit (V5.0.20)                              |
//+------------------------------------------------------------------+
void CheckPositionTimeLimit()
{
   if (MaxPositionHours <= 0) return;

   datetime oldestTime = TimeCurrent();
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if (openTime < oldestTime)
            oldestTime = openTime;
      }
   }

   double hoursOpen = (TimeCurrent() - oldestTime) / 3600.0;
   if (hoursOpen >= MaxPositionHours)
   {
      Print("TIME LIMIT: Position open ", DoubleToString(hoursOpen, 1),
            "h >= ", MaxPositionHours, "h - Closing all");
      CloseThisSymbolAll();
   }
}

//+------------------------------------------------------------------+
//| Close This Symbol All                                           |
//+------------------------------------------------------------------+
void CloseThisSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            ExtTrade.PositionClose(ticket);
            Sleep(500);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Stop/Take Functions                                             |
//+------------------------------------------------------------------+
double StopLong(double price, int slPoints)
{
   if (slPoints == 0) return 0;
   return price - slPoints * _Point;
}

double StopShort(double price, int slPoints)
{
   if (slPoints == 0) return 0;
   return price + slPoints * _Point;
}

double TakeLong(double price, int tpPoints)
{
   if (tpPoints == 0) return 0;
   return price + tpPoints * _Point;
}

double TakeShort(double price, int tpPoints)
{
   if (tpPoints == 0) return 0;
   return price - tpPoints * _Point;
}

//+------------------------------------------------------------------+
//| Calculate Weighted Average Entry Price (V4.06)                  |
//+------------------------------------------------------------------+
double CalculateAverageEntryPrice()
{
   double weightedSum = 0;
   double totalVolume = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);

         weightedSum += entryPrice * volume;
         totalVolume += volume;
      }
   }

   if (totalVolume > 0)
      return NormalizeDouble(weightedSum / totalVolume, _Digits);

   return 0;
}

//+------------------------------------------------------------------+
//| Update All Orders TP (V4.12 - With Error Logging)                |
//+------------------------------------------------------------------+
void UpdateMartingaleTP()
{
   if (CountTrades() < 1)
   {
      Print("UpdateMartingaleTP: No trades");
      return;
   }

   double avgEntry = CalculateAverageEntryPrice();
   if (avgEntry <= 0)
   {
      Print("UpdateMartingaleTP: avgEntry <= 0");
      return;
   }

   double dynamicTP = 0, dynamicSL = 0;
   CalculateDynamicTPSL(dynamicTP, dynamicSL);

   Print("UpdateMartingaleTP - AvgEntry: ", DoubleToString(avgEntry, _Digits),
         " DynamicTP: ", DoubleToString(dynamicTP, 0),
         " DynamicSL: ", DoubleToString(dynamicSL, 0),
         " Positions: ", CountTrades());

   int modified = 0;
   int failed = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
      {
         Print("UpdateMartingaleTP: Cannot select ticket ", ticket);
         continue;
      }

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double tp = TakeLong(avgEntry, (int)dynamicTP);
         if (MathAbs(currentTP - tp) > _Point)
         {
            Print("BUY Ticket:", ticket, " Set TP: ", DoubleToString(currentTP, _Digits),
                  " -> ", DoubleToString(tp, _Digits), " SL: ", DoubleToString(currentSL, _Digits));
            if (ExtTrade.PositionModify(ticket, currentSL, tp))
            {
               modified++;
               Print("BUY Ticket:", ticket, " TP set OK");
            }
            else
            {
               failed++;
               Print("BUY Ticket:", ticket, " FAILED! Error: ", GetLastError());
            }
         }
      }
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double tp = TakeShort(avgEntry, (int)dynamicTP);
         if (MathAbs(currentTP - tp) > _Point)
         {
            Print("SELL Ticket:", ticket, " Set TP: ", DoubleToString(currentTP, _Digits),
                  " -> ", DoubleToString(tp, _Digits), " SL: ", DoubleToString(currentSL, _Digits));
            if (ExtTrade.PositionModify(ticket, currentSL, tp))
            {
               modified++;
               Print("SELL Ticket:", ticket, " TP set OK");
            }
            else
            {
               failed++;
               Print("SELL Ticket:", ticket, " FAILED! Error: ", GetLastError());
            }
         }
      }
   }

   Print("UpdateMartingaleTP Result: Modified=", modified, " Failed=", failed);
}

//+------------------------------------------------------------------+
//| Trailing Stop (V4.18 - ALL Orders)                               |
//+------------------------------------------------------------------+
void TrailingStopFirstOrder()
{
   if (TrailingPoints == 0) return;

   ExtSymbolInfo.RefreshRates();
   double bid = ExtSymbolInfo.Bid();
   double ask = ExtSymbolInfo.Ask();
   double trailDist = TrailingPoints * _Point;

   int trailed = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;

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
            double newSL = bid - trailDist;
            bool slAboveEntry = (currentSL > entryPrice && currentSL > 0);
            bool shouldModify = (currentSL < newSL || currentSL == 0 || slAboveEntry);

            if (shouldModify)
            {
               if (ExtTrade.PositionModify(ticket, newSL, currentTP))
               {
                  trailed++;
                  Print("TRAIL BUY #", ticket, " Entry:", DoubleToString(entryPrice, _Digits),
                        " SL:", DoubleToString(currentSL, _Digits), " -> ", DoubleToString(newSL, _Digits));
               }
            }
         }
      }
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double distance = entryPrice - bid;
         if (distance >= trailDist)
         {
            double newSL = bid + trailDist;
            bool slBelowEntry = (currentSL < entryPrice && currentSL > 0);
            bool shouldModify = (currentSL > newSL || currentSL == 0 || slBelowEntry);

            if (shouldModify)
            {
               if (ExtTrade.PositionModify(ticket, newSL, currentTP))
               {
                  trailed++;
                  Print("TRAIL SELL #", ticket, " Entry:", DoubleToString(entryPrice, _Digits),
                        " SL:", DoubleToString(currentSL, _Digits), " -> ", DoubleToString(newSL, _Digits));
               }
            }
         }
      }
   }

   if (trailed > 0)
      Print("TrailingStop: Trailed ", trailed, " orders");
}

//+------------------------------------------------------------------+
//| Find First Order Ticket (Oldest)                                |
//+------------------------------------------------------------------+
ulong FindFirstOrderTicket()
{
   ulong firstTicket = 0;
   datetime earliestTime = TimeCurrent();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if (openTime < earliestTime)
            {
               earliestTime = openTime;
               firstTicket = ticket;
            }
         }
      }
   }
   return firstTicket;
}

//+------------------------------------------------------------------+
//| Display Info                                                    |
//+------------------------------------------------------------------+
void Display_Info()
{
   string BrokerTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string LocalTime = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);

   string csvStatus = "";
   if (StringLen(CSV_Password) > 0)
   {
      if (isCSVAuthenticated)
         csvStatus = "Auth: OK (" + IntegerToString(csvDaysRemaining) + " days)";
      else
         csvStatus = "Auth: FAILED";
   }

   double marginUsage = CalculateMarginUsage();
   string marginStatus = DoubleToString(marginUsage, 1) + "%";
   if (marginUsage >= MarginCriticalThreshold)
      marginStatus += " CRITICAL!";
   else if (marginUsage >= MarginRiskThreshold)
      marginStatus += " WARNING";

   int signal = CheckCombinedEntrySignal();
   string signalText = "WAIT";
   if (signal == 1) signalText = "BUY";
   else if (signal == -1) signalText = "SELL";

   string recoveryStatus = "";
   if (g_recoveryActive)
      recoveryStatus = "\nRecovery: ACTIVE (Last: " + TimeToString(g_lastRecoveryTime, TIME_SECONDS) + ")";

   Comment(
      "\n=== Devilmod Robot ", EA_Version, " ===",
      "\n", csvStatus,
      "\nSymbol: ", _Symbol,
      "\nBalance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      " | Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
      "\nMargin: ", marginStatus,
      " | Free: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2),
      "\nOrders: ", CountTrades(), " / ", MaxTrades,
      " | Lot: ", DoubleToString(GetCurrentTotalLot(), 2),
      "\nSignal: ", signalText,
      " | OB/OS: ", (UseOBOS_Signal ? "ON" : "OFF"),
      recoveryStatus,
      "\nBroker: ", BrokerTime,
      " | Local: ", LocalTime,
      "\n========================"
   );
}

//+------------------------------------------------------------------+
//| Download CSV                                                    |
//+------------------------------------------------------------------+
bool DownloadCSVFile()
{
   char post[];
   char result[];
   string result_headers;

   int res = WebRequest("GET", GoogleSheetURL, NULL, NULL, 5000, post, 0, result, result_headers);

   if (res == -1)
   {
      int error = GetLastError();
      Print("ERROR: WebRequest failed. Error: ", error);
      if (error == 4060)
         Alert("Add https://docs.google.com to allowed URLs in MT5!");
      return false;
   }

   if (res == 200)
   {
      string content = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return ParseCSVFromMemory(content);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Parse CSV                                                       |
//+------------------------------------------------------------------+
bool ParseCSVFromMemory(string csvContent)
{
   totalRecords = 0;
   ArrayResize(csvRecords, 0);

   string lines[];
   int lineCount = StringSplit(csvContent, '\n', lines);

   if (lineCount < 2) return false;

   for (int i = 1; i < lineCount; i++)
   {
      string line = lines[i];
      StringTrimRight(line);
      StringTrimLeft(line);

      if (StringLen(line) > 0)
      {
         string fields[];
         int count = StringSplit(line, ',', fields);

         if (count >= 6)
         {
            ArrayResize(csvRecords, totalRecords + 1);
            csvRecords[totalRecords].username = fields[2];
            csvRecords[totalRecords].passwordHash = fields[3];
            csvRecords[totalRecords].expDate = StringToTime(fields[5]);
            totalRecords++;
         }
      }
   }
   return totalRecords > 0;
}

//+------------------------------------------------------------------+
//| Validate CSV User                                               |
//+------------------------------------------------------------------+
bool ValidateCSVUser(string inputUsername, string inputPassword)
{
   if (StringLen(inputUsername) == 0 || StringLen(inputPassword) == 0)
      return false;

   string inputPasswordHash = MD5Hash(inputPassword);

   for (int i = 0; i < totalRecords; i++)
   {
      if (csvRecords[i].username == inputUsername &&
          csvRecords[i].passwordHash == inputPasswordHash)
      {
         datetime currentTime = TimeCurrent();
         datetime expireDate = csvRecords[i].expDate;

         if (currentTime > expireDate)
         {
            Alert("Account Expired!");
            isCSVAuthenticated = false;
            return false;
         }

         csvDaysRemaining = (int)((expireDate - currentTime) / 86400);
         isCSVAuthenticated = true;
         return true;
      }
   }

   Alert("Login Failed: Invalid Credentials");
   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtSymbolInfo.Name(_Symbol);
   ExtSymbolInfo.Refresh();
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints(5);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ExtTrade.SetAsyncMode(false);

   string accountUsername = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   if (MQLInfoInteger(MQL_TESTER))
   {
      isCSVAuthenticated = true;
      isChecked = true;
      Print("Strategy Tester detected - skipping CSV authentication");
   }
   else if (StringLen(CSV_Password) > 0)
   {
      if (isCSVAuthenticated && isChecked)
         return INIT_SUCCEEDED;

      if (DownloadCSVFile())
      {
         if (ValidateCSVUser(accountUsername, CSV_Password))
         {
            Alert("Login OK! Days: ", csvDaysRemaining);
            isChecked = true;
         }
         else
         {
            isChecked = false;
            return INIT_FAILED;
         }
      }
      else
      {
         isChecked = false;
         return INIT_FAILED;
      }
   }
   else
   {
      isCSVAuthenticated = true;
      isChecked = true;
   }

   //--- 3-Layer System Indicators
   HandleMACD_H4 = iMACD(_Symbol, PERIOD_H4, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_H1 = iMACD(_Symbol, PERIOD_H1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M30 = iMACD(_Symbol, PERIOD_M30, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M15 = iMACD(_Symbol, PERIOD_M15, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M5 = iMACD(_Symbol, PERIOD_M5, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M1 = iMACD(_Symbol, PERIOD_M1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);

   HandleSto_H4 = iStochastic(_Symbol, PERIOD_H4, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_H1 = iStochastic(_Symbol, PERIOD_H1, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M30 = iStochastic(_Symbol, PERIOD_M30, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M15 = iStochastic(_Symbol, PERIOD_M15, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M5 = iStochastic(_Symbol, PERIOD_M5, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M1 = iStochastic(_Symbol, PERIOD_M1, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);

   HandleRSI_H4 = iRSI(_Symbol, PERIOD_H4, RSI_Period, PRICE_CLOSE);
   HandleRSI_H1 = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   HandleRSI_M30 = iRSI(_Symbol, PERIOD_M30, RSI_Period, PRICE_CLOSE);
   HandleRSI_M15 = iRSI(_Symbol, PERIOD_M15, RSI_Period, PRICE_CLOSE);
   HandleRSI_M5 = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   HandleRSI_M1 = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);

   HandleATR_H4 = iATR(_Symbol, PERIOD_H4, 14);
   HandleATR_H1 = iATR(_Symbol, PERIOD_H1, 14);
   HandleATR_M30 = iATR(_Symbol, PERIOD_M30, 14);
   HandleATR_M15 = iATR(_Symbol, PERIOD_M15, 14);
   HandleATR_M5 = iATR(_Symbol, PERIOD_M5, 14);
   HandleATR_M1 = iATR(_Symbol, PERIOD_M1, 14);

   HandleADX_H4 = iADX(_Symbol, PERIOD_H4, ADX_Period);
   HandleADX_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period);
   HandleADX_M30 = iADX(_Symbol, PERIOD_M30, ADX_Period);
   HandleADX_M15 = iADX(_Symbol, PERIOD_M15, ADX_Period);

   //--- OB/OS System Indicators (From V6.1)
   HandleOBOS_RSI_M1 = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);
   HandleOBOS_Stoch_M1 = iStochastic(_Symbol, PERIOD_M1, OBOS_Stoch_K, OBOS_Stoch_D, OBOS_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleOBOS_ADX_M1 = iADX(_Symbol, PERIOD_M1, ADX_Period);

   HandleOBOS_Stoch_M5 = iStochastic(_Symbol, PERIOD_M5, OBOS_Stoch_K, OBOS_Stoch_D, OBOS_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleOBOS_Stoch_M15 = iStochastic(_Symbol, PERIOD_M15, OBOS_Stoch_K, OBOS_Stoch_D, OBOS_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleOBOS_Stoch_M30 = iStochastic(_Symbol, PERIOD_M30, OBOS_Stoch_K, OBOS_Stoch_D, OBOS_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleOBOS_Stoch_H1 = iStochastic(_Symbol, PERIOD_H1, OBOS_Stoch_K, OBOS_Stoch_D, OBOS_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

   Display_Info();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- 3-Layer System
   if (HandleMACD_H4 != INVALID_HANDLE) IndicatorRelease(HandleMACD_H4);
   if (HandleMACD_H1 != INVALID_HANDLE) IndicatorRelease(HandleMACD_H1);
   if (HandleMACD_M30 != INVALID_HANDLE) IndicatorRelease(HandleMACD_M30);
   if (HandleMACD_M15 != INVALID_HANDLE) IndicatorRelease(HandleMACD_M15);
   if (HandleMACD_M5 != INVALID_HANDLE) IndicatorRelease(HandleMACD_M5);
   if (HandleMACD_M1 != INVALID_HANDLE) IndicatorRelease(HandleMACD_M1);
   if (HandleSto_H4 != INVALID_HANDLE) IndicatorRelease(HandleSto_H4);
   if (HandleSto_H1 != INVALID_HANDLE) IndicatorRelease(HandleSto_H1);
   if (HandleSto_M30 != INVALID_HANDLE) IndicatorRelease(HandleSto_M30);
   if (HandleSto_M15 != INVALID_HANDLE) IndicatorRelease(HandleSto_M15);
   if (HandleSto_M5 != INVALID_HANDLE) IndicatorRelease(HandleSto_M5);
   if (HandleSto_M1 != INVALID_HANDLE) IndicatorRelease(HandleSto_M1);
   if (HandleRSI_H4 != INVALID_HANDLE) IndicatorRelease(HandleRSI_H4);
   if (HandleRSI_H1 != INVALID_HANDLE) IndicatorRelease(HandleRSI_H1);
   if (HandleRSI_M30 != INVALID_HANDLE) IndicatorRelease(HandleRSI_M30);
   if (HandleRSI_M15 != INVALID_HANDLE) IndicatorRelease(HandleRSI_M15);
   if (HandleRSI_M5 != INVALID_HANDLE) IndicatorRelease(HandleRSI_M5);
   if (HandleRSI_M1 != INVALID_HANDLE) IndicatorRelease(HandleRSI_M1);
   if (HandleATR_H4 != INVALID_HANDLE) IndicatorRelease(HandleATR_H4);
   if (HandleATR_H1 != INVALID_HANDLE) IndicatorRelease(HandleATR_H1);
   if (HandleATR_M30 != INVALID_HANDLE) IndicatorRelease(HandleATR_M30);
   if (HandleATR_M15 != INVALID_HANDLE) IndicatorRelease(HandleATR_M15);
   if (HandleATR_M5 != INVALID_HANDLE) IndicatorRelease(HandleATR_M5);
   if (HandleATR_M1 != INVALID_HANDLE) IndicatorRelease(HandleATR_M1);
   if (HandleADX_H4 != INVALID_HANDLE) IndicatorRelease(HandleADX_H4);
   if (HandleADX_H1 != INVALID_HANDLE) IndicatorRelease(HandleADX_H1);
   if (HandleADX_M30 != INVALID_HANDLE) IndicatorRelease(HandleADX_M30);
   if (HandleADX_M15 != INVALID_HANDLE) IndicatorRelease(HandleADX_M15);

   //--- OB/OS System
   if (HandleOBOS_RSI_M1 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_RSI_M1);
   if (HandleOBOS_Stoch_M1 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_Stoch_M1);
   if (HandleOBOS_ADX_M1 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_ADX_M1);
   if (HandleOBOS_Stoch_M5 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_Stoch_M5);
   if (HandleOBOS_Stoch_M15 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_Stoch_M15);
   if (HandleOBOS_Stoch_M30 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_Stoch_M30);
   if (HandleOBOS_Stoch_H1 != INVALID_HANDLE) IndicatorRelease(HandleOBOS_Stoch_H1);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Auth Failed! EA disabled.");
      return;
   }

   Display_Info();

   // V4.17: ManageMarginRisk ทำงานทุก tick
   if (PositionsTotal() > 0)
   {
      ManageMarginRisk();
      CheckPositionTimeLimit();
   }

   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int dayOfWeek = dt.day_of_week;
   int hourOfDay = dt.hour;

   if (dayOfWeek == 0 || dayOfWeek == 6) return;
   if (dayOfWeek == 1 && !(hourOfDay >= 8 && hourOfDay <= 23) && PositionsTotal() < 1)return;
   if (dayOfWeek == 5 && !(hourOfDay >= 1 && hourOfDay <= 3) && PositionsTotal() < 1)  return;
   
   if (UseHourTrade && !(hourOfDay >= StartHour && hourOfDay <= EndHour) && PositionsTotal() < 1)return;

   datetime currentTime[];
   ArraySetAsSeries(currentTime, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);

   if (g_timeLastBar == currentTime[0]) return;
   g_timeLastBar = currentTime[0];

   // V4.13: เรียก TrailingStop และ UpdateMartingaleTP ทุก Bar
   TrailingStopFirstOrder();
   if (CountTrades() > 0)
      UpdateMartingaleTP();

   g_tradeCount = CountTrades();
   g_isBuy = false;
   g_isSell = false;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            g_isBuy = true;
            break;
         }
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            g_isSell = true;
            break;
         }
      }
   }

   // V5.0: Combined Entry Signal (3-Layer + OB/OS)
   int signal = CheckCombinedEntrySignal();

   if (g_tradeCount < MaxTrades)
   {
      ExtSymbolInfo.RefreshRates();
       
       // First order - ต้องมี signal
       if (g_tradeCount == 0)
       {
          double dynamicTP = 0, dynamicSL = 0;
          CalculateDynamicTPSL(dynamicTP, dynamicSL);

          if (signal == 1)
          {
             double lot = fGetLots(ORDER_TYPE_BUY);
             if (lot > 0)
             {
                if (ExtTrade.Buy(lot, _Symbol, ExtSymbolInfo.Ask(),
                                 0, 0,
                                 "V5.0-BUY"))
                {
                   Print("BUY opened - Lot:", lot, " SL: 0 (First Order)");
                   UpdateMartingaleTP();
                }
             }
          }
          else if (signal == -1)
          {
             double lot = fGetLots(ORDER_TYPE_SELL);
             if (lot > 0)
             {
                if (ExtTrade.Sell(lot, _Symbol, ExtSymbolInfo.Bid(),
                                  0, 0,
                                  "V5.0-SELL"))
                {
                   Print("SELL opened - Lot:", lot, " SL: 0 (First Order)");
                   UpdateMartingaleTP();
                }
             }
          }
       }
       // Martingale - เปิดเมื่อราคาห่างจาก Order สุดท้าย >= MartingaleDistancePoints
       else if (g_tradeCount > 0)
       {
          if (g_isBuy)
          {
             double lastBuy = FindLastBuyPrice();
             if (lastBuy > 0)
             {
                double pointDiff = (lastBuy - ExtSymbolInfo.Bid()) / _Point;
                // BUY: ราคาต้องลงมาห่างจาก Order สุดท้าย >= MartingaleDistancePoints
                if (pointDiff >= MartingaleDistancePoints)
                {
                   double lot = fGetLots(ORDER_TYPE_BUY);
                   if (lot > 0)
                   {
                      if (ExtTrade.Buy(lot, _Symbol, ExtSymbolInfo.Ask(),
                                       0, 0,
                                       "V5.0-MART-BUY"))
                      {
                         Print("MART BUY - Lot:", lot, " Distance:", DoubleToString(pointDiff, 0),
                               " >= ", DoubleToString(MartingaleDistancePoints, 0));
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
                double pointDiff = (ExtSymbolInfo.Ask() - lastSell) / _Point;
                // SELL: ราคาต้องขึ้นมาห่างจาก Order สุดท้าย >= MartingaleDistancePoints
                if (pointDiff >= MartingaleDistancePoints)
                {
                   double lot = fGetLots(ORDER_TYPE_SELL);
                   if (lot > 0)
                   {
                      if (ExtTrade.Sell(lot, _Symbol, ExtSymbolInfo.Bid(),
                                        0, 0,
                                        "V5.0-MART-SELL"))
                      {
                         Print("MART SELL - Lot:", lot, " Distance:", DoubleToString(pointDiff, 0),
                               " >= ", DoubleToString(MartingaleDistancePoints, 0));
                         UpdateMartingaleTP();
                      }
                   }
                }
             }
          }
       }
   }
}
//+------------------------------------------------------------------+
