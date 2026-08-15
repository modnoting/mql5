//+------------------------------------------------------------------+
//|                               Devilmod-Robot-2026-V-5.0.6.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "5.06"
#property strict
#property description "Devilmod-Robot-2026 V5.0.6 - XAUUSD Martingale EA"
#property description ""
#property description "=== SYSTEMS USED ==="
#property description "1. Martingale System       - Lot multiplier 1.2x, Max 23 orders"
#property description "2. Dynamic SL (ATR)        - SL ตาม ATR x1.5"
#property description "3. Trailing Stop           - Trail ALL orders"
#property description "4. Adaptive Distance       - ลด distance เมื่อ lot สูง"
#property description "5. Circuit Breaker         - หยุดเมื่อ loss > 5% equity"
#property description "6. Trend Filter (EMA)      - เช็ค EMA50/200 ก่อนเปิด order"
#property description "7. Trading Hours Filter    - จำกัดเวลา trade"
#property description "8. CSV Authentication     - ตรวจสอบสิทธิ์ผ่าน Google Sheets"
#property description "9. Opposite Martingale     - เปิด Martingale ตรงข้ามเมื่อ loss >= 3000 pts"
#property description ""
#property description "=== ENTRY CONDITIONS ==="
#property description "Layer 1: Stoch M5 > 30 rising + MACD M1 rising + RSI H1 rising"
#property description "Layer 2: Trend Filter (EMA50/200)"
#property description ""
#property description "=== EXIT CONDITIONS ==="
#property description "1. Dynamic SL: SL ตาม ATR"
#property description "2. Trailing Stop: Lock profit เมื่อ price ลาก"
#property description "3. Circuit Breaker: Loss > 5% -> หยุด trading"
#property description "4. Opposite Martingale: Recovery เมื่อ loss ลึก"

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
input int MaxTrades = 15;
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

// === V5.04: Risk Management Inputs ===
input bool UseCircuitBreaker = true;
input double CircuitBreakerPct = 5.0;
input bool UseTrendFilter = false;
input bool UseDynamicSL = true;
input int ATR_Period = 14;
input double ATR_Multiplier = 1.5;
input bool UseAdaptiveDist = true;

// === V5.06 NEW: Opposite Martingale ===
input bool   UseOppositeMartingale = true;
input double OppositeTriggerPts   = 2000.0;
input double OppositeMaxLots      = 2.0;
input int    OppositeMaxLayers    = 5;

// Global Variables
double g_price_244;
double g_bid_252;
double g_ask_260;
double gd_268;
double gd_276;
double gd_284;
bool gi_292;
string gs_296 = "Devilmod-Robot-2026 V5.0.6";
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

// V5.06: Opposite Martingale tracking
datetime g_lastOppositeTime = 0;

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

// Indicator Handles
int HandleMACD_M1;
int HandleSto_M5;
int HandleRSI_H1;
int HandleEMA50_H1;
int HandleEMA200_H1;
int HandleATR_H1;

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
//| Adaptive Distance Function                                        |
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
//| Get Dynamic SL from ATR                                           |
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
//| V5.06: Count Opposite Trades (RECOVERY orders)                   |
//+------------------------------------------------------------------+
int CountOppositeTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         string comment = PositionGetString(POSITION_COMMENT);
         if (StringFind(comment, "RECOVERY") >= 0)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| V5.06: Get Total Loss in Points for a Direction                  |
//+------------------------------------------------------------------+
double GetDirectionLossPoints(int direction)
{
   double totalProfit = 0;
   double totalLot = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         string comment = PositionGetString(POSITION_COMMENT);
         if (StringFind(comment, "RECOVERY") >= 0)
            continue;
         int posType = (int)PositionGetInteger(POSITION_TYPE);
         if (direction == 1 && posType == POSITION_TYPE_BUY)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            totalLot += PositionGetDouble(POSITION_VOLUME);
         }
         if (direction == -1 && posType == POSITION_TYPE_SELL)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            totalLot += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
    if (totalLot <= 0) return 0;
    return totalProfit / totalLot;
}

