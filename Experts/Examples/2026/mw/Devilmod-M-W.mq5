//+------------------------------------------------------------------+
//|                                          Devilmod-M-W.mq5        |
//|                              M & W Pattern Trading Expert        |
//|                                  Copyright 2026, DevilMod        |
//+------------------------------------------------------------------+
#property copyright "DevilMod 2026"
#property link "https://www.mql5.com"
#property version "1.00"
#property description "M (Double Top) และ W (Double Bottom) Pattern Trading"
#property description "ระบบตรวจจับรูปแบบอัตโนมัติพร้อม Momentum Confirmation"
#property strict

// Include MT5 Trade Libraries
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters - CSV Authentication                            |
//+------------------------------------------------------------------+
input group "=== Authentication ===" input string CSV_Password = ""; // Password for authentication (leave blank to disable)
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

//+------------------------------------------------------------------+
//| Input Parameters - Pattern Detection                             |
//+------------------------------------------------------------------+
input group "=== Pattern Detection ===" input double PatternTolerance_Percent = 0.2; // Pattern Tolerance (0.1-0.5%)
input int LookbackBars = 100;                                                        // Bars to scan
input int SwingStrength = 5;                                                         // Swing strength (bars each side)
input double NecklineBreak_Percent = 0.3;                                            // Neckline break threshold (%)
input double MinRetracement_Percent = 10.0;                                          // Minimum retracement (%)

//+------------------------------------------------------------------+
//| Input Parameters - Entry Settings                                |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_AGGRESSIVE,  // Aggressive: Enter on neckline break
   ENTRY_CONSERVATIVE // Conservative: Wait for retest
};

input group "=== Entry Settings ===" input ENUM_ENTRY_MODE EntryMode = ENTRY_CONSERVATIVE; // Entry mode
input int RetestWaitBars = 10;                                                             // Max bars to wait for retest

//+------------------------------------------------------------------+
//| Input Parameters - Risk Management                               |
//+------------------------------------------------------------------+
input group "=== Risk Management ===" input double RiskPercent = 1.0; // Risk per trade (%)
input double RR_Ratio = 1.5;                                          // Risk:Reward ratio (1.0, 1.5, 2.0)
input int SL_Buffer_Pips = 20;                                        // SL buffer (pips)
input double Lots = 0.01;                                             // Fixed lot (if RiskPercent = 0)
input int g_magic_number = 20260509;                                  // Magic number

//+------------------------------------------------------------------+
//| Input Parameters - Confirmation Filters                          |
//+------------------------------------------------------------------+
input group "=== Confirmation Filters ===" input bool UseRSIDivergence = true; // Use RSI Divergence
input bool UseMACDWeakness = true;                                             // Use MACD weakness check
input bool UseRejectionCandle = false;                                         // Use rejection candle check
input bool UseTrendFilter = true;                                              // MA50/200 trend filter

//+------------------------------------------------------------------+
//| Input Parameters - Time Filters                                  |
//+------------------------------------------------------------------+
enum ENUM_TIME_MODE
{
   TIME_SIMPLE,      // Simple: Same hours every day
   TIME_OPTIMIZED    // Optimized: Different hours per day (Best winrate)
};

input group "=== Time Filters ===" 
input bool UseHourTrade = true;                       // Enable hour filter
input ENUM_TIME_MODE TimeMode = TIME_OPTIMIZED;       // Time filter mode

// Simple Mode - Same hours every day
input group "=== Simple Mode Settings ==="
input int StartHour = 15;                             // Start hour (all days)
input int EndHour = 23;                               // End hour (all days)

// Optimized Mode - Different hours per day for maximum winrate
input group "=== Optimized Mode Settings ==="
input bool Trade_Monday = true;                       // Trade on Monday
input int Monday_StartHour = 15;                      // Monday start (delayed - market settling)
input int Monday_EndHour = 23;                        // Monday end

input bool Trade_Tuesday = true;                      // Trade on Tuesday (Best day!)
input int Tuesday_StartHour = 14;                     // Tuesday start (full London-NY)
input int Tuesday_EndHour = 23;                       // Tuesday end

input bool Trade_Wednesday = true;                    // Trade on Wednesday (Best day!)
input int Wednesday_StartHour = 14;                   // Wednesday start (full London-NY)
input int Wednesday_EndHour = 23;                     // Wednesday end

input bool Trade_Thursday = true;                     // Trade on Thursday (Best day!)
input int Thursday_StartHour = 14;                    // Thursday start (full London-NY)
input int Thursday_EndHour = 23;                      // Thursday end

input bool Trade_Friday = true;                       // Trade on Friday
input int Friday_StartHour = 14;                      // Friday start
input int Friday_EndHour = 20;                        // Friday end (early stop - avoid weekend close)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// MT5 Trade Objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CAccountInfo ExtAccountInfo;
CPositionInfo ExtPositionInfo;

