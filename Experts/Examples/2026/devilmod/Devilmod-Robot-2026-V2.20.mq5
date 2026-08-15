//+------------------------------------------------------------------+
//|                          Devilmod-Robot-2026-V2.20.mq5           |
//|                          Improved Entry Conditions                |
//|                          Based on Backtest Analysis               |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "2.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| CHANGELOG V2.20                                                   |
//| - Timeframes: H4, H1, M15 (removed M30, M5, M1)                 |
//| - Confirmations: 3/5 majority voting (was 12/12 all required)    |
//| - Added ADX > 20 filter for trend strength                       |
//| - Shift=1 completed bars only (was shift=0 incomplete)           |
//| - Trading hours: 08:00-23:00 with day-specific rules             |
//| - RSI: BUY 50-70, SELL 30-50 (was 40-80 too wide)               |
//| - Removed MACD M1 (too noisy, false signals)                     |
//| - Thursday priority, avoid Monday early session                   |
//| - Avoid 22:00-23:00 (low win rate period)                        |
//+------------------------------------------------------------------+

// CSV Authentication Parameters
input string CSV_Password = "123456";
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

// Trading Parameters
int gi_76 = 1;
bool gi_80 = false;
bool gi_84 = true;
double gd_88 = 1.2;          // Martingale multiplier
double g_slippage_96 = 5.0;
input double Lots = 0.05;
double gd_112 = 2.0;
input double g_pips_120 = 3500.0;  // TP With Point
double g_pips_128 = 0.0;
input double gd_136 = 2000.0;      // Trailing
input double gd_144 = 1200.0;      // SL
input double distance = 1500.0;     // Distance From Before Price
double g_pips_152 = 7.0;
input int MaxTrades = 15;
bool gi_164 = false;
double gd_168 = 20.0;
bool gi_176 = true;
bool gi_180 = false;
double gd_184 = 0.0;
bool gi_192 = false;
input bool UseManualTrade = false;
input bool UseHourTrade = true;
input int StartHour = 8;      // V2.20: Start at 08:00 (was 15:00)
input int EndHour = 23;       // End at 23:00
input int g_magic_208 = 0;

// V2.20: Day-specific trading parameters
input bool UseDayFilter = true;       // Enable day-specific filtering
input bool TradeMonday = true;        // Allow Monday trading
input bool TradeTuesday = true;       // Allow Tuesday trading
input bool TradeWednesday = true;     // Allow Wednesday trading
input bool TradeThursday = true;      // Allow Thursday trading (BEST DAY)
input bool TradeFriday = true;        // Allow Friday trading
input int FridayStartHour = 7;        // Friday start hour
input int FridayEndHour = 14;         // Friday end hour (extended from 10)

// V2.20: Time avoidance
input bool AvoidLateNight = true;     // Avoid 22:00-23:00 (low win rate)
input int AvoidStartHour = 22;
input int AvoidEndHour = 23;

// V2.20: ADX Parameters
input int ADX_Period = 14;
input double ADX_MinStrength = 20.0;  // Minimum ADX for trend confirmation

// V2.20: Confirmation Parameters
input int MinConfirmations = 3;       // Minimum confirmations needed (out of 5)

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
string gs_296 = "Devilmod-Robot-2026-V2.20";
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

