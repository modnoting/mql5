//+------------------------------------------------------------------+
//|                               Devilmod-Robot-2026-V-5.0.5.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "5.05"
#property strict
#property description "Devilmod-Robot-2026 V5.0.5 - XAUUSD Martingale EA"
#property description ""
#property description "=== SYSTEMS USED ==="
#property description "1. Martingale System     - Lot multiplier 1.2x, Max 23 orders"
#property description "2. Dynamic SL (ATR)      - SL ตาม ATR x1.5"
#property description "3. Trailing Stop         - Trail ALL orders"
#property description "4. Adaptive Distance     - ลด distance เมื่อ lot สูง"
#property description "5. Partial Close         - ปิด 50% เมื่อ profit > 500 pts"
#property description "6. Circuit Breaker       - หยุดเมื่อ loss > 5% equity"
#property description "7. Trend Filter (EMA)    - เช็ค EMA50/200 ก่อนเปิด order"
#property description "8. Close on Trend        - ปิดเมื่อ price ข้าม EMA50"
#property description "9. Smart Exit            - Exit เมื่อ MACD cross + RSI extreme"
#property description "10. Trend Alignment      - H4+H1+ADX multi-timeframe confirm"
#property description "11. Entry Timing         - Pullback to EMA21 M15"
#property description "12. Trading Hours Filter - จำกัดเวลา trade"
#property description "13. CSV Authentication   - ตรวจสอบสิทธิ์ผ่าน Google Sheets"
#property description ""
#property description "=== ENTRY CONDITIONS ==="
#property description "Layer 1: Stoch M5 > 30 rising + MACD M1 rising + RSI H1 rising"
#property description "Layer 2: Trend Alignment (H4+H1+ADX) หรือ Trend Filter (EMA50/200)"
#property description "Layer 3: Entry Timing (Pullback to EMA21 M15)"
#property description ""
#property description "=== EXIT CONDITIONS ==="
#property description "1. Partial Close: Profit > 500 pts -> ปิด 50%"
#property description "2. Smart Exit: MACD cross + RSI extreme -> Close position"
#property description "3. Close on Trend: Price ข้าม EMA50 -> Close all"
#property description "4. Circuit Breaker: Loss > 5% -> หยุด trading"
#property description "5. Trailing Stop: Lock profit เมื่อ price ลาก"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

// CSV Authentication Parameters
input string CSV_Password = "";
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

// Trading Parameters
int gi_76 = 1;
bool gi_80 = false;
bool gi_84 = true;
double gd_88 = 1.2;
double g_slippage_96 = 5.0;
input double Lots = 0.01;
double gd_112 = 2.0;
input double g_pips_120 = 3100.0;
double g_pips_128 = 0.0;
input double gd_136 = 2500.0;
input double gd_144 = 1000.0;
input double distance = 1200.0;
double g_pips_152 = 7.0;
input int MaxTrades = 23;
bool gi_164 = false;
double gd_168 = 20.0;
bool gi_176 = true;
bool gi_180 = false;
double gd_184 = 0.0;
bool gi_192 = false;
input bool UseHourTrade = true;
input int StartHour = 1;
input int EndHour = 15;
input int StartHourMonday = 7;
input int EndHourMonday = 10;
input int StartHourFriday = 1;
input int EndHourFriday = 3;
input int g_magic_208 = 0;

// === V5.04 NEW: Risk Management Inputs ===
input bool UseCircuitBreaker = true;  // Circuit Breaker: หยุดเมื่อ loss > X% equity
input double CircuitBreakerPct = 5.0; // Circuit Breaker % (default 5%)
input bool UseTrendFilter = true;     // Trend Filter: เช็ค EMA50/200 ก่อนเปิด order
input bool UseDynamicSL = true;       // Dynamic SL: ใช้ ATR แทน SL ตายตัว
input int ATR_Period = 14;            // ATR Period
input double ATR_Multiplier = 1.5;    // ATR Multiplier for SL
input bool UseAdaptiveDist = true;    // Adaptive Distance: ลด distance เมื่อ lot สูง
input bool UseCloseOnTrend = true;    // Close on Trend: ปิดเมื่อเทรนเปลี่ยน (H1 EMA50)

// === V5.04 NEW: Partial Close ===
input bool UsePartialClose = true;       // Partial Close: ปิดบางส่วนเมื่อ profit
input double PartialCloseProfit = 500.0; // Partial Close Profit (points)
input double PartialCloseRatio = 0.5;    // Partial Close Ratio (0.5 = 50%)

// === V5.05 NEW: Smart Exit ===
input bool UseSmartExit = true;          // Smart Exit: exit เมื่อ momentum fade
input int SmartExit_ATR_Points = 200;    // Smart Exit: min profit (points) to activate
input double SmartExit_MACD_Cross = 0.0; // Smart Exit: MACD cross threshold

// === V5.05 NEW: Trend Alignment (Multi-Timeframe) ===
input bool UseTrendAlignment = true; // Trend Alignment: เช็ค H4/H1/M15
input int ADX_Period = 14;           // ADX Period
input int ADX_Threshold = 20;        // ADX Threshold (trend strength)

// === V5.05 NEW: Entry Timing ===
input bool UseEntryTiming = true;   // Entry Timing: pullback entry
input int Pullback_ATR_Points = 50; // Pullback: min distance from EMA (points)

// Global Variables
double g_price_244;
double g_bid_252;
double g_ask_260;
double gd_268;
double gd_276;
double gd_284;
bool gi_292;
string gs_296 = "Devilmod-Robot-2026 V5.0.5";
datetime g_time_304 = 0;
int gi_308;
int gi_312 = 0;
double gd_316;
int g_pos_324 = 0;
int gi_328;
double gd_332 = 0.0;
bool gi_340 = false;
bool gi_344 = false;
bool gi_348 = false;
int gi_352;
bool gi_356 = false;
datetime g_datetime_360 = 0;
datetime g_datetime_364 = 0;
double gd_368;
double gd_376;
double gd_220;

// CSV Data Structure
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

input int X_trend = 270;
input int Y_trend = 35;