// CSV Authentication
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

// Indicator Handles
int HandleATR;
int HandleRSI;
int HandleMACD;
int HandleMA50;
int HandleMA200;

// Pattern Detection Structure
struct PatternInfo
{
   bool found;
   datetime time;
   int type; // 1=M pattern (SELL), 2=W pattern (BUY)
   double peak1_price;
   double peak2_price;
   int peak1_index;
   int peak2_index;
   double neckline_price;
   int neckline_index;
   double pattern_height;
   bool neckline_broken;
   bool waiting_retest;
   datetime break_time;
};
PatternInfo currentPattern;

// Global State
datetime g_last_bar_time = 0;
bool g_position_opened = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Initializing Devilmod-M-W EA ===");

   // Initialize symbol info
   if (!ExtSymbolInfo.Name(_Symbol))
   {
      Print("ERROR: Failed to initialize symbol info");
      return (INIT_FAILED);
   }
   ExtSymbolInfo.Refresh();

   // Set trade parameters
   ExtTrade.SetExpertMagicNumber(g_magic_number);
   ExtTrade.SetDeviationInPoints(50);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ExtTrade.SetAsyncMode(false);

   // CSV Authentication Check
   string accountUsername = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));

   if (isCSVAuthenticated && isChecked)
   {
      Print("Authentication: Already authenticated");
   }
   else if (StringLen(CSV_Password) > 0)
   {
      Print("=== Starting CSV Authentication ===");
      Print("Account Number: ", accountUsername);

      if (DownloadCSVFile())
      {
         if (ValidateCSVUser(accountUsername, CSV_Password))
         {
            Alert("✅ Login Successful! Account: ", accountUsername);
            Print("AUTHENTICATED: Days remaining = ", csvDaysRemaining);
            isChecked = true;
         }
         else
         {
            Alert("❌ Login Failed! Check your credentials.");
            Print("ERROR: Authentication failed");
            isChecked = false;
            return (INIT_FAILED);
         }
      }
      else
      {
         Alert("❌ Failed to download CSV data. Check internet connection.");
         Print("ERROR: Failed to download CSV file");
         isChecked = false;
         return (INIT_FAILED);
      }
   }
   else
   {
      Print("Authentication: Disabled (no password provided)");
      isChecked = false;
      isCSVAuthenticated = true;
   }

   // Initialize Indicators
   HandleATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   HandleRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   HandleMACD = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   HandleMA50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   HandleMA200 = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);

   if (HandleATR == INVALID_HANDLE || HandleRSI == INVALID_HANDLE ||
       HandleMACD == INVALID_HANDLE || HandleMA50 == INVALID_HANDLE ||
       HandleMA200 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return (INIT_FAILED);
   }

   // Initialize pattern structure
   ResetPattern();

   Print("✅ Initialization successful!");
   Print("Pattern Tolerance: ", PatternTolerance_Percent, "%");
   Print("Entry Mode: ", (EntryMode == ENTRY_AGGRESSIVE ? "Aggressive" : "Conservative"));
   Print("Risk per trade: ", RiskPercent, "%");
   Print("Risk:Reward Ratio: 1:", RR_Ratio);

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== Devilmod-M-W EA Deinitialization ===");

   // Release indicator handles
   if (HandleATR != INVALID_HANDLE)
      IndicatorRelease(HandleATR);
   if (HandleRSI != INVALID_HANDLE)
      IndicatorRelease(HandleRSI);
   if (HandleMACD != INVALID_HANDLE)
      IndicatorRelease(HandleMACD);
   if (HandleMA50 != INVALID_HANDLE)
      IndicatorRelease(HandleMA50);
   if (HandleMA200 != INVALID_HANDLE)
      IndicatorRelease(HandleMA200);

   Comment("");
}