// V2.20: Indicator Handles - Only H4, H1, M15
int HandleMACD_H4, HandleMACD_H1, HandleMACD_M15;
int HandleSto_H4, HandleSto_H1, HandleSto_M15;
int HandleRSI_H4, HandleRSI_H1, HandleRSI_M15;
int HandleADX_H4, HandleADX_H1, HandleADX_M15;

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
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0)
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
//| Get ADX value                                                    |
//+------------------------------------------------------------------+
double GetADX(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get +DI value                                                    |
//+------------------------------------------------------------------+
double GetPlusDI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 1, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get -DI value                                                    |
//+------------------------------------------------------------------+
double GetMinusDI(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(handle, 2, shift, 1, buffer) > 0)
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
//| V2.20: Check if trading is allowed for current time/day          |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayOfWeek = dt.day_of_week;
   int hourOfDay = dt.hour;

   // Sunday = 0, Saturday = 6 -> No trade
   if (dayOfWeek == 0 || dayOfWeek == 6)
   {
      Comment("วันหยุด - ไม่เปิดเทรดวันเสาร์-อาทิตย์");
      return false;
   }

   // V2.20: Day-specific filtering
   if (UseDayFilter)
   {
      // Monday: Allow but prefer afternoon (15:00+)
      if (dayOfWeek == 1 && !TradeMonday)
      {
         Comment("วันจันทร์ - ปิดเทรดตามตั้งค่า");
         return false;
      }

      // Tuesday
      if (dayOfWeek == 2 && !TradeTuesday)
      {
         Comment("วันอังคาร - ปิดเทรดตามตั้งค่า");
         return false;
      }

      // Wednesday
      if (dayOfWeek == 3 && !TradeWednesday)
      {
         Comment("วันพุธ - ปิดเทรดตามตั้งค่า");
         return false;
      }

      // Thursday: BEST DAY - always allow
      if (dayOfWeek == 4 && !TradeThursday)
      {
         Comment("วันพฤหัสบดี - ปิดเทรดตามตั้งค่า");
         return false;
      }

      // Friday: Extended hours
      if (dayOfWeek == 5 && !TradeFriday)
      {
         Comment("วันศุกร์ - ปิดเทรดตามตั้งค่า");
         return false;
      }
   }

   // V2.20: Friday special hours (07:00-14:00)
   if (dayOfWeek == 5)
   {
      if (hourOfDay < FridayStartHour || hourOfDay > FridayEndHour)
      {
         if (PositionsTotal() < 1)
         {
            Comment("วันศุกร์นอกเวลาเทรด (เปิด ", FridayStartHour, ":00 - ", FridayEndHour, ":00)");
            return false;
         }
      }
   }

   // V2.20: Avoid late night (22:00-23:00) - low win rate period
   if (AvoidLateNight && hourOfDay >= AvoidStartHour && hourOfDay <= AvoidEndHour)
   {
      if (PositionsTotal() < 1)
      {
         Comment("หลีกเลี่ยงช่วง ", AvoidStartHour, ":00-", AvoidEndHour, ":00 (Win Rate ต่ำ)");
         return false;
      }
   }

   // General trading hours filter
   if (UseHourTrade)
   {
      if (hourOfDay < StartHour || hourOfDay > EndHour)
      {
         if (PositionsTotal() < 1)
         {
            Comment("นอกเวลาเทรด (เปิด ", StartHour, ":00 - ", EndHour, ":00)");
            return false;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| V2.20: Analyze Trend - 3/5 Majority Voting System                |
//| Confirmation 1: Price Trend (H4, H1, M15)                       |
//| Confirmation 2: MACD Direction (H4, H1, M15)                     |
//| Confirmation 3: RSI Zone + Direction                             |
//| Confirmation 4: Stochastic Zone + Direction                      |
//| Confirmation 5: ADX Trend Strength                               |
//+------------------------------------------------------------------+
string AnalyzeTrend()
{
   int buyScore = 0;
   int sellScore = 0;

   // ================================================================
   // Confirmation 1: Price Trend (H4 > H1 > M15 alignment)
   // ================================================================
   double h4_1 = GetClose(PERIOD_H4, 1);
   double h4_2 = GetClose(PERIOD_H4, 2);
   double h1_1 = GetClose(PERIOD_H1, 1);
   double h1_2 = GetClose(PERIOD_H1, 2);
   double m15_1 = GetClose(PERIOD_M15, 1);
   double m15_2 = GetClose(PERIOD_M15, 2);

   bool h4_up = (h4_1 > h4_2);
   bool h1_up = (h1_1 > h1_2);
   bool m15_up = (m15_1 > m15_2);
   bool h4_dn = (h4_1 < h4_2);
   bool h1_dn = (h1_1 < h1_2);
   bool m15_dn = (m15_1 < m15_2);

   // Bullish: H4 and H1 both up, or all 3 up
   if ((h4_up && h1_up) || (h4_up && m15_up) || (h1_up && m15_up))
      buyScore++;

   // Bearish: H4 and H1 both down, or all 3 down
   if ((h4_dn && h1_dn) || (h4_dn && m15_dn) || (h1_dn && m15_dn))
      sellScore++;

   // ================================================================
   // Confirmation 2: MACD Direction (at least 2 out of 3 TFs rising)
   // ================================================================
   double macdH4 = GetMACD(HandleMACD_H4, 1);
   double macdH4_prev = GetMACD(HandleMACD_H4, 2);
   double macdH1 = GetMACD(HandleMACD_H1, 1);
   double macdH1_prev = GetMACD(HandleMACD_H1, 2);
   double macdM15 = GetMACD(HandleMACD_M15, 1);
   double macdM15_prev = GetMACD(HandleMACD_M15, 2);

   int macdUpCount = 0;
   int macdDnCount = 0;
   if (macdH4 > macdH4_prev) macdUpCount++;
   if (macdH1 > macdH1_prev) macdUpCount++;
   if (macdM15 > macdM15_prev) macdUpCount++;
   if (macdH4 < macdH4_prev) macdDnCount++;
   if (macdH1 < macdH1_prev) macdDnCount++;
   if (macdM15 < macdM15_prev) macdDnCount++;

   if (macdUpCount >= 2) buyScore++;
   if (macdDnCount >= 2) sellScore++;

   // ================================================================
   // Confirmation 3: RSI Zone + Direction (V2.20: tighter ranges)
   // BUY: RSI 50-70 and rising
   // SELL: RSI 30-50 and falling
   // ================================================================
   double rsiH1 = GetRSI(HandleRSI_H1, 1);
   double rsiH1_prev = GetRSI(HandleRSI_H1, 2);

   bool rsiBuyZone = (rsiH1 > 50 && rsiH1 < 70 && rsiH1 > rsiH1_prev);
   bool rsiSellZone = (rsiH1 < 50 && rsiH1 > 30 && rsiH1 < rsiH1_prev);

   if (rsiBuyZone) buyScore++;
   if (rsiSellZone) sellScore++;

   // ================================================================
   // Confirmation 4: Stochastic Zone + Direction
   // BUY: Stoch H1 > 30 and < 70, rising
   // SELL: Stoch H1 < 70 and > 30, falling
   // ================================================================
   double stoH1 = GetStochastic(HandleSto_H1, 1);
   double stoH1_prev = GetStochastic(HandleSto_H1, 2);
   double stoM15 = GetStochastic(HandleSto_M15, 1);

   bool stoBuy = (stoH1 > 30 && stoH1 < 70 && stoH1 > stoH1_prev && stoM15 > 30);
   bool stoSell = (stoH1 < 70 && stoH1 > 30 && stoH1 < stoH1_prev && stoM15 < 70);

   if (stoBuy) buyScore++;
   if (stoSell) sellScore++;

   // ================================================================
   // Confirmation 5: ADX Trend Strength (ADX > 20)
   // ================================================================
   double adxH1 = GetADX(HandleADX_H1, 1);
   double plusDI_H1 = GetPlusDI(HandleADX_H1, 1);
   double minusDI_H1 = GetMinusDI(HandleADX_H1, 1);
   double adxM15 = GetADX(HandleADX_M15, 1);

   bool adxStrong = (adxH1 > ADX_MinStrength || adxM15 > ADX_MinStrength);
   bool adxBullish = (plusDI_H1 > minusDI_H1);
   bool adxBearish = (minusDI_H1 > plusDI_H1);

   if (adxStrong && adxBullish) buyScore++;
   if (adxStrong && adxBearish) sellScore++;

   // ================================================================
   // V2.20: Majority Voting (3 out of 5)
   // ================================================================
   Print("=== V2.20 Trend Analysis ===");
   Print("  BUY Score: ", buyScore, "/", MinConfirmations, " | SELL Score: ", sellScore, "/", MinConfirmations);
   Print("  H4:", h4_1, " H1:", h1_1, " M15:", m15_1);
   Print("  RSI:", rsiH1, " Stoch:", stoH1, " ADX:", adxH1, " +DI:", plusDI_H1, " -DI:", minusDI_H1);

   if (buyScore >= MinConfirmations && buyScore > sellScore)
   {
      Print(">>> BUY Signal Confirmed (", buyScore, "/", MinConfirmations, " confirmations)");
      return "BUY";
   }
   else if (sellScore >= MinConfirmations && sellScore > buyScore)
   {
      Print(">>> SELL Signal Confirmed (", sellScore, "/", MinConfirmations, " confirmations)");
      return "SELL";
   }

   Print(">>> No Signal (BUY:", buyScore, " SELL:", sellScore, " Need:", MinConfirmations, ")");
   return "NONE";
}

//+------------------------------------------------------------------+
//| FiboLevel                                                        |
//+------------------------------------------------------------------+
string FiboLevel()
{
   static double fibLow, fibHigh, fibLowM60, fibHighM60;
   int bars = 60;
   string Action = "";
   double highBuffer[], lowBuffer[];
   ArraySetAsSeries(highBuffer, true);
   ArraySetAsSeries(lowBuffer, true);
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, bars, highBuffer);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, bars, lowBuffer);
   fibHigh = highBuffer[ArrayMaximum(highBuffer)];
   fibLow = lowBuffer[ArrayMinimum(lowBuffer)];
   CopyHigh(_Symbol, PERIOD_M5, 0, bars, highBuffer);
   CopyLow(_Symbol, PERIOD_M5, 0, bars, lowBuffer);
   fibHighM60 = highBuffer[ArrayMaximum(highBuffer)];
   fibLowM60 = lowBuffer[ArrayMinimum(lowBuffer)];
   double fib382 = fibHigh - (fibHigh - fibLow) * 0.382;
   double fib618 = fibHigh - (fibHigh - fibLow) * 0.618;
   double fib382M60 = fibHighM60 - (fibHighM60 - fibLowM60) * 0.382;
   double fib618M60 = fibHighM60 - (fibHighM60 - fibLowM60) * 0.618;
   ExtSymbolInfo.Refresh();
   double ask = ExtSymbolInfo.Ask();
   double bid = ExtSymbolInfo.Bid();
   if (ask <= fib618 && ask <= fib618M60 && PositionsTotal() == 0)
      Action = "UP";
   if (bid >= fib382 && bid >= fib382M60 && PositionsTotal() == 0)
      Action = "DN";
   return Action;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
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
       return (INIT_SUCCEEDED);

    if (!MQLInfoInteger(MQL_TESTER) && StringLen(CSV_Password) > 0)
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

   // V2.20: Initialize Indicator Handles - Only H4, H1, M15
   HandleMACD_H4 = iMACD(_Symbol, PERIOD_H4, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_H1 = iMACD(_Symbol, PERIOD_H1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   HandleMACD_M15 = iMACD(_Symbol, PERIOD_M15, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);

   HandleSto_H4 = iStochastic(_Symbol, PERIOD_H4, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_H1 = iStochastic(_Symbol, PERIOD_H1, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);
   HandleSto_M15 = iStochastic(_Symbol, PERIOD_M15, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, STO_LOWHIGH);

   HandleRSI_H4 = iRSI(_Symbol, PERIOD_H4, 14, PRICE_CLOSE);
   HandleRSI_H1 = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   HandleRSI_M15 = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);

   // V2.20: ADX for trend strength
   HandleADX_H4 = iADX(_Symbol, PERIOD_H4, ADX_Period);
   HandleADX_H1 = iADX(_Symbol, PERIOD_H1, ADX_Period);
   HandleADX_M15 = iADX(_Symbol, PERIOD_M15, ADX_Period);

   // Validate indicator handles
   if (HandleMACD_H4 == INVALID_HANDLE || HandleMACD_H1 == INVALID_HANDLE || HandleMACD_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MACD indicator handles");
      return (INIT_FAILED);
   }
   if (HandleSto_H4 == INVALID_HANDLE || HandleSto_H1 == INVALID_HANDLE || HandleSto_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Stochastic indicator handles");
      return (INIT_FAILED);
   }
   if (HandleRSI_H4 == INVALID_HANDLE || HandleRSI_H1 == INVALID_HANDLE || HandleRSI_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create RSI indicator handles");
      return (INIT_FAILED);
   }
   if (HandleADX_H4 == INVALID_HANDLE || HandleADX_H1 == INVALID_HANDLE || HandleADX_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ADX indicator handles");
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
   if (HandleMACD_H4 != INVALID_HANDLE) IndicatorRelease(HandleMACD_H4);
   if (HandleMACD_H1 != INVALID_HANDLE) IndicatorRelease(HandleMACD_H1);
   if (HandleMACD_M15 != INVALID_HANDLE) IndicatorRelease(HandleMACD_M15);
   if (HandleSto_H4 != INVALID_HANDLE) IndicatorRelease(HandleSto_H4);
   if (HandleSto_H1 != INVALID_HANDLE) IndicatorRelease(HandleSto_H1);
   if (HandleSto_M15 != INVALID_HANDLE) IndicatorRelease(HandleSto_M15);
   if (HandleRSI_H4 != INVALID_HANDLE) IndicatorRelease(HandleRSI_H4);
   if (HandleRSI_H1 != INVALID_HANDLE) IndicatorRelease(HandleRSI_H1);
   if (HandleRSI_M15 != INVALID_HANDLE) IndicatorRelease(HandleRSI_M15);
   if (HandleADX_H4 != INVALID_HANDLE) IndicatorRelease(HandleADX_H4);
   if (HandleADX_H1 != INVALID_HANDLE) IndicatorRelease(HandleADX_H1);
   if (HandleADX_M15 != INVALID_HANDLE) IndicatorRelease(HandleADX_M15);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check CSV Authentication
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Failed! EA is disabled.");
      return;
   }

   // V2.20: Check if trading is allowed (day + time)
   if (!IsTradeAllowed())
      return;

   Display_Info();

   // V2.20: Analyze trend with majority voting (3/5)
   string trendSignal = AnalyzeTrend();

   bool is_buy = false, is_sell = false;
   double l_ord_lots_0 = 0.0;
   double l_ord_lots_8 = 0.0;

   if (trendSignal == "BUY")
   {
      is_buy = true;
      Print(">>> BUY Signal Ready");
   }
   else if (trendSignal == "SELL")
   {
      is_sell = true;
      Print(">>> SELL Signal Ready");
   }

   // Get local time
   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int hourOfDay = dt.hour;
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
            if (gi_176) TrailingAlls((int)gd_136, (int)gd_144, g_price_244);
            break;
         }
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            gi_344 = false;
            gi_348 = true;
            l_ord_lots_8 = PositionGetDouble(POSITION_VOLUME);
            if (gi_176) TrailingAlls((int)gd_136, (int)gd_144, g_price_244);
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
               if (LastSellPrice > 0)
               {
                  double pointDiffSell = MathAbs(currentPriceSell - LastSellPrice) / ExtSymbolInfo.Point();
                  if (pointDiffSell < distance)
                  {
                     Comment("รอระยะ SELL... Distance=", (int)pointDiffSell, " < ต้องการ=", (int)distance);
                     return;
                  }
               }
               ExtSymbolInfo.RefreshRates();
               if (ExtTrade.Sell(gd_316, _Symbol, ExtSymbolInfo.Bid(),
                                 StopShort(ExtSymbolInfo.Ask(), (int)gd_144),
                                 TakeShort(ExtSymbolInfo.Bid(), (int)g_pips_120),
                                 gs_296 + "-" + IntegerToString(gi_312)))
               {
                  Print("SELL order opened - Lot: ", gd_316);
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
                     double pointDiffBuy = MathAbs(currentPriceBuy - LastBuyPrice) / ExtSymbolInfo.Point();
                     if (pointDiffBuy < distance)
                     {
                        Comment("รอระยะ BUY... Distance=", (int)pointDiffBuy, " < ต้องการ=", (int)distance);
                        return;
                     }
                  }
                  ExtSymbolInfo.RefreshRates();
                  if (ExtTrade.Buy(gd_316, _Symbol, ExtSymbolInfo.Ask(),
                                   StopLong(ExtSymbolInfo.Bid(), (int)gd_144),
                                   TakeLong(ExtSymbolInfo.Ask(), (int)g_pips_120),
                                   gs_296 + "-" + IntegerToString(gi_312)))
                  {
                     Print("BUY order opened - Lot: ", gd_316);
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

   // V2.20: Open first order based on trend signal
   if (gi_340 && gi_328 < 1)
   {
      Print(">>> Ready to open first order - Signal:", trendSignal);

      ExtSymbolInfo.RefreshRates();
      g_bid_252 = ExtSymbolInfo.Bid();
      g_ask_260 = ExtSymbolInfo.Ask();

      if (!gi_348 && !gi_344 && ls_32 == "true")
      {
         gi_312 = gi_328;

         if (UseManualTrade)
         {
            Print("Manual trade mode active - waiting for manual signals");
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
                  Print("First SELL opened - Lot: ", gd_316);
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
                  Print("First BUY opened - Lot: ", gd_316);
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
         else
         {
            Print("Conditions not met - Positions:", PositionsTotal(),
                  " BUY:", is_buy, " SELL:", is_sell);
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
   if (l_lots_4 < minlot) l_lots_4 = minlot;
   if (l_lots_4 > maxlot) l_lots_4 = maxlot;
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
            ExtTrade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Stop Long                                                        |
//+------------------------------------------------------------------+
double StopLong(double ad_0, int ai_8)
{
   if (ai_8 == 0) return (0);
   return (ad_0 - ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Stop Short                                                       |
//+------------------------------------------------------------------+
double StopShort(double ad_0, int ai_8)
{
   if (ai_8 == 0) return (0);
   return (ad_0 + ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Take Long                                                        |
//+------------------------------------------------------------------+
double TakeLong(double ad_0, int ai_8)
{
   if (ai_8 == 0) return (0);
   return (ad_0 + ai_8 * _Point);
}

//+------------------------------------------------------------------+
//| Take Short                                                       |
//+------------------------------------------------------------------+
double TakeShort(double ad_0, int ai_8)
{
   if (ai_8 == 0) return (0);
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
   int res = WebRequest("GET", GoogleSheetURL, cookie, referer, timeout, post, 0, result, result_headers);
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
//| Validate Username, Password and Expiry Date                      |
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
void Display_Info()
{
   string BrokerTime = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string LocalComputerTime = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
   string csvStatus = "";
   if (StringLen(CSV_Password) > 0)
   {
      if (isCSVAuthenticated)
         csvStatus = "CSV Auth: Account " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " (" + IntegerToString(csvDaysRemaining) + " days left)";
      else
         csvStatus = "CSV Auth: FAILED";
   }

   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   string dayNames[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
   string dayStr = dayNames[dt.day_of_week];

   // Get current ADX for display
   double adxH1 = GetADX(HandleADX_H1, 1);
   double rsiH1 = GetRSI(HandleRSI_H1, 1);
   string trendStr = "Analyzing...";
   if (CountTrades() == 0)
   {
      string signal = AnalyzeTrend();
      if (signal == "BUY") trendStr = "BULLISH (Buy Ready)";
      else if (signal == "SELL") trendStr = "BEARISH (Sell Ready)";
      else trendStr = "WAITING (No Signal)";
   }
   else
      trendStr = "In Position (" + IntegerToString(CountTrades()) + " orders)";

   Comment(
       "=== Devilmod V2.20 ===",
       "\n", csvStatus != "" ? csvStatus + "\n" : "",
       "Server: ", AccountInfoString(ACCOUNT_SERVER),
       "\n", "Lots: ", NormalizeDouble(GetLastLotSize(), 2),
       " | Orders: ", CountTrades(), "/", MaxTrades,
       "\n", "Trend: ", trendStr,
       "\n", "ADX: ", DoubleToString(adxH1, 1),
       " | RSI: ", DoubleToString(rsiH1, 1),
       "\n", "Day: ", dayStr,
       " | Time: ", TimeToString(dt.hour, TIME_MINUTES), ":", TimeToString(dt.min, TIME_MINUTES),
       "\n", "SellPrice: ", FindLastSellPrice(),
       " | BuyPrice: ", FindLastBuyPrice(),
       "\n", "Balance: ", NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE), 2),
       " | Equity: ", NormalizeDouble(AccountInfoDouble(ACCOUNT_EQUITY), 2),
       "\n", "EA Version: V2.20 (Improved Entry + ADX + Day Filter)",
       "\n");
}
//+------------------------------------------------------------------+