// Indicator Parameters
int MACD_Fast = 12;
int MACD_Slow = 26;
int MACD_Signal = 9;
int Sto_K = 14;
int Sto_D = 3;
int Sto_Slowing = 3;

// MT5 Trade Objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CAccountInfo ExtAccountInfo;
CPositionInfo ExtPositionInfo;

// === V5.04: Only active indicator handles ===
int HandleMACD_M1;
int HandleSto_M5;
int HandleRSI_H1;

// === V5.04 NEW: Trend & Volatility Indicators ===
int HandleEMA50_H1;
int HandleEMA200_H1;
int HandleATR_H1;

// === V5.05 NEW: Smart Exit Indicators ===
int HandleMACD_H1;
int HandleRSI_H1_Exit;

// === V5.05 NEW: Trend Alignment Indicators ===
int HandleEMA50_H4;
int HandleEMA200_H4;
int HandleADX_H1;
int HandleDI_Plus_H1;
int HandleDI_Minus_H1;

// === V5.05 NEW: Entry Timing Indicators ===
int HandleEMA21_M15;

// Timezone Detection
int g_timezone_offset = 0;
bool g_timezone_detected = false;

//+------------------------------------------------------------------+
//| Detect Timezone                                                   |
//+------------------------------------------------------------------+
void DetectTimezone()
{
   if (g_timezone_detected)
      return;
   datetime serverTime = TimeCurrent();
   datetime localTime = TimeLocal();
   g_timezone_offset = (int)(localTime - serverTime);
   g_timezone_detected = true;
   Print("=== Timezone Detected ===");
   Print("Server: ", TimeToString(serverTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   Print("Local:  ", TimeToString(localTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   Print("Offset: ", g_timezone_offset / 3600, "h ", (MathAbs(g_timezone_offset) % 3600) / 60, "m");
}

datetime GetAdjustedTime()
{
   DetectTimezone();
   return TimeCurrent() + g_timezone_offset;
}

int GetAdjustedHour()
{
   datetime adjusted = GetAdjustedTime();
   MqlDateTime dt;
   TimeToStruct(adjusted, dt);
   return dt.hour;
}

int GetAdjustedDayOfWeek()
{
   datetime adjusted = GetAdjustedTime();
   MqlDateTime dt;
   TimeToStruct(adjusted, dt);
   return dt.day_of_week;
}

//+------------------------------------------------------------------+
//| Hash Functions                                                    |
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
//| Indicator Getters                                                 |
//+------------------------------------------------------------------+
double GetMACD(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
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

double GetEMA(int handle, int shift)
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

//+------------------------------------------------------------------+
//| V5.04: Adaptive Distance Function                                 |
//+------------------------------------------------------------------+
int GetAdaptiveDistance(int tradeCount)
{
   if (!UseAdaptiveDist)
      return (int)distance;
   if (tradeCount <= 5)
      return (int)distance;
   if (tradeCount <= 10)
      return (int)(distance * 0.67);
   if (tradeCount <= 15)
      return (int)(distance * 0.42);
   return (int)(distance * 0.25);
}

//+------------------------------------------------------------------+
//| V5.04: Get Dynamic SL from ATR                                    |
//+------------------------------------------------------------------+
double GetDynamicSL()
{
   if (!UseDynamicSL)
      return gd_144;
   double atr = GetATR(HandleATR_H1, 0);
   if (atr <= 0)
      return gd_144;
   double dynamicSL = atr * ATR_Multiplier / _Point;
   if (dynamicSL < 100)
      dynamicSL = 100;
   if (dynamicSL > gd_144 * 3)
      dynamicSL = gd_144 * 3;
   return dynamicSL;
}

//+------------------------------------------------------------------+
//| V5.04: Partial Close                                              |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   if (!UsePartialClose)
      return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);

         ExtSymbolInfo.RefreshRates();

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double profitPts = (ExtSymbolInfo.Bid() - openPrice) / _Point;
            if (profitPts >= PartialCloseProfit)
            {
               double closeVolume = NormalizeDouble(volume * PartialCloseRatio, 2);
               double minLot = ExtSymbolInfo.LotsMin();
               if (closeVolume >= minLot && closeVolume < volume)
               {
                  Print("PARTIAL CLOSE BUY: Profit=", (int)profitPts, " pts, Closing ", closeVolume, " lots");
                  ExtTrade.PositionClosePartial(ticket, closeVolume);
               }
            }
         }
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double profitPts = (openPrice - ExtSymbolInfo.Ask()) / _Point;
            if (profitPts >= PartialCloseProfit)
            {
               double closeVolume = NormalizeDouble(volume * PartialCloseRatio, 2);
               double minLot = ExtSymbolInfo.LotsMin();
               if (closeVolume >= minLot && closeVolume < volume)
               {
                  Print("PARTIAL CLOSE SELL: Profit=", (int)profitPts, " pts, Closing ", closeVolume, " lots");
                  ExtTrade.PositionClosePartial(ticket, closeVolume);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| V5.05: Smart Exit - exit เมื่อ momentum fade                     |
//+------------------------------------------------------------------+
void CheckSmartExit()
{
   if (!UseSmartExit)
      return;
   if (CountTrades() < 1)
      return;

   double macdH1 = GetMACD(HandleMACD_H1, 0);
   double macdH1_prev = GetMACD(HandleMACD_H1, 1);
   double macdH1_prev2 = GetMACD(HandleMACD_H1, 2);
   double rsiH1 = GetRSI(HandleRSI_H1_Exit, 0);

   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double profitPts = 0;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            profitPts = (currentPrice - openPrice) / _Point;
            // Exit BUY: MACD cross down + RSI overbought
            if (profitPts > SmartExit_ATR_Points &&
                macdH1_prev > 0 && macdH1 < 0 && rsiH1 > 70)
            {
               Print("SMART EXIT BUY: MACD cross down, RSI=", DoubleToString(rsiH1, 1),
                     " Profit=", (int)profitPts, " pts");
               ExtTrade.PositionClose(ticket);
            }
         }
         else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            profitPts = (openPrice - currentPrice) / _Point;
            // Exit SELL: MACD cross up + RSI oversold
            if (profitPts > SmartExit_ATR_Points &&
                macdH1_prev < 0 && macdH1 > 0 && rsiH1 < 30)
            {
               Print("SMART EXIT SELL: MACD cross up, RSI=", DoubleToString(rsiH1, 1),
                     " Profit=", (int)profitPts, " pts");
               ExtTrade.PositionClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| V5.05: Trend Alignment - multi-timeframe trend confirmation      |
//+------------------------------------------------------------------+
int GetTrendAlignment()
{
   if (!UseTrendAlignment)
      return 0; // neutral

   // H4 trend
   double ema50_H4 = GetEMA(HandleEMA50_H4, 0);
   double ema200_H4 = GetEMA(HandleEMA200_H4, 0);
   bool h4Up = (ema50_H4 > ema200_H4);
   bool h4Down = (ema50_H4 < ema200_H4);

   // H1 trend
   double ema50_H1 = GetEMA(HandleEMA50_H1, 0);
   double ema200_H1 = GetEMA(HandleEMA200_H1, 0);
   bool h1Up = (ema50_H1 > ema200_H1);
   bool h1Down = (ema50_H1 < ema200_H1);

   // ADX strength
   double adx = 0;
   double diPlus = 0;
   double diMinus = 0;
   double adxBuf[], diPBuf[], diMBuf[];
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(diPBuf, true);
   ArraySetAsSeries(diMBuf, true);

   if (CopyBuffer(HandleADX_H1, 0, 1, 1, adxBuf) > 0)
      adx = adxBuf[0];
   if (CopyBuffer(HandleDI_Plus_H1, 0, 1, 1, diPBuf) > 0)
      diPlus = diPBuf[0];
   if (CopyBuffer(HandleDI_Minus_H1, 0, 1, 1, diMBuf) > 0)
      diMinus = diMBuf[0];

   bool strongTrend = (adx > ADX_Threshold);

   // +1 = BUY aligned, -1 = SELL aligned, 0 = no alignment
   if (h4Up && h1Up && strongTrend && diPlus > diMinus)
      return 1; // BUY aligned
   if (h4Down && h1Down && strongTrend && diMinus > diPlus)
      return -1; // SELL aligned

   return 0; // no alignment
}

//+------------------------------------------------------------------+
//| V5.05: Entry Timing - pullback to EMA                            |
//+------------------------------------------------------------------+
bool IsPullbackBuy()
{
   if (!UseEntryTiming)
      return true;

   double ema21 = GetEMA(HandleEMA21_M15, 0);
   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   // BUY: price pulled back near EMA21 (within Pullback_ATR_Points)
   double dist = (currentPrice - ema21) / _Point;
   if (dist >= 0 && dist <= Pullback_ATR_Points)
      return true;

   return false;
}

bool IsPullbackSell()
{
   if (!UseEntryTiming)
      return true;

   double ema21 = GetEMA(HandleEMA21_M15, 0);
   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Ask();

   // SELL: price pulled back near EMA21 (within Pullback_ATR_Points)
   double dist = (ema21 - currentPrice) / _Point;
   if (dist >= 0 && dist <= Pullback_ATR_Points)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtSymbolInfo.Name(_Symbol);
   ExtSymbolInfo.Refresh();
   gd_284 = ExtSymbolInfo.Spread() * ExtSymbolInfo.Point();

   ExtTrade.SetExpertMagicNumber(g_magic_208);
   ExtTrade.SetDeviationInPoints((int)g_slippage_96);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ExtTrade.SetAsyncMode(false);

   // CSV Authentication
   string accountUsername = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   if (MQLInfoInteger(MQL_TESTER))
   {
      isCSVAuthenticated = true;
      isChecked = true;
      Print("TESTER MODE: CSV authentication bypassed");
   }
   else if (isCSVAuthenticated && isChecked)
   {
      return (INIT_SUCCEEDED);
   }
   else if (StringLen(CSV_Password) > 0)
   {
      Print("=== Starting CSV Authentication ===");
      Print("Account Number: ", accountUsername);
      if (DownloadCSVFile())
      {
         if (ValidateCSVUser(accountUsername, CSV_Password))
         {
            Alert("Login Successful! Account: ", accountUsername);
            Print("AUTHENTICATED: Days remaining = ", csvDaysRemaining);
            isChecked = true;
         }
         else
         {
            Alert("Login Failed! Check your credentials.");
            Print("ERROR: Authentication failed");
            isChecked = false;
            return (INIT_FAILED);
         }
      }
      else
      {
         Alert("Failed to download CSV data.");
         Print("ERROR: Failed to download CSV file");
         isChecked = false;
         return (INIT_FAILED);
      }
   }
   else
   {
      Print("CSV Authentication disabled (Password not provided)");
      isChecked = false;
      isCSVAuthenticated = true;
   }

   // === V5.04: Only active indicator handles ===
   HandleMACD_M1 = iMACD(_Symbol, PERIOD_M1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleSto_M5 = iStochastic(_Symbol, PERIOD_M5, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleRSI_H1 = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);

   // === V5.04 NEW: Trend & Volatility ===
   HandleEMA50_H1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   HandleEMA200_H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   HandleATR_H1 = iATR(_Symbol, PERIOD_H1, ATR_Period);

   // === V5.05 NEW: Smart Exit ===
   HandleMACD_H1 = iMACD(_Symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
   HandleRSI_H1_Exit = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);

   // === V5.05 NEW: Trend Alignment ===
   HandleEMA50_H4 = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   HandleEMA200_H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   HandleADX_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period);
   HandleDI_Plus_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period);  // buffer 1 = +DI
   HandleDI_Minus_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period); // buffer 2 = -DI

   // === V5.05 NEW: Entry Timing ===
   HandleEMA21_M15 = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);

   if (HandleMACD_M1 == INVALID_HANDLE || HandleSto_M5 == INVALID_HANDLE || HandleRSI_H1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return (INIT_FAILED);
   }
   if (HandleEMA50_H1 == INVALID_HANDLE || HandleEMA200_H1 == INVALID_HANDLE || HandleATR_H1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create trend/ATR indicator handles");
      return (INIT_FAILED);
   }
   if (HandleMACD_H1 == INVALID_HANDLE || HandleADX_H1 == INVALID_HANDLE || HandleEMA21_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Smart Exit/Trend Alignment/Entry Timing handles");
      return (INIT_FAILED);
   }

   Display_Info();
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (HandleMACD_M1 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_M1);
   if (HandleSto_M5 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_M5);
   if (HandleRSI_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_H1);
   if (HandleEMA50_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleEMA50_H1);
   if (HandleEMA200_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleEMA200_H1);
   if (HandleATR_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_H1);
   if (HandleMACD_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_H1);
   if (HandleRSI_H1_Exit != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_H1_Exit);
   if (HandleEMA50_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleEMA50_H4);
   if (HandleEMA200_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleEMA200_H4);
   if (HandleADX_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleADX_H1);
   if (HandleDI_Plus_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleDI_Plus_H1);
   if (HandleDI_Minus_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleDI_Minus_H1);
   if (HandleEMA21_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleEMA21_M15);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check CSV Authentication
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Failed! EA is disabled.");
      return;
   }

   // Get indicator values
   double macdM1 = GetMACD(HandleMACD_M1, 0);
   double macdM1_prev = GetMACD(HandleMACD_M1, 1);

   double stoM5 = GetStochastic(HandleSto_M5, 0);
   double stoM5_prev = GetStochastic(HandleSto_M5, 1);

   double rsiH1 = GetRSI(HandleRSI_H1, 0);
   double rsiH1_prev = GetRSI(HandleRSI_H1, 1);

   // === V5.04 NEW: Trend Indicators ===
   double ema50 = GetEMA(HandleEMA50_H1, 0);
   double ema200 = GetEMA(HandleEMA200_H1, 0);

   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   bool is_buy = false, is_sell = false;
   double l_ord_lots_0 = 0.0;
   double l_ord_lots_8 = 0.0;

   // Get adjusted time
   DetectTimezone();
   int dayOfWeek = GetAdjustedDayOfWeek();
   int hourOfDay = GetAdjustedHour();

   // Check day of week
   if (dayOfWeek == 0 || dayOfWeek == 6)
   {
      Display_Info("Do not work on Holidays!");
      return;
   }

   // Trading Hours
   if (UseHourTrade)
   {
      if (dayOfWeek == 5)
      {
         if (!(hourOfDay >= StartHourFriday && hourOfDay <= EndHourFriday))
         {
            if (PositionsTotal() < 1)
            {
               Display_Info("Outside trading hours (Friday)");
               return;
            }
         }
      }
      if (dayOfWeek == 1)
      {
         if (!(hourOfDay >= StartHourMonday && hourOfDay <= EndHourMonday))
         {
            if (PositionsTotal() < 1)
            {
               Display_Info("Outside trading hours (Monday)");
               return;
            }
         }
      }
      if (!(hourOfDay >= StartHour && hourOfDay <= EndHour))
      {
         if (PositionsTotal() < 1)
         {
            Display_Info("Outside trading hours");
            return;
         }
      }
   }

   Display_Info();

   string ls_32 = "false";
   string ls_40 = "false";
   if (gi_192 == false || (gi_192 && ((EndHour > StartHour && (hourOfDay >= StartHour && hourOfDay <= EndHour)) ||
                                      (StartHour > EndHour && !(hourOfDay >= EndHour && hourOfDay <= StartHour)))))
      ls_32 = "true";
   if (gi_192 && ((EndHour > StartHour && !(hourOfDay >= StartHour && hourOfDay <= EndHour)) ||
                  (StartHour > EndHour && (hourOfDay >= EndHour && hourOfDay <= StartHour))))
      ls_40 = "true";

   if (gi_176)
      TrailingAlls((int)gd_136, (int)gd_144, g_price_244);

   // === V5.04 NEW: Partial Close ===
   CheckPartialClose();

   // === V5.05 NEW: Smart Exit ===
   CheckSmartExit();

   if (gi_180)
   {
      if (TimeCurrent() >= gi_308)
      {
         if (PositionsTotal() < 1)
         {
            CloseThisSymbolAll();
            Print("Closed All due to TimeOut");
         }
      }
   }

   // New bar check
   datetime currentTime[];
   ArraySetAsSeries(currentTime, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);

   if (g_time_304 == currentTime[0])
      return;
   g_time_304 = currentTime[0];

   double ld_48 = CalculateProfit();
   if (gi_164)
   {
      if (ld_48 < 0.0 && MathAbs(ld_48) > gd_168 / 100.0 * AccountEquityHigh())
      {
         CloseThisSymbolAll();
         Print("Closed All due to Stop Out");
         gi_356 = false;
      }
   }

   // === V5.04 NEW: Circuit Breaker ===
   if (UseCircuitBreaker)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double maxLoss = equity * CircuitBreakerPct / 100.0;
      if (ld_48 < 0.0 && MathAbs(ld_48) > maxLoss)
      {
         Display_Info("CIRCUIT BREAKER: Loss > " + DoubleToString(CircuitBreakerPct, 1) + "% equity");
         gi_340 = false;
         return;
      }
   }

   gi_328 = CountTrades();
   if (gi_328 == 0)
      gi_292 = false;

   // Check existing positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            gi_344 = true;
            gi_348 = false;
            l_ord_lots_0 = PositionGetDouble(POSITION_VOLUME);
            if (gi_176)
               TrailingAlls((int)gd_136, (int)gd_144, g_price_244);
            break;
         }
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            gi_344 = false;
            gi_348 = true;
            l_ord_lots_8 = PositionGetDouble(POSITION_VOLUME);
            if (gi_176)
               TrailingAlls((int)gd_136, (int)gd_144, g_price_244);
            break;
         }
      }
   }

   // === V5.04 NEW: Close on Trend Change ===
   if (UseCloseOnTrend && PositionsTotal() > 0)
   {
      if (gi_348 && currentPrice > ema50)
      {
         CloseThisSymbolAll();
         Print("TREND CHANGE: Close All SELL - Price crossed above EMA50");
         gi_344 = false;
         gi_348 = false;
         gi_340 = true;
      }
      if (gi_344 && currentPrice < ema50)
      {
         CloseThisSymbolAll();
         Print("TREND CHANGE: Close All BUY - Price crossed below EMA50");
         gi_344 = false;
         gi_348 = false;
         gi_340 = true;
      }
   }

   if (gi_328 > 0 && gi_328 <= MaxTrades)
   {
      ExtSymbolInfo.RefreshRates();
      gd_268 = FindLastBuyPrice();
      gd_276 = FindLastSellPrice();

      // === V5.04: Use Adaptive Distance ===
      int currentDistance = GetAdaptiveDistance(gi_328);

      if (gi_344 && gd_268 - ExtSymbolInfo.Ask() >= g_pips_152 * ExtSymbolInfo.Point())
         gi_340 = true;
      if (gi_348 && ExtSymbolInfo.Bid() - gd_276 >= g_pips_152 * ExtSymbolInfo.Point())
         gi_340 = true;
   }

   if (gi_328 < 1)
   {
      gi_348 = false;
      gi_344 = false;
      gi_340 = true;
      gd_220 = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   if (gi_340)
   {
      gd_268 = FindLastBuyPrice();
      gd_276 = FindLastSellPrice();

      // === V5.04: Dynamic SL ===
      double dynamicSL = GetDynamicSL();

      if (gi_348)
      {
         if (gi_80 || ls_40 == "true")
         {
            fOrderCloseMarket(false, true);
            gd_316 = NormalizeDouble(gd_88 * l_ord_lots_8, (int)gd_112);
         }
         else
            gd_316 = fGetLots(ORDER_TYPE_SELL);

         if (gi_84 && ls_32 == "true")
         {
            gi_312 = gi_328;
            ExtSymbolInfo.RefreshRates();
            double LastSellPrice = FindLastSellPrice();
            double currentPriceSell = ExtSymbolInfo.Ask();

            if (gd_316 > 0.0)
            {
               if (LastSellPrice > 0)
               {
                  int currentDist = GetAdaptiveDistance(gi_328);
                  double pointDiffSell = MathAbs(currentPriceSell - LastSellPrice) / ExtSymbolInfo.Point();
                  Print("SELL Check - LastPrice: ", LastSellPrice,
                        " CurrentPrice: ", currentPriceSell,
                        " PointDiff: ", (int)pointDiffSell,
                        " Required Distance: ", currentDist);

                  if (pointDiffSell < currentDist)
                  {
                     Comment("Waiting for SELL distance... PointDiff=", (int)pointDiffSell,
                             " < Required=", currentDist);
                     return;
                  }
               }

               ExtSymbolInfo.RefreshRates();
               Print("Opening SELL order - Lot: ", gd_316, " Price: ", ExtSymbolInfo.Bid(), " DynamicSL: ", (int)dynamicSL);

               if (ExtTrade.Sell(gd_316, _Symbol, ExtSymbolInfo.Bid(),
                                 StopShort(ExtSymbolInfo.Ask(), (int)dynamicSL),
                                 TakeShort(ExtSymbolInfo.Bid(), (int)g_pips_120),
                                 gs_296 + "-" + IntegerToString(gi_312)))
               {
                  Print("SELL order opened successfully!");
                  gd_276 = FindLastSellPrice();
                  gi_340 = false;
                  gi_356 = true;
               }
               else
               {
                  Print("Error opening SELL: ", GetLastError());
                  return;
               }
            }
         }
      }
      else
      {
         if (gi_344)
         {
            if (gi_80 || ls_40 == "true")
            {
               fOrderCloseMarket(true, false);
               gd_316 = NormalizeDouble(gd_88 * l_ord_lots_0, (int)gd_112);
            }
            else
               gd_316 = fGetLots(ORDER_TYPE_BUY);

            if (gi_84 && ls_32 == "true")
            {
               gi_312 = gi_328;
               ExtSymbolInfo.RefreshRates();
               double LastBuyPrice = FindLastBuyPrice();
               double currentPriceBuy = ExtSymbolInfo.Bid();

               if (gd_316 > 0.0)
               {
                  if (LastBuyPrice > 0)
                  {
                     int currentDist = GetAdaptiveDistance(gi_328);
                     double pointDiffBuy = MathAbs(currentPriceBuy - LastBuyPrice) / ExtSymbolInfo.Point();
                     Print("BUY Check - LastPrice: ", LastBuyPrice,
                           " CurrentPrice: ", currentPriceBuy,
                           " PointDiff: ", (int)pointDiffBuy,
                           " Required Distance: ", currentDist);

                     if (pointDiffBuy < currentDist)
                     {
                        Comment("Waiting for BUY distance... PointDiff=", (int)pointDiffBuy,
                                " < Required=", currentDist);
                        return;
                     }
                  }

                  ExtSymbolInfo.RefreshRates();
                  Print("Opening BUY order - Lot: ", gd_316, " Price: ", ExtSymbolInfo.Ask(), " DynamicSL: ", (int)dynamicSL);

                  if (ExtTrade.Buy(gd_316, _Symbol, ExtSymbolInfo.Ask(),
                                   StopLong(ExtSymbolInfo.Bid(), (int)dynamicSL),
                                   TakeLong(ExtSymbolInfo.Ask(), (int)g_pips_120),
                                   gs_296 + "-" + IntegerToString(gi_312)))
                  {
                     Print("BUY order opened successfully!");
                     gd_268 = FindLastBuyPrice();
                     gi_340 = false;
                     gi_356 = true;
                  }
                  else
                  {
                     Print("Error opening BUY: ", GetLastError());
                     return;
                  }
               }
            }
         }
      }
   }

   // === V5.04: Entry Conditions with Trend Filter ===
   bool trendUp = (ema50 > ema200) && (currentPrice > ema50);
   bool trendDown = (ema50 < ema200) && (currentPrice < ema50);

   // === V5.05 NEW: Trend Alignment ===
   int trendAlign = GetTrendAlignment();

   if (PositionsTotal() == 0)
   {
      bool buySignal = stoM5 > 30 && stoM5 > stoM5_prev &&
                       macdM1 > macdM1_prev &&
                       rsiH1 > rsiH1_prev;

      bool sellSignal = stoM5 < 70 && stoM5 < stoM5_prev &&
                        macdM1 < macdM1_prev &&
                        rsiH1 < rsiH1_prev;

      // === V5.05: Use Trend Alignment if enabled ===
      if (UseTrendAlignment)
      {
         if (buySignal && trendAlign == 1 && IsPullbackBuy())
         {
            is_buy = true;
            is_sell = false;
         }
         else if (sellSignal && trendAlign == -1 && IsPullbackSell())
         {
            is_buy = false;
            is_sell = true;
         }
      }
      else if (UseTrendFilter)
      {
         if (buySignal && trendUp && IsPullbackBuy())
         {
            is_buy = true;
            is_sell = false;
         }
         else if (sellSignal && trendDown && IsPullbackSell())
         {
            is_buy = false;
            is_sell = true;
         }
      }
      else
      {
         if (buySignal && IsPullbackBuy())
         {
            is_buy = true;
            is_sell = false;
         }
         else if (sellSignal && IsPullbackSell())
         {
            is_buy = false;
            is_sell = true;
         }
      }
   }

   if (gi_340 && gi_328 < 1)
   {
      ExtSymbolInfo.RefreshRates();
      g_bid_252 = ExtSymbolInfo.Bid();
      g_ask_260 = ExtSymbolInfo.Ask();

      double dynamicSL = GetDynamicSL();

      if (!gi_348 && !gi_344 && ls_32 == "true")
      {
         gi_312 = gi_328;

         if (PositionsTotal() <= 0 && is_sell)
         {
            gd_316 = fGetLots(ORDER_TYPE_SELL);
            if (gd_316 > 0)
            {
               if (ExtTrade.Sell(gd_316, _Symbol, g_bid_252,
                                 StopShort(g_ask_260, (int)dynamicSL),
                                 TakeShort(g_bid_252, (int)g_pips_120),
                                 gs_296 + "-" + IntegerToString(gi_312)))
               {
                  gd_276 = FindLastSellPrice();
                  gi_348 = true;
                  gi_356 = true;
               }
               else
               {
                  Print(gd_316, " Error: ", GetLastError());
                  return;
               }
            }
         }
         else if (PositionsTotal() <= 0 && is_buy)
         {
            gd_316 = fGetLots(ORDER_TYPE_BUY);
            if (gd_316 > 0)
            {
               if (ExtTrade.Buy(gd_316, _Symbol, g_ask_260,
                                StopLong(g_bid_252, (int)dynamicSL),
                                TakeLong(g_ask_260, (int)g_pips_120),
                                gs_296 + "-" + IntegerToString(gi_312)))
               {
                  gd_268 = FindLastBuyPrice();
                  gi_344 = true;
                  gi_356 = true;
               }
               else
               {
                  Print(gd_316, " Error: ", GetLastError());
                  return;
               }
            }
         }
      }

      if (gi_352 > 0)
         gi_308 = (int)(TimeCurrent() + 60 * 60 * gd_184);
      gi_340 = false;
   }

   gi_328 = CountTrades();
   g_price_244 = 0;
   double ld_56 = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ||
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            g_price_244 += PositionGetDouble(POSITION_PRICE_OPEN) *
                           PositionGetDouble(POSITION_VOLUME);
            ld_56 += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   if (gi_328 > 0)
      g_price_244 = NormalizeDouble(g_price_244 / ld_56, _Digits);

   if (gi_356)
   {
      double dynSL = GetDynamicSL();
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               double sl = StopLong(g_price_244, (int)g_pips_128);
               double tp = TakeLong(g_price_244, (int)g_pips_120);
               ExtTrade.PositionModify(ticket, sl, tp);
            }
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               double sl = StopShort(g_price_244, (int)g_pips_128);
               double tp = TakeShort(g_price_244, (int)g_pips_120);
               ExtTrade.PositionModify(ticket, sl, tp);
            }
         }
      }
   }

   if (gi_356)
   {
      if (gi_292 == true)
      {
         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket))
            {
               if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                   PositionGetInteger(POSITION_MAGIC) == g_magic_208)
               {
                  ExtTrade.PositionClose(ticket);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Order Close Market                                                |
//+------------------------------------------------------------------+
int fOrderCloseMarket(bool ai_0 = true, bool ai_4 = true)
{
   int li_ret_8 = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == g_magic_208)
         {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && ai_0)
            {
               if (ExtTrade.PositionClose(ticket))
                  li_ret_8++;
            }
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && ai_4)
            {
               if (ExtTrade.PositionClose(ticket))
                  li_ret_8++;
            }
         }
      }
   }
   return (li_ret_8);
}