//+------------------------------------------------------------------+
//| Check if current day/time is allowed for trading                 |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
   if(!UseHourTrade) return true; // No time filter
   
   // Get local time
   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int hourOfDay = dt.hour;
   int dayOfWeek = dt.day_of_week; // 0=Sunday, 1=Monday, ..., 6=Saturday
   
   // Block weekends
   if(dayOfWeek == 0 || dayOfWeek == 6)
   {
      Comment("❌ Weekend - EA not active");
      return false;
   }
   
   // Simple Mode: Same hours every day
   if(TimeMode == TIME_SIMPLE)
   {
      if(hourOfDay >= StartHour && hourOfDay <= EndHour)
         return true;
      
      Comment("⏰ Outside trading hours (", hourOfDay, ":00)");
      return false;
   }
   
   // Optimized Mode: Different hours per day
   int start = 0, end = 0;
   bool trade_today = false;
   string day_name = "";
   
   switch(dayOfWeek)
   {
      case 1: // Monday
         trade_today = Trade_Monday;
         start = Monday_StartHour;
         end = Monday_EndHour;
         day_name = "Monday";
         break;
         
      case 2: // Tuesday
         trade_today = Trade_Tuesday;
         start = Tuesday_StartHour;
         end = Tuesday_EndHour;
         day_name = "Tuesday";
         break;
         
      case 3: // Wednesday
         trade_today = Trade_Wednesday;
         start = Wednesday_StartHour;
         end = Wednesday_EndHour;
         day_name = "Wednesday";
         break;
         
      case 4: // Thursday
         trade_today = Trade_Thursday;
         start = Thursday_StartHour;
         end = Thursday_EndHour;
         day_name = "Thursday";
         break;
         
      case 5: // Friday
         trade_today = Trade_Friday;
         start = Friday_StartHour;
         end = Friday_EndHour;
         day_name = "Friday";
         break;
   }
   
   // Check if trading is disabled for this day
   if(!trade_today)
   {
      Comment("📅 ", day_name, " trading disabled");
      return false;
   }
   
   // Check if within time window
   if(hourOfDay >= start && hourOfDay <= end)
   {
      return true;
   }
   
   Comment("⏰ ", day_name, " outside trading hours (", hourOfDay, ":00) - Allowed: ", start, ":00-", end, ":00");
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check authentication
   if (!isCSVAuthenticated)
   {
      Comment("❌ Not authenticated!");
      return;
   }

   // Check if valid trading time (includes weekend block + day-specific hours)
   if(!IsValidTradingTime())
   {
      return;
   }

   // Check for new bar
   datetime currentTime[];
   ArraySetAsSeries(currentTime, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);

   if (g_last_bar_time == currentTime[0] && !currentPattern.waiting_retest)
      return;

   g_last_bar_time = currentTime[0];

   // Refresh symbol info
   ExtSymbolInfo.Refresh();

   // Check existing position
   int positions = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == g_magic_number)
         {
            positions++;
         }
      }
   }

   if (positions > 0)
   {
      Comment("✅ Position already open");
      return;
   }

   // Main trading logic

   // 1. Check if waiting for retest
   if (currentPattern.waiting_retest && EntryMode == ENTRY_CONSERVATIVE)
   {
      if (CheckRetest())
      {
         ExecuteTrade();
         ResetPattern();
      }
      else
      {
         // Check timeout
         int bars_since_break = iBarShift(_Symbol, PERIOD_CURRENT, currentPattern.break_time);
         if (bars_since_break > RetestWaitBars)
         {
            Print("Retest timeout - resetting pattern");
            ResetPattern();
         }
      }
      return;
   }

   // 2. Detect new patterns
   DetectPatterns();

   // 3. If pattern found and confirmed, take action
   if (currentPattern.found && currentPattern.neckline_broken)
   {
      if (EntryMode == ENTRY_AGGRESSIVE)
      {
         ExecuteTrade();
         ResetPattern();
      }
      else // ENTRY_CONSERVATIVE
      {
         currentPattern.waiting_retest = true;
         currentPattern.break_time = TimeCurrent();
         Print("🔄 Waiting for retest of neckline at ", currentPattern.neckline_price);
      }
   }

   // Update comment
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Detect M and W Patterns                                          |
//+------------------------------------------------------------------+
void DetectPatterns()
{
   // Try to detect M pattern (Double Top)
   if (DetectDoubleTop())
   {
      Print("📉 M Pattern (Double Top) detected!");
      return;
   }

   // Try to detect W pattern (Double Bottom)
   if (DetectDoubleBottom())
   {
      Print("📈 W Pattern (Double Bottom) detected!");
      return;
   }
}