//+------------------------------------------------------------------+
//| V5.06: Check Opposite Martingale                                  |
//+------------------------------------------------------------------+
void CheckOppositeMartingale()
{
   if (!UseOppositeMartingale) return;
   if (CountTrades() < 3) return;

   ExtSymbolInfo.RefreshRates();
   double currentBid = ExtSymbolInfo.Bid();
   double currentAsk = ExtSymbolInfo.Ask();

   int existingOpposite = CountOppositeTrades();
   if (existingOpposite >= OppositeMaxLayers) return;

   double buyLoss = GetDirectionLossPoints(1);
   double sellLoss = GetDirectionLossPoints(-1);

   bool hasBuy = false, hasSell = false;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) hasBuy = true;
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) hasSell = true;
      }
   }

   double dynamicSL = GetDynamicSL();
   double oppositeLot = NormalizeDouble(Lots * MathPow(gd_88, existingOpposite), (int)gd_112);
   double minLot = ExtSymbolInfo.LotsMin();
   double maxLot = ExtSymbolInfo.LotsMax();
   if (oppositeLot < minLot) oppositeLot = minLot;
   if (oppositeLot > maxLot) oppositeLot = maxLot;
   if (oppositeLot > OppositeMaxLots) oppositeLot = OppositeMaxLots;

   int cooldownSeconds = 600;
   if (TimeCurrent() - g_lastOppositeTime < cooldownSeconds) return;

   if (hasBuy && buyLoss < -OppositeTriggerPts && !hasSell)
   {
      int existingBuys = 0;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;
            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "RECOVERY") >= 0) continue;
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               existingBuys++;
         }
      }
      if (existingBuys <= 0) return;

      double lastBuyPrice = FindLastBuyPrice();
      if (lastBuyPrice > 0)
      {
         int currentDist = GetAdaptiveDistance(existingBuys + existingOpposite);
         double pointDiff = (lastBuyPrice - currentAsk) / _Point;
         if (pointDiff < currentDist) return;
      }

      Print("OPPOSITE MARTINGALE: Opening SELL RECOVERY. BuyLoss=", DoubleToString(buyLoss, 1),
            " pts, Lot=", oppositeLot, " Layer=", existingOpposite + 1);
      if (ExtTrade.Sell(oppositeLot, _Symbol, currentBid,
                        0,
                        0,
                        gs_296 + "-RECOVERY"))
      {
         g_lastOppositeTime = TimeCurrent();
      }
   }
   else if (hasSell && sellLoss < -OppositeTriggerPts && !hasBuy)
   {
      int existingSells = 0;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;
            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "RECOVERY") >= 0) continue;
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               existingSells++;
         }
      }
      if (existingSells <= 0) return;

      double lastSellPrice = FindLastSellPrice();
      if (lastSellPrice > 0)
      {
         int currentDist = GetAdaptiveDistance(existingSells + existingOpposite);
         double pointDiff = (currentBid - lastSellPrice) / _Point;
         if (pointDiff < currentDist) return;
      }

      Print("OPPOSITE MARTINGALE: Opening BUY RECOVERY. SellLoss=", DoubleToString(sellLoss, 1),
            " pts, Lot=", oppositeLot, " Layer=", existingOpposite + 1);
      if (ExtTrade.Buy(oppositeLot, _Symbol, currentAsk,
                        0,
                        0,
                        gs_296 + "-RECOVERY"))
      {
         g_lastOppositeTime = TimeCurrent();
      }
   }
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

   HandleMACD_M1 = iMACD(_Symbol, PERIOD_M1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleSto_M5 = iStochastic(_Symbol, PERIOD_M5, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleRSI_H1 = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   HandleEMA50_H1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   HandleEMA200_H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   HandleATR_H1 = iATR(_Symbol, PERIOD_H1, ATR_Period);

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
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Failed! EA is disabled.");
      return;
   }

   double macdM1 = GetMACD(HandleMACD_M1, 0);
   double macdM1_prev = GetMACD(HandleMACD_M1, 1);
   double stoM5 = GetStochastic(HandleSto_M5, 0);
   double stoM5_prev = GetStochastic(HandleSto_M5, 1);
   double rsiH1 = GetRSI(HandleRSI_H1, 0);
   double rsiH1_prev = GetRSI(HandleRSI_H1, 1);
   double ema50 = GetEMA(HandleEMA50_H1, 0);
   double ema200 = GetEMA(HandleEMA200_H1, 0);

   ExtSymbolInfo.RefreshRates();
   double currentPrice = ExtSymbolInfo.Bid();

   bool is_buy = false, is_sell = false;
   double l_ord_lots_0 = 0.0;
   double l_ord_lots_8 = 0.0;

   DetectTimezone();
   int dayOfWeek = GetAdjustedDayOfWeek();
   int hourOfDay = GetAdjustedHour();

   if (dayOfWeek == 0 || dayOfWeek == 6)
   {
      Display_Info("Do not work on Holidays!");
      return;
   }

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

   CheckOppositeMartingale();

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

   if (gi_328 > 0 && gi_328 <= MaxTrades)
   {
      ExtSymbolInfo.RefreshRates();
      gd_268 = FindLastBuyPrice();
      gd_276 = FindLastSellPrice();

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

                  if (pointDiffSell < currentDist)
                  {
                     Comment("Waiting for SELL distance... PointDiff=", (int)pointDiffSell,
                             " < Required=", currentDist);
                     return;
                  }
               }

               ExtSymbolInfo.RefreshRates();

               if (ExtTrade.Sell(gd_316, _Symbol, ExtSymbolInfo.Bid(),
                                 StopShort(ExtSymbolInfo.Ask(), (int)dynamicSL),
                                 TakeShort(ExtSymbolInfo.Bid(), (int)g_pips_120),
                                 gs_296 + "-" + IntegerToString(gi_312)))
               {
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

                     if (pointDiffBuy < currentDist)
                     {
                        Comment("Waiting for BUY distance... PointDiff=", (int)pointDiffBuy,
                                " < Required=", currentDist);
                        return;
                     }
                  }

                  ExtSymbolInfo.RefreshRates();

                  if (ExtTrade.Buy(gd_316, _Symbol, ExtSymbolInfo.Ask(),
                                   StopLong(ExtSymbolInfo.Bid(), (int)dynamicSL),
                                   TakeLong(ExtSymbolInfo.Ask(), (int)g_pips_120),
                                   gs_296 + "-" + IntegerToString(gi_312)))
                  {
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

   bool trendUp = (ema50 > ema200) && (currentPrice > ema50);
   bool trendDown = (ema50 < ema200) && (currentPrice < ema50);

   if (gi_328 == 0)
   {
      bool buySignal = stoM5 > 30 && stoM5 > stoM5_prev &&
                       macdM1 > macdM1_prev &&
                       rsiH1 > rsiH1_prev;

      bool sellSignal = stoM5 < 70 && stoM5 < stoM5_prev &&
                        macdM1 < macdM1_prev &&
                        rsiH1 < rsiH1_prev;

      if (UseTrendFilter)
      {
         if (buySignal && trendUp)
         {
            is_buy = true;
            is_sell = false;
         }
         else if (sellSignal && trendDown)
         {
            is_buy = false;
            is_sell = true;
         }
      }
      else
      {
         if (buySignal)
         {
            is_buy = true;
            is_sell = false;
         }
         else if (sellSignal)
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

         if (gi_328 <= 0 && is_sell)
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
         else if (gi_328 <= 0 && is_buy)
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

          string comment = PositionGetString(POSITION_COMMENT);
          if (StringFind(comment, "RECOVERY") >= 0)
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
      ExtSymbolInfo.RefreshRates();
      double bid = ExtSymbolInfo.Bid();
      double ask = ExtSymbolInfo.Ask();

      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket))
         {
            if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;

            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "RECOVERY") >= 0)
               continue;

            double currentSL = PositionGetDouble(POSITION_SL);

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               double newSL = StopLong(g_price_244, (int)g_pips_128);
               double newTP = TakeLong(g_price_244, (int)g_pips_120);
               bool slValid = (newSL == 0 || newSL < bid);
               bool tpValid = (newTP == 0 || newTP > bid);
               if (slValid && tpValid)
                  ExtTrade.PositionModify(ticket, newSL, newTP);
            }
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               double newSL = StopShort(g_price_244, (int)g_pips_128);
               double newTP = TakeShort(g_price_244, (int)g_pips_120);
               bool slValid = (newSL == 0 || newSL > ask);
               bool tpValid = (newTP == 0 || newTP < ask);
               if (slValid && tpValid)
                  ExtTrade.PositionModify(ticket, newSL, newTP);
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
            if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                PositionGetInteger(POSITION_MAGIC) != g_magic_208)
               continue;

            string comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(comment, "RECOVERY") >= 0)
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

   string circuitStatus = UseCircuitBreaker ? "ON (" + DoubleToString(CircuitBreakerPct, 1) + "%)" : "OFF";
   string trendStatus = UseTrendFilter ? "ON (EMA50/200)" : "OFF";
   string slStatus = UseDynamicSL ? "ON (ATR x" + DoubleToString(ATR_Multiplier, 1) + ")" : "OFF";
   string distStatus = UseAdaptiveDist ? "ON" : "OFF";
   string oppositeStatus = UseOppositeMartingale ? "ON (Trigger>" + DoubleToString(OppositeTriggerPts, 0) + "pts)" : "OFF";

   int oppCount = CountOppositeTrades();
   string oppInfo = oppCount > 0 ? "Recovery Orders: " + IntegerToString(oppCount) : "";

   Comment(
       "=== Devilmod-Robot-2026 V5.0.6 ===\n",
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
       "--- Systems ---\n",
       "Circuit Breaker: ", circuitStatus, "\n",
       "Trend Filter: ", trendStatus, "\n",
       "Dynamic SL: ", slStatus, "\n",
       "Adaptive Distance: ", distStatus, "\n",
       "Opposite Martingale: ", oppositeStatus, "\n",
       oppInfo, "\n",
       mess, "\n",
       "Trading Hours: ", StartHour, ":00 - ", EndHour, ":00 (Adjusted)\n");
}
//+------------------------------------------------------------------+