//+------------------------------------------------------------------+
//| Get Lots                                                          |
//+------------------------------------------------------------------+
double fGetLots(int a_cmd_0)
{
   double l_lots_4 = Lots;
   datetime l_datetime_12;

   switch (gi_76)
   {
   case 0:
      l_lots_4 = Lots;
      break;
   case 1:
      l_lots_4 = NormalizeDouble(Lots * MathPow(gd_88, gi_312), (int)gd_112);
      break;
   case 2:
      l_datetime_12 = 0;
      l_lots_4 = Lots;
      HistorySelect(0, TimeCurrent());
      for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket > 0)
         {
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
                HistoryDealGetInteger(ticket, DEAL_MAGIC) == g_magic_208)
            {
               if ((int)HistoryDealGetInteger(ticket, DEAL_TIME) > l_datetime_12)
               {
                  l_datetime_12 = (int)HistoryDealGetInteger(ticket, DEAL_TIME);
                  if (HistoryDealGetDouble(ticket, DEAL_PROFIT) < 0)
                     l_lots_4 = NormalizeDouble(HistoryDealGetDouble(ticket, DEAL_VOLUME) * gd_88, (int)gd_112);
                  else
                     l_lots_4 = Lots;
               }
            }
         }
      }
      break;
   }

   ExtSymbolInfo.Refresh();
   double minlot = ExtSymbolInfo.LotsMin();
   double maxlot = ExtSymbolInfo.LotsMax();
   if (l_lots_4 < minlot)
      l_lots_4 = minlot;
   if (l_lots_4 > maxlot)
      l_lots_4 = maxlot;

   double margin_required = 0;
   if (!OrderCalcMargin((ENUM_ORDER_TYPE)a_cmd_0, _Symbol, l_lots_4, ExtSymbolInfo.Ask(), margin_required))
      return (-1);
   if (AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_required)
      return (-1);
   if (GetLastError() == 134)
      return (-2);

   return (l_lots_4);
}