//+------------------------------------------------------------------+
//| Detect Double Top (M Pattern)                                    |
//+------------------------------------------------------------------+
bool DetectDoubleTop()
{
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if (CopyHigh(_Symbol, PERIOD_CURRENT, 0, LookbackBars, highs) <= 0)
      return false;
   if (CopyLow(_Symbol, PERIOD_CURRENT, 0, LookbackBars, lows) <= 0)
      return false;
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, LookbackBars, closes) <= 0)
      return false;

   // Find swing highs
   int swing_highs[];
   ArrayResize(swing_highs, 0);

   for (int i = SwingStrength; i < LookbackBars - SwingStrength; i++)
   {
      bool is_swing_high = true;

      // Check left side
      for (int j = 1; j <= SwingStrength; j++)
      {
         if (highs[i] <= highs[i - j])
         {
            is_swing_high = false;
            break;
         }
      }

      // Check right side
      if (is_swing_high)
      {
         for (int j = 1; j <= SwingStrength; j++)
         {
            if (highs[i] <= highs[i + j])
            {
               is_swing_high = false;
               break;
            }
         }
      }

      if (is_swing_high)
      {
         int size = ArraySize(swing_highs);
         ArrayResize(swing_highs, size + 1);
         swing_highs[size] = i;
      }
   }

   // Need at least 2 swing highs
   if (ArraySize(swing_highs) < 2)
      return false;

   // Check pairs of swing highs
   for (int i = 0; i < ArraySize(swing_highs) - 1; i++)
   {
      int idx1 = swing_highs[i];
      int idx2 = swing_highs[i + 1];

      double p1_high = highs[idx1];
      double p2_high = highs[idx2];

      // Check distance between peaks
      int bars_between = idx2 - idx1;
      if (bars_between < 15 || bars_between > 80)
         continue;

      // Check peak similarity (tolerance)
      double price_diff = MathAbs(p1_high - p2_high);
      double tolerance = p1_high * (PatternTolerance_Percent / 100.0);
      if (price_diff > tolerance)
         continue;

      // Find valley between peaks
      int valley_idx = idx1;
      double valley_price = lows[idx1];
      for (int j = idx1; j <= idx2; j++)
      {
         if (lows[j] < valley_price)
         {
            valley_price = lows[j];
            valley_idx = j;
         }
      }

      // Check retracement depth
      double avg_peak = (p1_high + p2_high) / 2.0;
      double retracement = ((avg_peak - valley_price) / avg_peak) * 100.0;
      if (retracement < MinRetracement_Percent)
         continue;

      // Check neckline break
      double neckline = valley_price;
      double break_threshold = neckline * (1.0 - NecklineBreak_Percent / 100.0);

      if (closes[0] < break_threshold && closes[1] >= neckline)
      {
         // Neckline broken!

         // Apply momentum confirmations
         if (!CheckMomentumConfirmation_M(idx1, idx2))
         {
            Print("⚠️ M Pattern found but momentum confirmation failed");
            continue;
         }

         // Apply trend filter
         if (UseTrendFilter && !CheckTrendFilter_SELL())
         {
            Print("⚠️ M Pattern found but trend filter failed (not in downtrend)");
            continue;
         }

         // Pattern confirmed!
         currentPattern.found = true;
         currentPattern.type = 1; // M pattern
         currentPattern.peak1_price = p1_high;
         currentPattern.peak2_price = p2_high;
         currentPattern.peak1_index = idx1;
         currentPattern.peak2_index = idx2;
         currentPattern.neckline_price = neckline;
         currentPattern.neckline_index = valley_idx;
         currentPattern.pattern_height = avg_peak - neckline;
         currentPattern.neckline_broken = true;
         currentPattern.time = TimeCurrent();

         Print("✅ M Pattern confirmed!");
         Print("  Peak1: ", p1_high, " at bar ", idx1);
         Print("  Peak2: ", p2_high, " at bar ", idx2);
         Print("  Neckline: ", neckline);
         Print("  Pattern Height: ", currentPattern.pattern_height / _Point, " pips");

         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Detect Double Bottom (W Pattern)                                 |
//+------------------------------------------------------------------+
bool DetectDoubleBottom()
{
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if (CopyHigh(_Symbol, PERIOD_CURRENT, 0, LookbackBars, highs) <= 0)
      return false;
   if (CopyLow(_Symbol, PERIOD_CURRENT, 0, LookbackBars, lows) <= 0)
      return false;
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, LookbackBars, closes) <= 0)
      return false;

   // Find swing lows
   int swing_lows[];
   ArrayResize(swing_lows, 0);

   for (int i = SwingStrength; i < LookbackBars - SwingStrength; i++)
   {
      bool is_swing_low = true;

      // Check left side
      for (int j = 1; j <= SwingStrength; j++)
      {
         if (lows[i] >= lows[i - j])
         {
            is_swing_low = false;
            break;
         }
      }

      // Check right side
      if (is_swing_low)
      {
         for (int j = 1; j <= SwingStrength; j++)
         {
            if (lows[i] >= lows[i + j])
            {
               is_swing_low = false;
               break;
            }
         }
      }

      if (is_swing_low)
      {
         int size = ArraySize(swing_lows);
         ArrayResize(swing_lows, size + 1);
         swing_lows[size] = i;
      }
   }

   // Need at least 2 swing lows
   if (ArraySize(swing_lows) < 2)
      return false;

   // Check pairs of swing lows
   for (int i = 0; i < ArraySize(swing_lows) - 1; i++)
   {
      int idx1 = swing_lows[i];
      int idx2 = swing_lows[i + 1];

      double t1_low = lows[idx1];
      double t2_low = lows[idx2];

      // Check distance between troughs
      int bars_between = idx2 - idx1;
      if (bars_between < 15 || bars_between > 80)
         continue;

      // Check trough similarity (tolerance)
      double price_diff = MathAbs(t1_low - t2_low);
      double tolerance = t1_low * (PatternTolerance_Percent / 100.0);
      if (price_diff > tolerance)
         continue;

      // Find peak between troughs
      int peak_idx = idx1;
      double peak_price = highs[idx1];
      for (int j = idx1; j <= idx2; j++)
      {
         if (highs[j] > peak_price)
         {
            peak_price = highs[j];
            peak_idx = j;
         }
      }

      // Check rally height
      double avg_trough = (t1_low + t2_low) / 2.0;
      double rally = ((peak_price - avg_trough) / avg_trough) * 100.0;
      if (rally < MinRetracement_Percent)
         continue;

      // Check neckline break
      double neckline = peak_price;
      double break_threshold = neckline * (1.0 + NecklineBreak_Percent / 100.0);

      if (closes[0] > break_threshold && closes[1] <= neckline)
      {
         // Neckline broken!

         // Apply momentum confirmations
         if (!CheckMomentumConfirmation_W(idx1, idx2))
         {
            Print("⚠️ W Pattern found but momentum confirmation failed");
            continue;
         }

         // Apply trend filter
         if (UseTrendFilter && !CheckTrendFilter_BUY())
         {
            Print("⚠️ W Pattern found but trend filter failed (not in uptrend)");
            continue;
         }

         // Pattern confirmed!
         currentPattern.found = true;
         currentPattern.type = 2; // W pattern
         currentPattern.peak1_price = t1_low;
         currentPattern.peak2_price = t2_low;
         currentPattern.peak1_index = idx1;
         currentPattern.peak2_index = idx2;
         currentPattern.neckline_price = neckline;
         currentPattern.neckline_index = peak_idx;
         currentPattern.pattern_height = neckline - avg_trough;
         currentPattern.neckline_broken = true;
         currentPattern.time = TimeCurrent();

         Print("✅ W Pattern confirmed!");
         Print("  Trough1: ", t1_low, " at bar ", idx1);
         Print("  Trough2: ", t2_low, " at bar ", idx2);
         Print("  Neckline: ", neckline);
         Print("  Pattern Height: ", currentPattern.pattern_height / _Point, " pips");

         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check Momentum Confirmation for M Pattern                        |
//+------------------------------------------------------------------+
bool CheckMomentumConfirmation_M(int peak1_idx, int peak2_idx)
{
   int checks_passed = 0;
   int checks_total = 0;

   // RSI Divergence Check
   if (UseRSIDivergence)
   {
      checks_total++;
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);

      if (CopyBuffer(HandleRSI, 0, 0, LookbackBars, rsi_buffer) > 0)
      {
         double rsi1 = rsi_buffer[peak1_idx];
         double rsi2 = rsi_buffer[peak2_idx];

         // For M pattern: RSI at peak2 should be lower than peak1 (Bearish Divergence)
         if (rsi2 < rsi1 - 2.0) // At least 2 points difference
         {
            checks_passed++;
            Print("  ✓ RSI Divergence confirmed (RSI1:", rsi1, " RSI2:", rsi2, ")");
         }
         else
         {
            Print("  ✗ RSI Divergence failed (RSI1:", rsi1, " RSI2:", rsi2, ")");
         }
      }
   }

   // MACD Weakness Check
   if (UseMACDWeakness)
   {
      checks_total++;
      double macd_buffer[];
      ArraySetAsSeries(macd_buffer, true);

      if (CopyBuffer(HandleMACD, 0, 0, LookbackBars, macd_buffer) > 0)
      {
         double macd1 = macd_buffer[peak1_idx];
         double macd2 = macd_buffer[peak2_idx];

         // For M pattern: MACD at peak2 should be weaker (smaller absolute value)
         if (MathAbs(macd2) < MathAbs(macd1))
         {
            checks_passed++;
            Print("  ✓ MACD Weakness confirmed (MACD1:", macd1, " MACD2:", macd2, ")");
         }
         else
         {
            Print("  ✗ MACD Weakness failed (MACD1:", macd1, " MACD2:", macd2, ")");
         }
      }
   }

   // Rejection Candle Check (optional)
   if (UseRejectionCandle)
   {
      checks_total++;
      if (CheckRejectionCandle(peak2_idx, true))
      {
         checks_passed++;
         Print("  ✓ Rejection candle confirmed at peak2");
      }
      else
      {
         Print("  ✗ No rejection candle at peak2");
      }
   }

   // Need at least 50% of checks to pass
   if (checks_total == 0)
      return true; // No checks enabled

   double pass_rate = (double)checks_passed / (double)checks_total;
   return (pass_rate >= 0.5);
}

//+------------------------------------------------------------------+
//| Check Momentum Confirmation for W Pattern                        |
//+------------------------------------------------------------------+
bool CheckMomentumConfirmation_W(int trough1_idx, int trough2_idx)
{
   int checks_passed = 0;
   int checks_total = 0;

   // RSI Divergence Check
   if (UseRSIDivergence)
   {
      checks_total++;
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);

      if (CopyBuffer(HandleRSI, 0, 0, LookbackBars, rsi_buffer) > 0)
      {
         double rsi1 = rsi_buffer[trough1_idx];
         double rsi2 = rsi_buffer[trough2_idx];

         // For W pattern: RSI at trough2 should be higher than trough1 (Bullish Divergence)
         if (rsi2 > rsi1 + 2.0) // At least 2 points difference
         {
            checks_passed++;
            Print("  ✓ RSI Divergence confirmed (RSI1:", rsi1, " RSI2:", rsi2, ")");
         }
         else
         {
            Print("  ✗ RSI Divergence failed (RSI1:", rsi1, " RSI2:", rsi2, ")");
         }
      }
   }

   // MACD Weakness Check
   if (UseMACDWeakness)
   {
      checks_total++;
      double macd_buffer[];
      ArraySetAsSeries(macd_buffer, true);

      if (CopyBuffer(HandleMACD, 0, 0, LookbackBars, macd_buffer) > 0)
      {
         double macd1 = macd_buffer[trough1_idx];
         double macd2 = macd_buffer[trough2_idx];

         // For W pattern: MACD at trough2 should be weaker (smaller absolute value)
         if (MathAbs(macd2) < MathAbs(macd1))
         {
            checks_passed++;
            Print("  ✓ MACD Weakness confirmed (MACD1:", macd1, " MACD2:", macd2, ")");
         }
         else
         {
            Print("  ✗ MACD Weakness failed (MACD1:", macd1, " MACD2:", macd2, ")");
         }
      }
   }

   // Rejection Candle Check (optional)
   if (UseRejectionCandle)
   {
      checks_total++;
      if (CheckRejectionCandle(trough2_idx, false))
      {
         checks_passed++;
         Print("  ✓ Rejection candle confirmed at trough2");
      }
      else
      {
         Print("  ✗ No rejection candle at trough2");
      }
   }

   // Need at least 50% of checks to pass
   if (checks_total == 0)
      return true; // No checks enabled

   double pass_rate = (double)checks_passed / (double)checks_total;
   return (pass_rate >= 0.5);
}

//+------------------------------------------------------------------+
//| Check Rejection Candle                                           |
//+------------------------------------------------------------------+
bool CheckRejectionCandle(int index, bool is_top)
{
   double opens[], closes[], highs[], lows[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if (CopyOpen(_Symbol, PERIOD_CURRENT, 0, LookbackBars, opens) <= 0)
      return false;
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, LookbackBars, closes) <= 0)
      return false;
   if (CopyHigh(_Symbol, PERIOD_CURRENT, 0, LookbackBars, highs) <= 0)
      return false;
   if (CopyLow(_Symbol, PERIOD_CURRENT, 0, LookbackBars, lows) <= 0)
      return false;

   double body = MathAbs(closes[index] - opens[index]);

   if (is_top)
   {
      // Check for shooting star or bearish engulfing
      double upper_wick = highs[index] - MathMax(closes[index], opens[index]);
      return (upper_wick > body * 2.0); // Upper wick > 2x body
   }
   else
   {
      // Check for hammer or bullish engulfing
      double lower_wick = MathMin(closes[index], opens[index]) - lows[index];
      return (lower_wick > body * 2.0); // Lower wick > 2x body
   }
}

