//+------------------------------------------------------------------+
//|                               Devilmod-Robot-2026-V-5.0.3.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "5.03"
#property strict

// Include MT5 Trade Libraries
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

// CSV Authentication Parameters
input string CSV_Password = ""; // Password for authentication
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

// Trading Parameters
int gi_76 = 1;
bool gi_80 = false;
bool gi_84 = true;
double gd_88 = 1.2;
double g_slippage_96 = 5.0;
input double Lots = 0.01;
double gd_112 = 2.0;
input double g_pips_120 = 3100.0; // TP With Point
double g_pips_128 = 0.0;
input double gd_136 = 2500.0;   // Trailing
input double gd_144 = 1000.0;   // SL
input double distance = 1200.0; // Distance From Before Price
double g_pips_152 = 7.0;        // Distance From Before Price
input int MaxTrades = 23;
bool gi_164 = false;
double gd_168 = 20.0;
bool gi_176 = true;
bool gi_180 = false;
double gd_184 = 0.0;
bool gi_192 = false;
input bool UseManualTrade = false;
input bool UseHourTrade = true;
input int StartHour = 1;       // Trading Start Hour (Server )
input int EndHour = 15;        // Trading End Hour (Server )
input int StartHourMonday = 7; // Trading Monday Start Hour (Server )
input int EndHourMonday = 10;  // Trading Monday End Hour (Server )
input int StartHourFriday = 1; // Trading Friday Start Hour (Server )
input int EndHourFriday = 3;   // Trading FridayEnd Hour (Server )
input int g_magic_208 = 0;

// Global Variables
double g_price_212;
double gd_220;
double gd_unused_228;
double gd_unused_236;
double g_price_244;
double g_bid_252;
double g_ask_260;
double gd_268;
double gd_276;
double gd_284;
bool gi_292;
string gs_296 = "Devilmod-Robot-2026 V5.0.3";
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

input int X_trend = 270; // x position button
input int Y_trend = 35;  // y position button

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
int HandleMACD_H1, HandleMACD_M30, HandleMACD_M15, HandleMACD_M5, HandleMACD_M1;
int HandleSto_H1, HandleSto_M30, HandleSto_M15, HandleSto_M5, HandleSto_M1;
int HandleRSI_H1, HandleRSI_M30, HandleRSI_M15, HandleRSI_M5, HandleRSI_M1;

// Timezone Detection
int g_timezone_offset = 0; // Timezone offset in seconds (Server to Local)
bool g_timezone_detected = false;