//+------------------------------------------------------------------+
//| Count Trades                                                      |
//+------------------------------------------------------------------+
int CountTrades()
{
   int l_count_0 = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL ||
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            l_count_0++;
      }
   }
   return (l_count_0);
}

//+------------------------------------------------------------------+
//| Close This Symbol All                                             |
//+------------------------------------------------------------------+
void CloseThisSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == g_magic_208)
         {
            ExtTrade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Stop/Take Functions                                               |
//+------------------------------------------------------------------+
double StopLong(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 - ai_8 * _Point);
}

double StopShort(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 + ai_8 * _Point);
}

double TakeLong(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 + ai_8 * _Point);
}

double TakeShort(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 - ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Calculate Profit                                                  |
//+------------------------------------------------------------------+
double CalculateProfit()
{
   double ld_ret_0 = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ||
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            ld_ret_0 += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return (ld_ret_0);
}

//+------------------------------------------------------------------+
//| Trailing Alls                                                     |
//+------------------------------------------------------------------+
void TrailingAlls(int ai_0, int ai_4, double a_price_8)
{
   double l_ord_stoploss_20;
   if (ai_4 != 0)
   {
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;

            ExtSymbolInfo.RefreshRates();

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               l_ord_stoploss_20 = PositionGetDouble(POSITION_SL);
               if (ExtSymbolInfo.Bid() - PositionGetDouble(POSITION_PRICE_OPEN) > _Point * ai_0)
               {
                  if (l_ord_stoploss_20 < ExtSymbolInfo.Bid() - _Point * ai_0)
                  {
                     double newSL = ExtSymbolInfo.Bid() - ai_0 * _Point;
                     double tp = PositionGetDouble(POSITION_TP);
                     ExtTrade.PositionModify(ticket, newSL, tp);
                  }
               }
            }
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               l_ord_stoploss_20 = PositionGetDouble(POSITION_SL);
               if (PositionGetDouble(POSITION_PRICE_OPEN) - ExtSymbolInfo.Ask() > _Point * ai_0)
               {
                  if (l_ord_stoploss_20 > ExtSymbolInfo.Ask() + _Point * ai_0 ||
                      l_ord_stoploss_20 == 0)
                  {
                     double newSL = ExtSymbolInfo.Ask() + ai_0 * _Point;
                     double tp = PositionGetDouble(POSITION_TP);
                     ExtTrade.PositionModify(ticket, newSL, tp);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Account Equity High                                               |
//+------------------------------------------------------------------+
double AccountEquityHigh()
{
   if (CountTrades() == 0)
      gd_368 = AccountInfoDouble(ACCOUNT_EQUITY);
   if (gd_368 < gd_376)
      gd_368 = gd_376;
   else
      gd_368 = AccountInfoDouble(ACCOUNT_EQUITY);
   gd_376 = AccountInfoDouble(ACCOUNT_EQUITY);
   return (gd_368);
}

//+------------------------------------------------------------------+
//| Find Last Buy Price                                               |
//+------------------------------------------------------------------+
double FindLastBuyPrice()
{
   double l_ord_open_price_0 = 0;
   ulong l_ticket_8 = 0;
   ulong l_ticket_20 = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == g_magic_208 &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            l_ticket_8 = ticket;
            if (l_ticket_8 > l_ticket_20)
            {
               l_ord_open_price_0 = PositionGetDouble(POSITION_PRICE_OPEN);
               l_ticket_20 = l_ticket_8;
            }
         }
      }
   }
   return (l_ord_open_price_0);
}

//+------------------------------------------------------------------+
//| Find Last Sell Price                                              |
//+------------------------------------------------------------------+
double FindLastSellPrice()
{
   double l_ord_open_price_0 = 0;
   ulong l_ticket_8 = 0;
   ulong l_ticket_20 = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == g_magic_208 &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            l_ticket_8 = ticket;
            if (l_ticket_8 > l_ticket_20)
            {
               l_ord_open_price_0 = PositionGetDouble(POSITION_PRICE_OPEN);
               l_ticket_20 = l_ticket_8;
            }
         }
      }
   }
   return (l_ord_open_price_0);
}