//+------------------------------------------------------------------+
//| Check Trend Filter for SELL                                      |
//+------------------------------------------------------------------+
bool CheckTrendFilter_SELL()
{
   double ma50_buffer[], ma200_buffer[], close_buffer[];
   ArraySetAsSeries(ma50_buffer, true);
   ArraySetAsSeries(ma200_buffer, true);
   ArraySetAsSeries(close_buffer, true);

   if (CopyBuffer(HandleMA50, 0, 0, 5, ma50_buffer) <= 0)
      return true;
   if (CopyBuffer(HandleMA200, 0, 0, 5, ma200_buffer) <= 0)
      return true;
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, 5, close_buffer) <= 0)
      return true;

   double ma50 = ma50_buffer[0];
   double ma200 = ma200_buffer[0];
   double close = close_buffer[0];

   // For SELL: Price should be below MA50 OR MA50 below MA200 (downtrend)
   bool trend_ok = (close < ma50) || (ma50 < ma200);

   Print("  Trend Check (SELL): Close=", close, " MA50=", ma50, " MA200=", ma200,
         " => ", (trend_ok ? "OK" : "FAILED"));

   return trend_ok;
}

//+------------------------------------------------------------------+
//| Check Trend Filter for BUY                                       |
//+------------------------------------------------------------------+
bool CheckTrendFilter_BUY()
{
   double ma50_buffer[], ma200_buffer[], close_buffer[];
   ArraySetAsSeries(ma50_buffer, true);
   ArraySetAsSeries(ma200_buffer, true);
   ArraySetAsSeries(close_buffer, true);

   if (CopyBuffer(HandleMA50, 0, 0, 5, ma50_buffer) <= 0)
      return true;
   if (CopyBuffer(HandleMA200, 0, 0, 5, ma200_buffer) <= 0)
      return true;
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, 5, close_buffer) <= 0)
      return true;

   double ma50 = ma50_buffer[0];
   double ma200 = ma200_buffer[0];
   double close = close_buffer[0];

   // For BUY: Price should be above MA50 OR MA50 above MA200 (uptrend)
   bool trend_ok = (close > ma50) || (ma50 > ma200);

   Print("  Trend Check (BUY): Close=", close, " MA50=", ma50, " MA200=", ma200,
         " => ", (trend_ok ? "OK" : "FAILED"));

   return trend_ok;
}