//+------------------------------------------------------------------+
//| Detect Timezone from Server vs Local Time                        |
//+------------------------------------------------------------------+
void DetectTimezone()
{
   if (g_timezone_detected)
      return;

   datetime serverTime = TimeCurrent();
   datetime localTime = TimeLocal();

   // Calculate offset: positive means local is ahead of server
   g_timezone_offset = (int)(localTime - serverTime);

   g_timezone_detected = true;

   Print("=== Timezone Detected ===");
   Print("Server Time: ", TimeToString(serverTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   Print("Local Time:  ", TimeToString(localTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   Print("Timezone Offset: ", g_timezone_offset / 3600, " hours ",
         (MathAbs(g_timezone_offset) % 3600) / 60, " minutes");
}

//+------------------------------------------------------------------+
//| Get Adjusted Time (Server + Timezone)                             |
//+------------------------------------------------------------------+
datetime GetAdjustedTime()
{
   DetectTimezone();
   return TimeCurrent() + g_timezone_offset;
}

//+------------------------------------------------------------------+
//| Get Hour from Adjusted Time                                       |
//+------------------------------------------------------------------+
int GetAdjustedHour()
{
   datetime adjusted = GetAdjustedTime();
   MqlDateTime dt;
   TimeToStruct(adjusted, dt);
   return dt.hour;
}

//+------------------------------------------------------------------+
//| Get Day of Week from Adjusted Time                                |
//+------------------------------------------------------------------+
int GetAdjustedDayOfWeek()
{
   datetime adjusted = GetAdjustedTime();
   MqlDateTime dt;
   TimeToStruct(adjusted, dt);
   return dt.day_of_week;
}

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
      {
         result += StringFormat("%02x", hash[i]);
      }
      return result;
   }

   return SimpleHash(inputStr);
}

//+------------------------------------------------------------------+
//| Simple Hash Function (Fallback)                                  |
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
//| Get MACD value                                                   |
//+------------------------------------------------------------------+
double GetMACD(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get Stochastic value                                             |
//+------------------------------------------------------------------+
double GetStochastic(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0) // MODE_SIGNAL = index 1
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get Close price                                                  |
//+------------------------------------------------------------------+
double GetClose(ENUM_TIMEFRAMES timeframe, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyClose(_Symbol, timeframe, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   ExtSymbolInfo.Name(_Symbol);
   ExtSymbolInfo.Refresh();

   gd_284 = ExtSymbolInfo.Spread() * ExtSymbolInfo.Point();

   // Set trade parameters
   ExtTrade.SetExpertMagicNumber(g_magic_208);
   ExtTrade.SetDeviationInPoints((int)g_slippage_96);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ExtTrade.SetAsyncMode(false);

   // CSV Authentication Check - Use Account Number as Username
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
         Alert("Failed to download CSV data. Check internet connection and URL settings.");
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

   // Initialize Indicator Handles
   HandleMACD_H1 = iMACD(_Symbol, PERIOD_H1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M30 = iMACD(_Symbol, PERIOD_M30, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M15 = iMACD(_Symbol, PERIOD_M15, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M5 = iMACD(_Symbol, PERIOD_M5, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M1 = iMACD(_Symbol, PERIOD_M1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);

   HandleSto_H1 = iStochastic(_Symbol, PERIOD_H1, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M30 = iStochastic(_Symbol, PERIOD_M30, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M15 = iStochastic(_Symbol, PERIOD_M15, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M5 = iStochastic(_Symbol, PERIOD_M5, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M1 = iStochastic(_Symbol, PERIOD_M1, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);

   HandleRSI_H1 = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   HandleRSI_M30 = iRSI(_Symbol, PERIOD_M30, 14, PRICE_CLOSE);
   HandleRSI_M15 = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
   HandleRSI_M5 = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   HandleRSI_M1 = iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);

   // Validate indicator handles
   if (HandleMACD_H1 == INVALID_HANDLE || HandleMACD_M30 == INVALID_HANDLE ||
       HandleMACD_M15 == INVALID_HANDLE || HandleMACD_M5 == INVALID_HANDLE ||
       HandleMACD_M1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MACD indicator handles");
      return (INIT_FAILED);
   }

   if (HandleSto_H1 == INVALID_HANDLE || HandleSto_M30 == INVALID_HANDLE ||
       HandleSto_M15 == INVALID_HANDLE || HandleSto_M5 == INVALID_HANDLE ||
       HandleSto_M1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Stochastic indicator handles");
      return (INIT_FAILED);
   }

   if (HandleRSI_H1 == INVALID_HANDLE || HandleRSI_M30 == INVALID_HANDLE ||
       HandleRSI_M15 == INVALID_HANDLE || HandleRSI_M5 == INVALID_HANDLE ||
       HandleRSI_M1 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create RSI indicator handles");
      return (INIT_FAILED);
   }

   Display_Info();

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if (HandleMACD_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_H1);
   if (HandleMACD_M30 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_M30);
   if (HandleMACD_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_M15);
   if (HandleMACD_M5 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_M5);
   if (HandleMACD_M1 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_M1);

   if (HandleSto_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_H1);
   if (HandleSto_M30 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_M30);
   if (HandleSto_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_M15);
   if (HandleSto_M5 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_M5);
   if (HandleSto_M1 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_M1);

   if (HandleRSI_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_H1);
   if (HandleRSI_M30 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_M30);
   if (HandleRSI_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_M15);
   if (HandleRSI_M5 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_M5);
   if (HandleRSI_M1 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_M1);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check CSV Authentication Status
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Failed! EA is disabled.");
      return;
   }

   // Display_Info();

   // Get MACD values for all required timeframes
   double macdH1 = GetMACD(HandleMACD_H1, 0);
   double macdH1_prev = GetMACD(HandleMACD_H1, 1);
   double macdH1_prev1 = GetMACD(HandleMACD_H1, 2);

   double macdM30 = GetMACD(HandleMACD_M30, 0);
   double macdM30_prev = GetMACD(HandleMACD_M30, 1);
   double macdM30_prev1 = GetMACD(HandleMACD_M30, 2);

   double macdM15 = GetMACD(HandleMACD_M15, 0);
   double macdM15_prev = GetMACD(HandleMACD_M15, 1);
   double macdM15_prev1 = GetMACD(HandleMACD_M15, 2);

   double macdM5 = GetMACD(HandleMACD_M5, 0);
   double macdM5_prev = GetMACD(HandleMACD_M5, 1);
   double macdM5_prev1 = GetMACD(HandleMACD_M5, 2);

   double macdM1 = GetMACD(HandleMACD_M1, 0);
   double macdM1_prev = GetMACD(HandleMACD_M1, 1);
   double macdM1_prev1 = GetMACD(HandleMACD_M1, 2);

   // Get Stochastic values for all required timeframes
   double stoH1 = GetStochastic(HandleSto_H1, 0);
   double stoH1_prev = GetStochastic(HandleSto_H1, 1);
   double rsiH1 = GetRSI(HandleRSI_H1, 0);
   double rsiH1_prev = GetRSI(HandleRSI_H1, 1);

   double stoM30 = GetStochastic(HandleSto_M30, 0);
   double stoM30_prev = GetStochastic(HandleSto_M30, 1);
   double rsiM30 = GetRSI(HandleRSI_M30, 0);
   double rsiM30_prev = GetRSI(HandleRSI_M30, 1);

   double stoM15 = GetStochastic(HandleSto_M15, 0);
   double stoM15_prev = GetStochastic(HandleSto_M15, 1);
   double rsiM15 = GetRSI(HandleRSI_M15, 0);
   double rsiM15_prev = GetRSI(HandleRSI_M15, 1);

   double stoM5 = GetStochastic(HandleSto_M5, 0);
   double stoM5_prev = GetStochastic(HandleSto_M5, 1);
   double rsiM5 = GetRSI(HandleRSI_M5, 0);
   double rsiM5_prev = GetRSI(HandleRSI_M5, 1);

   double stoM1 = GetStochastic(HandleSto_M1, 0);
   double stoM1_prev = GetStochastic(HandleSto_M1, 1);

   bool is_buy = false, is_sell = false;
   double l_ord_lots_0 = 0.0;
   double l_ord_lots_8 = 0.0;

   double h1_2 = GetClose(PERIOD_H1, 2);
   double h1_1 = GetClose(PERIOD_H1, 1);
   double h1_0 = GetClose(PERIOD_H1, 0);
   double m30_2 = GetClose(PERIOD_M30, 2);
   double m30_1 = GetClose(PERIOD_M30, 1);
   double m30_0 = GetClose(PERIOD_M30, 0);
   double m15_2 = GetClose(PERIOD_M15, 2);
   double m15_1 = GetClose(PERIOD_M15, 1);
   double m15_0 = GetClose(PERIOD_M15, 0);

   // Get adjusted time (Server Time + Timezone Offset)
   DetectTimezone();
   int dayOfWeek = GetAdjustedDayOfWeek();
   int hourOfDay = GetAdjustedHour();

   // Get local computer time
   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int dayOfWeekLocal = dt.day_of_week;
   int hourOfDayLocal = dt.hour;

   // Debug: Show adjusted time info
   static datetime lastDebugTime = 0;
   datetime currentAdjusted = GetAdjustedTime();
   if (currentAdjusted - lastDebugTime >= 300) // Print every 5 minutes
   {
      MqlDateTime dtAdj;
      TimeToStruct(currentAdjusted, dtAdj);
      /*Print("Adjusted Time: ", TimeToString(currentAdjusted, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
            " | Day: ", dtAdj.day_of_week, " | Hour: ", dtAdj.hour, " | hourOfDayLocal: ", hourOfDay, " | dayOfWeek: ", dayOfWeek);
      lastDebugTime = currentAdjusted;*/
   }

   // Check day of week restrictions
   if (dayOfWeek == 0 || dayOfWeek == 6)
   {
      // Comment("Do not work on Holidays!");
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

   gi_328 = CountTrades();
   if (gi_328 == 0)
      gi_292 = false;

   // Check existing positions for updates and store lot sizes
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
               // ตรวจสอบว่ามี position เดิมหรือไม่
               if (LastSellPrice > 0)
               {
                  double pointDiffSell = MathAbs(currentPriceSell - LastSellPrice) / ExtSymbolInfo.Point();
                  Print("SELL Check - LastPrice: ", LastSellPrice,
                        " CurrentPrice: ", currentPriceSell,
                        " PointDiff: ", (int)pointDiffSell,
                        " Required Distance: ", (int)distance);

                  if (pointDiffSell < distance)
                  {
                     Comment("Waiting for SELL distance... PointDiff=", (int)pointDiffSell,
                             " < Required=", (int)distance);
                     return;
                  }
               }

               ExtSymbolInfo.RefreshRates();
               Print("Opening SELL order - Lot: ", gd_316, " Price: ", ExtSymbolInfo.Bid());

               if (ExtTrade.Sell(gd_316, _Symbol, ExtSymbolInfo.Bid(),
                                 StopShort(ExtSymbolInfo.Ask(), (int)gd_144),
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
                  // ตรวจสอบว่ามี position เดิมหรือไม่
                  if (LastBuyPrice > 0)
                  {
                     double pointDiffBuy = MathAbs(currentPriceBuy - LastBuyPrice) / ExtSymbolInfo.Point();
                     Print("BUY Check - LastPrice: ", LastBuyPrice,
                           " CurrentPrice: ", currentPriceBuy,
                           " PointDiff: ", (int)pointDiffBuy,
                           " Required Distance: ", (int)distance);

                     if (pointDiffBuy < distance)
                     {
                        Comment("Waiting for BUY distance... PointDiff=", (int)pointDiffBuy,
                                " < Required=", (int)distance);
                        return;
                     }
                  }

                  ExtSymbolInfo.RefreshRates();
                  Print("Opening BUY order - Lot: ", gd_316, " Price: ", ExtSymbolInfo.Ask());

                  if (ExtTrade.Buy(gd_316, _Symbol, ExtSymbolInfo.Ask(),
                                   StopLong(ExtSymbolInfo.Bid(), (int)gd_144),
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

   // Buy Condition (V5.03: FiboLevel + Stoch + MACD M1 + RSI H1)
   // เน้น FiboLevel เป็นหลัก + Stoch ยืนยันเด้งจริง
   if (PositionsTotal() == 0 &&
       stoM5 > 30 && stoM5 > stoM5_prev && // Stoch M5 ยืนยันเด้งจริง
       macdM1 > macdM1_prev &&             // MACD M1 momentum ขาขึ้น
       rsiH1 > rsiH1_prev                  // RSI H1 trend ขาขึ้น
                                           //&& GetAction == "UP" // FiboLevel Bounce Signal
   )
   {
      is_buy = true;
      is_sell = false;
   }

   // Sell Condition (V5.03: FiboLevel + Stoch + MACD M1 + RSI H1)
   // เน้น FiboLevel เป็นหลัก + Stoch ยืนยันเด้งจริง
   else if (PositionsTotal() == 0 &&
            stoM5 < 70 && stoM5 < stoM5_prev && // Stoch M5 ยืนยันเด้งจริง
            macdM1 < macdM1_prev &&             // MACD M1 momentum ขาลง
            rsiH1 < rsiH1_prev                  // RSI H1 trend ขาลง
            //&& GetAction == "DN"                   // FiboLevel Bounce Signal
   )
   {
      is_buy = false;
      is_sell = true;
   }

   if (gi_340 && gi_328 < 1)
   {
      ExtSymbolInfo.RefreshRates();
      g_bid_252 = ExtSymbolInfo.Bid();
      g_ask_260 = ExtSymbolInfo.Ask();

      if (!gi_348 && !gi_344 && ls_32 == "true")
      {
         gi_312 = gi_328;

         if (UseManualTrade)
         {
            // Manual trade mode - wait for manual signals
         }

         if (PositionsTotal() <= 0 && is_sell)
         {
            gd_316 = fGetLots(ORDER_TYPE_SELL);
            if (gd_316 > 0)
            {
               if (ExtTrade.Sell(gd_316, _Symbol, g_bid_252,
                                 StopShort(g_ask_260, (int)gd_144),
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
                                StopLong(g_bid_252, (int)gd_144),
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
//| Normalize Double                                                 |
//+------------------------------------------------------------------+
double ND(double ad_0)
{
   return (NormalizeDouble(ad_0, _Digits));
}

//+------------------------------------------------------------------+
//| Order Close Market                                               |
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
//| Get Lots                                                         |
//+------------------------------------------------------------------+
double fGetLots(int a_cmd_0)
{
   double l_lots_4 = Lots; // Initialize to default value
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

   // Check margin requirements in MQL5
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
//| Count Trades                                                     |
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
//| Close This Symbol All                                           |
//+------------------------------------------------------------------+
void CloseThisSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) == g_magic_208)
            {
               ExtTrade.PositionClose(ticket);
            }
            Sleep(1000);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close Symbol All                                                |
//+------------------------------------------------------------------+
void CloseSymbolAll()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ExtTrade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Stop Long                                                        |
//+------------------------------------------------------------------+
double StopLong(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 - ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Stop Short                                                       |
//+------------------------------------------------------------------+
double StopShort(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 + ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Take Long                                                        |
//+------------------------------------------------------------------+
double TakeLong(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 + ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Take Short                                                       |
//+------------------------------------------------------------------+
double TakeShort(double ad_0, int ai_8)
{
   if (ai_8 == 0)
      return (0);
   return (ad_0 - ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Calculate Profit                                                |
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
//| Trailing Alls                                                   |
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
                PositionGetInteger(POSITION_MAGIC) == g_magic_208)
            {
               ExtSymbolInfo.RefreshRates();

               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               {
                  l_ord_stoploss_20 = PositionGetDouble(POSITION_SL);
                  if (ExtSymbolInfo.Bid() - PositionGetDouble(POSITION_PRICE_OPEN) >
                      _Point * ai_0)
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
                  if (PositionGetDouble(POSITION_PRICE_OPEN) - ExtSymbolInfo.Ask() >
                      _Point * ai_0)
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
}

//+------------------------------------------------------------------+
//| Account Equity High                                             |
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
//| Find Last Buy Price                                             |
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
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

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
//| Find Last Sell Price                                            |
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
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != g_magic_208)
            continue;

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
//| Get Last Lot Size                                               |
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
//| Download and Parse CSV from Google Sheets                        |
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

   int res = WebRequest(
       "GET",
       GoogleSheetURL,
       cookie,
       referer,
       timeout,
       post,
       0,
       result,
       result_headers);

   if (res == -1)
   {
      int error = GetLastError();
      Print("ERROR: WebRequest failed. Error code: ", error);

      if (error == 4060)
      {
         Print("ERROR: URL not allowed. Please add URL to Tools -> Options -> Expert Advisors -> Allow WebRequest");
         Print("Add this URL: https://docs.google.com");
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

   return false;
}

//+------------------------------------------------------------------+
//| Parse CSV from Memory                                            |
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

         // CSV format: No., Name, User, Password, Date Start, Date End
         // We need: User (index 2), Password (index 3), Date End (index 5)
         if (count >= 6)
         {
            ArrayResize(csvRecords, totalRecords + 1);
            csvRecords[totalRecords].username = fields[2];              // User column
            csvRecords[totalRecords].passwordHash = fields[3];          // Password column
            csvRecords[totalRecords].expDate = StringToTime(fields[5]); // Date End column
            totalRecords++;
         }
      }
   }

   ArrayResize(lines, 0);

   return totalRecords > 0;
}

//+------------------------------------------------------------------+
//| Validate Username, Password and Expiry Date                      |
//+------------------------------------------------------------------+
bool ValidateCSVUser(string inputUsername, string inputPassword)
{
   if (StringLen(inputUsername) == 0 || StringLen(inputPassword) == 0)
   {
      Print("ERROR: Username or Password is empty");
      return false;
   }

   // Always use MD5 hash
   string inputPasswordHash = MD5Hash(inputPassword);
   Print("Using MD5 hash: ", StringSubstr(inputPasswordHash, 0, 8), "...");
   Print("inputPasswordHash: ", inputPasswordHash);
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
//| Display Info                                                     |
//+------------------------------------------------------------------+
void Display_Info(string mess = "Inside trading hours")
{
   string BrokerTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string LocalComputerTime = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);

   // Get adjusted time info
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
      {
         csvStatus = "CSV Auth: Account " +
                     IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                     " (" + IntegerToString(csvDaysRemaining) + " days left)";
      }
      else
      {
         csvStatus = "CSV Auth: FAILED";
      }
   }

   Comment(
       "Forex Account Server:", AccountInfoString(ACCOUNT_SERVER),
       "\n", csvStatus != "" ? csvStatus + "\n" : "",
       "Lots: ", NormalizeDouble(GetLastLotSize(), 2), " OrderTotal=", CountTrades(),
       "\n", "Symbol: ", _Symbol, "  Account: ",
       NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE), 2),
       "  MARGIN:", NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN), 2),
       "  FREEMARGIN:", NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2),
       "\n", "SellPrice: ", FindLastSellPrice(), " BuyPrice: ", FindLastBuyPrice(),
       "\n", "BrokerTime: ", BrokerTime,
       "\n", "LocalComputerTime: ", LocalComputerTime,
       "\n", "AdjustedTime(Srv+TZ): ", AdjustedTimeStr, "  Timezone: UTC+", TimezoneStr,
       "\n ", mess,
       "\n", "Trading Hours: ", StartHour, ":00 - ", EndHour, ":00 (Adjusted)",
       "\n");
}