//+------------------------------------------------------------------+
//| Get Last Lot Size                                                 |
//+------------------------------------------------------------------+
double GetLastLotSize()
{
   double lastLotSize = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         lastLotSize = PositionGetDouble(POSITION_VOLUME);
         break;
      }
   }
   return lastLotSize;
}

//+------------------------------------------------------------------+
//| Download and Parse CSV from Google Sheets                         |
//+------------------------------------------------------------------+
bool DownloadCSVFile()
{
   Print("Downloading CSV from: ", GoogleSheetURL);
   string cookie = NULL;
   string referer = NULL;
   int timeout = 5000;
   char post[];
   char result[];
   string result_headers;
   ResetLastError();

   int res = WebRequest("GET", GoogleSheetURL, cookie, referer, timeout, post, 0, result, result_headers);

   if (res == -1)
   {
      int error = GetLastError();
      Print("ERROR: WebRequest failed. Error code: ", error);
      if (error == 4060)
      {
         Print("ERROR: URL not allowed. Add to Tools -> Options -> Expert Advisors -> Allow WebRequest");
         Alert("Please add https://docs.google.com to allowed URLs in MT5 settings!");
      }
      return false;
   }

   if (res == 200)
   {
      string content = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      bool success = ParseCSVFromMemory(content);
      content = "";
      ArrayResize(result, 0);
      if (success)
      {
         Print("CSV data parsed successfully. Total records: ", totalRecords);
         return true;
      }
      else
      {
         Print("ERROR: Failed to parse CSV data");
         return false;
      }
   }
   else
   {
      Print("ERROR: HTTP Error Code: ", res);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Parse CSV from Memory                                             |
//+------------------------------------------------------------------+
bool ParseCSVFromMemory(string csvContent)
{
   totalRecords = 0;
   ArrayResize(csvRecords, 0);
   string lines[];
   int lineCount = StringSplit(csvContent, '\n', lines);
   if (lineCount < 2)
   {
      Print("ERROR: CSV content is empty or invalid");
      return false;
   }
   Print("CSV Header: ", lines[0]);
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
   ArrayResize(lines, 0);
   return totalRecords > 0;
}

//+------------------------------------------------------------------+
//| Validate Username, Password and Expiry Date                       |
//+------------------------------------------------------------------+
bool ValidateCSVUser(string inputUsername, string inputPassword)
{
   if (StringLen(inputUsername) == 0 || StringLen(inputPassword) == 0)
   {
      Print("ERROR: Username or Password is empty");
      return false;
   }
   string inputPasswordHash = MD5Hash(inputPassword);
   Print("Using MD5 hash: ", StringSubstr(inputPasswordHash, 0, 8), "...");
   for (int i = 0; i < totalRecords; i++)
   {
      if (csvRecords[i].username == inputUsername &&
          csvRecords[i].passwordHash == inputPasswordHash)
      {
         Print("User found: ", inputUsername);
         datetime currentTime = TimeCurrent();
         datetime expireDate = csvRecords[i].expDate;
         Print("Current Time: ", TimeToString(currentTime, TIME_DATE | TIME_MINUTES));
         Print("Expire Date: ", TimeToString(expireDate, TIME_DATE | TIME_MINUTES));
         if (currentTime > expireDate)
         {
            Print("ERROR: Account expired");
            Alert("Account Expired! Please renew subscription.");
            isCSVAuthenticated = false;
            return false;
         }
         else
         {
            csvDaysRemaining = (int)((expireDate - currentTime) / 86400);
            Print("SUCCESS: Account valid. Days remaining: ", csvDaysRemaining);
            isCSVAuthenticated = true;
            return true;
         }
      }
   }
   Print("ERROR: Username or Password is incorrect");
   Alert("Login Failed: Invalid Username or Password");
   return false;
}

//+------------------------------------------------------------------+
//| Display Info                                                      |
//+------------------------------------------------------------------+
void Display_Info(string mess = "Inside trading hours")
{
   string BrokerTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string LocalComputerTime = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
   DetectTimezone();
   datetime adjustedTime = GetAdjustedTime();
   string AdjustedTimeStr = TimeToString(adjustedTime, TIME_DATE | TIME_SECONDS);
   int tzHours = g_timezone_offset / 3600;
   int tzMinutes = (MathAbs(g_timezone_offset) % 3600) / 60;
   string TimezoneStr = IntegerToString(tzHours) + "h " + IntegerToString(MathAbs(tzMinutes)) + "m";

   string csvStatus = "";
   if (StringLen(CSV_Password) > 0)
   {
      if (isCSVAuthenticated)
         csvStatus = "CSV Auth: Account " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                     " (" + IntegerToString(csvDaysRemaining) + " days left)";
      else
         csvStatus = "CSV Auth: FAILED";
   }

   // === V5.04: Show new features status ===
   string circuitStatus = UseCircuitBreaker ? "ON (" + DoubleToString(CircuitBreakerPct, 1) + "%)" : "OFF";
   string trendStatus = UseTrendFilter ? "ON (EMA50/200)" : "OFF";
   string slStatus = UseDynamicSL ? "ON (ATR x" + DoubleToString(ATR_Multiplier, 1) + ")" : "OFF";
   string distStatus = UseAdaptiveDist ? "ON" : "OFF";
   string closeStatus = UseCloseOnTrend ? "ON (EMA50)" : "OFF";
   string partialStatus = UsePartialClose ? "ON (Profit>" + DoubleToString(PartialCloseProfit, 0) + "pts)" : "OFF";
   string smartStatus = UseSmartExit ? "ON" : "OFF";
   string alignStatus = UseTrendAlignment ? "ON (H4/H1+ADX)" : "OFF";
   string timingStatus = UseEntryTiming ? "ON (EMA21 Pullback)" : "OFF";

   Comment(
       "=== Devilmod-Robot-2026 V5.0.5 ===\n",
       "Forex Account Server: ", AccountInfoString(ACCOUNT_SERVER), "\n",
       csvStatus != "" ? csvStatus + "\n" : "",
       "Lots: ", NormalizeDouble(GetLastLotSize(), 2), " OrderTotal=", CountTrades(), "\n",
       "Symbol: ", _Symbol, "  Balance: ",
       NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE), 2),
       "  MARGIN: ", NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN), 2),
       "  FREE: ", NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2), "\n",
       "SellPrice: ", FindLastSellPrice(), " BuyPrice: ", FindLastBuyPrice(), "\n",
       "BrokerTime: ", BrokerTime, "  Local: ", LocalComputerTime, "\n",
       "AdjustedTime: ", AdjustedTimeStr, "  UTC+", TimezoneStr, "\n",
       "--- Risk Management (V5.05) ---\n",
       "Circuit Breaker: ", circuitStatus, "\n",
       "Trend Filter: ", trendStatus, "\n",
       "Dynamic SL: ", slStatus, "\n",
       "Adaptive Distance: ", distStatus, "\n",
       "Close on Trend: ", closeStatus, "\n",
       "Partial Close: ", partialStatus, "\n",
       "Smart Exit: ", smartStatus, "\n",
       "Trend Alignment: ", alignStatus, "\n",
       "Entry Timing: ", timingStatus, "\n",
       mess, "\n",
       "Trading Hours: ", StartHour, ":00 - ", EndHour, ":00 (Adjusted)\n");
}