//+------------------------------------------------------------------+
//| Check for Retest (Conservative Entry)                            |
//+------------------------------------------------------------------+
bool CheckRetest()
{
   double closes[];
   ArraySetAsSeries(closes, true);
   if (CopyClose(_Symbol, PERIOD_CURRENT, 0, 5, closes) <= 0)
      return false;

   double current_close = closes[0];
   double neckline = currentPattern.neckline_price;
   double tolerance = neckline * 0.002; // 0.2% tolerance

   if (currentPattern.type == 1) // M pattern (SELL)
   {
      // Check if price came back up to test neckline from below
      if (current_close >= neckline - tolerance && current_close <= neckline + tolerance)
      {
         Print("🎯 Retest detected for M pattern at ", current_close, " (Neckline: ", neckline, ")");
         return true;
      }
   }
   else if (currentPattern.type == 2) // W pattern (BUY)
   {
      // Check if price came back down to test neckline from above
      if (current_close >= neckline - tolerance && current_close <= neckline + tolerance)
      {
         Print("🎯 Retest detected for W pattern at ", current_close, " (Neckline: ", neckline, ")");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade()
{
   ExtSymbolInfo.Refresh();

   if (currentPattern.type == 1) // M pattern - SELL
   {
      // Calculate SL
      double sl_level = MathMax(currentPattern.peak1_price, currentPattern.peak2_price);
      double atr_buffer = GetATR() * 0.5;
      double pip_buffer = SL_Buffer_Pips * _Point;
      double buffer = MathMax(atr_buffer, pip_buffer);
      double sl = sl_level + buffer;

      // Calculate TP
      double tp = currentPattern.neckline_price - (currentPattern.pattern_height * RR_Ratio);

      // Calculate position size
      double lot_size = CalculatePositionSize(sl, ExtSymbolInfo.Bid());

      // Validate and normalize
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
      lot_size = MathFloor(lot_size / lot_step) * lot_step;

      Print("📉 Opening SELL position:");
      Print("  Entry: ", ExtSymbolInfo.Bid());
      Print("  SL: ", sl, " (", (sl - ExtSymbolInfo.Bid()) / _Point, " pips)");
      Print("  TP: ", tp, " (", (ExtSymbolInfo.Bid() - tp) / _Point, " pips)");
      Print("  Lot: ", lot_size);
      Print("  RR Ratio: 1:", RR_Ratio);

      if (ExtTrade.Sell(lot_size, _Symbol, ExtSymbolInfo.Bid(), sl, tp,
                        "M-Pattern-" + TimeToString(TimeCurrent())))
      {
         Print("✅ SELL order opened successfully! Ticket: ", ExtTrade.ResultOrder());
      }
      else
      {
         Print("❌ Error opening SELL: ", GetLastError(), " - ", ExtTrade.ResultRetcodeDescription());
      }
   }
   else if (currentPattern.type == 2) // W pattern - BUY
   {
      // Calculate SL
      double sl_level = MathMin(currentPattern.peak1_price, currentPattern.peak2_price);
      double atr_buffer = GetATR() * 0.5;
      double pip_buffer = SL_Buffer_Pips * _Point;
      double buffer = MathMax(atr_buffer, pip_buffer);
      double sl = sl_level - buffer;

      // Calculate TP
      double tp = currentPattern.neckline_price + (currentPattern.pattern_height * RR_Ratio);

      // Calculate position size
      double lot_size = CalculatePositionSize(sl, ExtSymbolInfo.Ask());

      // Validate and normalize
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
      lot_size = MathFloor(lot_size / lot_step) * lot_step;

      Print("📈 Opening BUY position:");
      Print("  Entry: ", ExtSymbolInfo.Ask());
      Print("  SL: ", sl, " (", (ExtSymbolInfo.Ask() - sl) / _Point, " pips)");
      Print("  TP: ", tp, " (", (tp - ExtSymbolInfo.Ask()) / _Point, " pips)");
      Print("  Lot: ", lot_size);
      Print("  RR Ratio: 1:", RR_Ratio);

      if (ExtTrade.Buy(lot_size, _Symbol, ExtSymbolInfo.Ask(), sl, tp,
                       "W-Pattern-" + TimeToString(TimeCurrent())))
      {
         Print("✅ BUY order opened successfully! Ticket: ", ExtTrade.ResultOrder());
      }
      else
      {
         Print("❌ Error opening BUY: ", GetLastError(), " - ", ExtTrade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Position Size based on Risk                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double sl_price, double entry_price)
{
   if (RiskPercent <= 0)
      return Lots; // Use fixed lot

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);

   double sl_distance = MathAbs(entry_price - sl_price);
   double sl_pips = sl_distance / _Point;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double pip_value = tick_value / tick_size * _Point;

   double lot_size = risk_amount / (sl_pips * pip_value);

   return lot_size;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double GetATR()
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if (CopyBuffer(HandleATR, 0, 0, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| Reset Pattern Structure                                          |
//+------------------------------------------------------------------+
void ResetPattern()
{
   currentPattern.found = false;
   currentPattern.type = 0;
   currentPattern.neckline_broken = false;
   currentPattern.waiting_retest = false;
}

//+------------------------------------------------------------------+
//| Update Comment on Chart                                          |
//+------------------------------------------------------------------+
void UpdateComment()
{
   string comment = "=== Devilmod M&W Pattern EA ===\n";
   comment += "Status: " + (isCSVAuthenticated ? "✅ Active" : "❌ Not authenticated") + "\n";
   comment += "Symbol: " + _Symbol + " | TF: " + EnumToString(PERIOD_CURRENT) + "\n";
   comment += "Entry Mode: " + (EntryMode == ENTRY_AGGRESSIVE ? "Aggressive" : "Conservative") + "\n";
   comment += "Risk: " + DoubleToString(RiskPercent, 1) + "% | RR: 1:" + DoubleToString(RR_Ratio, 1) + "\n";
   comment += "Pattern Tolerance: " + DoubleToString(PatternTolerance_Percent, 2) + "%\n";
   comment += "---\n";

   if (currentPattern.found)
   {
      comment += "🎯 Pattern Detected: " + (currentPattern.type == 1 ? "M (Double Top)" : "W (Double Bottom)") + "\n";
      comment += "Neckline: " + DoubleToString(currentPattern.neckline_price, _Digits) + "\n";
      comment += "Pattern Height: " + DoubleToString(currentPattern.pattern_height / _Point, 0) + " pips\n";

      if (currentPattern.waiting_retest)
      {
         comment += "⏳ Waiting for retest...\n";
      }
   }
   else
   {
      comment += "🔍 Scanning for patterns...\n";
   }

   Comment(comment);
}

//+------------------------------------------------------------------+
//| CSV Authentication Functions                                     |
//+------------------------------------------------------------------+
string MD5Hash(string inputStr)
{
   uchar data[], hash[];
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
   return "";
}

bool DownloadCSVFile()
{
   string cookie = NULL, headers;
   char post[], result[];

   ResetLastError();
   int res = WebRequest("GET", GoogleSheetURL, cookie, NULL, 5000, post, 0, result, headers);

   if (res == -1)
   {
      Print("Error downloading CSV: ", GetLastError());
      Print("Make sure URL is in allowed list: Tools -> Options -> Expert Advisors");
      return false;
   }

   string csv_data = CharArrayToString(result);
   return ParseCSVData(csv_data);
}

bool ParseCSVData(string csv_data)
{
   string lines[];
   int line_count = StringSplit(csv_data, '\n', lines);

   ArrayResize(csvRecords, 0);
   totalRecords = 0;

   for (int i = 1; i < line_count; i++)
   {
      string fields[];
      if (StringSplit(lines[i], ',', fields) >= 3)
      {
         int idx = ArraySize(csvRecords);
         ArrayResize(csvRecords, idx + 1);

         csvRecords[idx].username = fields[0];
         csvRecords[idx].passwordHash = fields[1];
         csvRecords[idx].expDate = StringToTime(fields[2]);
         totalRecords++;
      }
   }

   Print("Loaded ", totalRecords, " records from CSV");
   return (totalRecords > 0);
}

bool ValidateCSVUser(string username, string password)
{
   string passwordHash = MD5Hash(password);

   for (int i = 0; i < totalRecords; i++)
   {
      if (csvRecords[i].username == username && csvRecords[i].passwordHash == passwordHash)
      {
         datetime now = TimeCurrent();
         if (now <= csvRecords[i].expDate)
         {
            csvDaysRemaining = (int)((csvRecords[i].expDate - now) / 86400);
            isCSVAuthenticated = true;
            return true;
         }
         else
         {
            Print("Account expired!");
            return false;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
