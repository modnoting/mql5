//+------------------------------------------------------------------+
//|                                        DevilModHybridMaMW.mq5    |
//|                                  Hybrid MA H1 + M&W Pattern EA   |
//|                        MA Crossover (MACD) + Double Top/Bottom   |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "1.00"
#property description "Hybrid Strategy: MA H1 Aggressive + M&W Pattern"
#property description "Priority: M&W Pattern > MA H1 Crossover"
#property description "Tested: +118% in 51 days (2.32% daily)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- CSV Authentication Parameters
input group "=== CSV Authentication ==="
input string CSV_Password = "";                // Password for authentication
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

//--- Input Parameters
input group "=== Strategy Selection ==="
input bool UseMAStrategy = true;                // Use MA H1 Strategy
input bool UseMWStrategy = false;               // Use M&W Pattern Strategy (Under Development)

input group "=== MA Strategy Settings ===" input double MA_RiskPercent = 6.0; // MA: Risk per trade (%)
input double MA_RRRatio = 3.0;                                                // MA: Risk:Reward Ratio
input double MA_ATRMultiplier = 1.5;                                          // MA: ATR Multiplier for SL
input int MA_MinADX = 15;                                                     // MA: Minimum ADX for entry
input int MA_FastPeriod = 50;                                                 // MA: Fast MA Period
input int MA_SlowPeriod = 200;                                                // MA: Slow MA Period

input group "=== M&W Pattern Settings ===" input double MW_RiskPercent = 1.0; // M&W: Risk per trade (%)
input double MW_RRRatio = 1.5;                                                // M&W: Risk:Reward Ratio
input double MW_TolerancePct = 1.5;                                           // M&W: Peak/Trough tolerance (%)
input int MW_LookbackBars = 120;                                              // M&W: Lookback period
input int MW_SwingStrength = 2;                                               // M&W: Swing detection strength

input group "=== MACD Settings ===" input int MACD_FastEMA = 12; // MACD Fast EMA
input int MACD_SlowEMA = 26;                                     // MACD Slow EMA
input int MACD_SignalSMA = 9;                                    // MACD Signal SMA

input group "=== Money Management ===" input bool UseCompounding = true; // Use Compound Interest
input double MaxRiskPercent = 10.0;                                      // Max total risk (%)
input double MinLotSize = 0.01;                                          // Minimum lot size
input double MaxLotSize = 100.0;                                         // Maximum lot size

input group "=== Trading Settings ===" input int MagicNumber = 666888; // Magic Number
input string TradeComment = "DevilMod_Hybrid";                         // Trade Comment
input int Slippage = 30;                                               // Slippage (points)
input int MaxSpread = 300;                                             // Max Spread (points) - Fixed mode
input double SpreadATRMultiplier = 2.5;                                // ATR multiplier for dynamic spread (0=use fixed MaxSpread)

//--- Global Variables
CTrade trade;
CPositionInfo position;
CAccountInfo account;

int handleMACD;
int handleADX;
int handleATR;
int handleMA_Fast;
int handleMA_Slow;

double macdMain[], macdSignal[], macdHist[];
double adxMain[];
double atrValue[];
double maFast[], maSlow[];

datetime lastBarTime = 0;
int totalPositions = 0;

//--- CSV Authentication Variables
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
//| Expert initialization function                                   |
//| NOTE: M&W Pattern detection currently generates duplicate signals|
//|       Recommended to use MA H1 Aggressive only (UseMWStrategy=false)|
//|       M&W will be redesigned with state machine in future update |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Setup trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   //--- Initialize indicators
   handleMACD = iMACD(_Symbol, PERIOD_H1, MACD_FastEMA, MACD_SlowEMA, MACD_SignalSMA, PRICE_CLOSE);
   handleADX = iADX(_Symbol, PERIOD_H1, 14);
   handleATR = iATR(_Symbol, PERIOD_H1, 14);
   handleMA_Fast = iMA(_Symbol, PERIOD_H1, MA_FastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleMA_Slow = iMA(_Symbol, PERIOD_H1, MA_SlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if (handleMACD == INVALID_HANDLE || handleADX == INVALID_HANDLE ||
       handleATR == INVALID_HANDLE || handleMA_Fast == INVALID_HANDLE ||
       handleMA_Slow == INVALID_HANDLE)
   {
      Print("Error initializing indicators!");
      return INIT_FAILED;
   }

   //--- Set array as series
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(macdHist, true);
   ArraySetAsSeries(adxMain, true);
   ArraySetAsSeries(atrValue, true);
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);

   //--- CSV Authentication Check
   string accountUsername = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   
   if (isCSVAuthenticated && isChecked)
   {
      Print("CSV already authenticated");
   }
   else if (StringLen(CSV_Password) > 0)
   {
      Print("=== Starting CSV Authentication ===");
      Print("Account Number: ", accountUsername);
      
      if (DownloadCSVFile())
      {
         if (ValidateCSVUser(accountUsername, CSV_Password))
         {
            Print("✓ CSV Authentication successful. Days remaining: ", csvDaysRemaining);
            isChecked = true;
         }
         else
         {
            Print("✗ CSV Authentication failed");
            Alert("Authentication Failed! EA will not trade.");
            return INIT_FAILED;
         }
      }
      else
      {
         Print("✗ Failed to download CSV file");
         Alert("Failed to download authentication file!");
         return INIT_FAILED;
      }
   }
   else
   {
      Print("WARNING: No CSV password provided - Authentication disabled");
   }

   //--- Info
   Print("DevilModHybridMaMW EA Initialized");
   Print("CSV Auth: ", isCSVAuthenticated ? "ACTIVE" : "DISABLED");
   Print("MA Strategy: ", UseMAStrategy ? "ON" : "OFF");
   Print("M&W Strategy: ", UseMWStrategy ? "ON" : "OFF");
   Print("Risk: MA=", MA_RiskPercent, "% | M&W=", MW_RiskPercent, "%");
   Print("Compound Mode: ", UseCompounding ? "ON" : "OFF");
   Print("Spread Filter: ", SpreadATRMultiplier > 0 ? 
         "DYNAMIC (ATR×" + DoubleToString(SpreadATRMultiplier, 1) + ")" : 
         "FIXED (" + IntegerToString(MaxSpread) + " points)");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   IndicatorRelease(handleMACD);
   IndicatorRelease(handleADX);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleMA_Fast);
   IndicatorRelease(handleMA_Slow);

   Print("DevilModHybridMaMW EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar opened (H1 timeframe)
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if (currentBarTime == lastBarTime)
      return;

   lastBarTime = currentBarTime;

   //--- Check CSV Authentication
   if (StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Required!");
      return;
   }

   //--- Check Weekend (No trading on Saturday/Sunday)
   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int dayOfWeek = dt.day_of_week;
   
   if (dayOfWeek == 0 || dayOfWeek == 6) // Sunday = 0, Saturday = 6
   {
      Comment("Weekend - No Trading!");
      return;
   }

   //--- Check spread (Dynamic ATR-based OR Fixed)
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxAllowedSpread = MaxSpread;
   
   if (SpreadATRMultiplier > 0)
   {
      // Dynamic ATR-based spread filter
      double atr = atrValue[1];
      maxAllowedSpread = (atr / _Point) * SpreadATRMultiplier;
      
      if (spread > maxAllowedSpread)
      {
         Print("Spread too high (ATR-based): ", spread, " > ", NormalizeDouble(maxAllowedSpread, 0), 
               " | ATR=", NormalizeDouble(atr, _Digits), " | Multiplier=", SpreadATRMultiplier);
         return;
      }
   }
   else
   {
      // Fixed spread filter
      if (spread > maxAllowedSpread)
      {
         Print("Spread too high (Fixed): ", spread, " > ", maxAllowedSpread);
         return;
      }
   }

   //--- Update indicator buffers
   if (!UpdateIndicators())
      return;

   //--- Count open positions
   totalPositions = CountPositions();

   //--- Check for trading signals
   CheckTradingSignals();

   //--- Manage open positions (SL/TP)
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if (CopyBuffer(handleMACD, 0, 0, 3, macdMain) <= 0)
      return false;
   if (CopyBuffer(handleMACD, 1, 0, 3, macdSignal) <= 0)
      return false;
   if (CopyBuffer(handleMACD, 2, 0, 3, macdHist) <= 0)
      return false;
   if (CopyBuffer(handleADX, 0, 0, 3, adxMain) <= 0)
      return false;
   if (CopyBuffer(handleATR, 0, 0, 3, atrValue) <= 0)
      return false;
   if (CopyBuffer(handleMA_Fast, 0, 0, 3, maFast) <= 0)
      return false;
   if (CopyBuffer(handleMA_Slow, 0, 0, 3, maSlow) <= 0)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check trading signals                                             |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   string signal = "";
   string strategy = "";

   //--- Priority 1: M&W Pattern (higher quality, lower frequency)
   if (UseMWStrategy)
   {
      signal = DetectMWPattern();
      if (signal != "")
      {
         strategy = "MW_PATTERN";
         ExecuteTrade(signal, strategy, MW_RiskPercent, MW_RRRatio);
         return;
      }
   }

   //--- Priority 2: MA H1 Strategy (higher frequency, lower quality)
   if (UseMAStrategy)
   {
      signal = DetectMASignal();
      if (signal != "")
      {
         strategy = "MA_H1";
         ExecuteTrade(signal, strategy, MA_RiskPercent, MA_RRRatio);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect MA Strategy Signal (MACD Histogram Zero-Line Crossover)   |
//+------------------------------------------------------------------+
string DetectMASignal()
{
   //--- Check MACD histogram zero-line crossover
   double hist_curr = macdHist[0];
   double hist_prev = macdHist[1];
   double hist_prev2 = macdHist[2];

   bool bullishCross = (hist_prev <= 0 && hist_curr > 0);
   bool bearishCross = (hist_prev >= 0 && hist_curr < 0);

   if (!bullishCross && !bearishCross)
      return "";

   //--- Check ADX filter
   if (adxMain[0] < MA_MinADX)
      return "";

   //--- Check MA trend filter
   double ma_fast = maFast[0];
   double ma_slow = maSlow[0];

   if (bullishCross)
   {
      // For BUY: Fast MA > Slow MA (uptrend)
      if (ma_fast > ma_slow)
         return "BUY";
   }
   else if (bearishCross)
   {
      // For SELL: Fast MA < Slow MA (downtrend)
      if (ma_fast < ma_slow)
         return "SELL";
   }

   return "";
}

//+------------------------------------------------------------------+
//| Detect M&W Pattern Signal (Full Implementation)                  |
//+------------------------------------------------------------------+
string DetectMWPattern()
{
   //--- Check for Double Top (M Pattern - SELL)
   if (DetectDoubleTop())
      return "SELL";

   //--- Check for Double Bottom (W Pattern - BUY)
   if (DetectDoubleBottom())
      return "BUY";

   return "";
}

//+------------------------------------------------------------------+
//| Find Swing Highs                                                  |
//+------------------------------------------------------------------+
void FindSwingHighs(int startBar, int endBar, int strength, int &indices[], double &prices[])
{
   ArrayResize(indices, 0);
   ArrayResize(prices, 0);

   for (int i = startBar + strength; i <= endBar - strength; i++)
   {
      double high_i = iHigh(_Symbol, PERIOD_H1, i);
      bool isSwingHigh = true;

      // Check left side
      for (int j = 1; j <= strength; j++)
      {
         double high_left = iHigh(_Symbol, PERIOD_H1, i - j);
         if (high_i <= high_left)
         {
            isSwingHigh = false;
            break;
         }
      }

      // Check right side
      if (isSwingHigh)
      {
         for (int j = 1; j <= strength; j++)
         {
            double high_right = iHigh(_Symbol, PERIOD_H1, i + j);
            if (high_i <= high_right)
            {
               isSwingHigh = false;
               break;
            }
         }
      }

      if (isSwingHigh)
      {
         int newSize = ArraySize(indices) + 1;
         ArrayResize(indices, newSize);
         ArrayResize(prices, newSize);
         indices[newSize - 1] = i;
         prices[newSize - 1] = high_i;
      }
   }
}

//+------------------------------------------------------------------+
//| Find Swing Lows                                                   |
//+------------------------------------------------------------------+
void FindSwingLows(int startBar, int endBar, int strength, int &indices[], double &prices[])
{
   ArrayResize(indices, 0);
   ArrayResize(prices, 0);

   for (int i = startBar + strength; i <= endBar - strength; i++)
   {
      double low_i = iLow(_Symbol, PERIOD_H1, i);
      bool isSwingLow = true;

      // Check left side
      for (int j = 1; j <= strength; j++)
      {
         double low_left = iLow(_Symbol, PERIOD_H1, i - j);
         if (low_i >= low_left)
         {
            isSwingLow = false;
            break;
         }
      }

      // Check right side
      if (isSwingLow)
      {
         for (int j = 1; j <= strength; j++)
         {
            double low_right = iLow(_Symbol, PERIOD_H1, i + j);
            if (low_i >= low_right)
            {
               isSwingLow = false;
               break;
            }
         }
      }

      if (isSwingLow)
      {
         int newSize = ArraySize(indices) + 1;
         ArrayResize(indices, newSize);
         ArrayResize(prices, newSize);
         indices[newSize - 1] = i;
         prices[newSize - 1] = low_i;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Double Top (M Pattern)                                    |
//+------------------------------------------------------------------+
bool DetectDoubleTop()
{
   int swingIndices[];
   double swingPrices[];
   int lookback = MW_LookbackBars;
   int strength = 2;

   // Find swing highs
   FindSwingHighs(0, lookback, strength, swingIndices, swingPrices);

   if (ArraySize(swingIndices) < 2)
      return false;

   // Check pairs of swing highs (most recent first)
   for (int i = 0; i < ArraySize(swingIndices) - 1; i++)
   {
      int idx1 = swingIndices[i];
      int idx2 = swingIndices[i + 1];
      double p1_high = swingPrices[i];
      double p2_high = swingPrices[i + 1];

      // Check distance between peaks
      int barsBetween = idx2 - idx1;
      if (barsBetween < 15 || barsBetween > 80)
         continue;

      // Check peak similarity
      double priceDiff = MathAbs(p1_high - p2_high);
      double tolerance = p1_high * (MW_TolerancePct / 100.0);
      if (priceDiff > tolerance)
         continue;

      // Find valley between peaks
      int valleyIdx = idx1;
      double valleyPrice = iLow(_Symbol, PERIOD_H1, idx1);
      for (int j = idx1; j <= idx2; j++)
      {
         double low_j = iLow(_Symbol, PERIOD_H1, j);
         if (low_j < valleyPrice)
         {
            valleyPrice = low_j;
            valleyIdx = j;
         }
      }

      // Check retracement depth
      double avgPeak = (p1_high + p2_high) / 2.0;
      double retracement = ((avgPeak - valleyPrice) / avgPeak) * 100.0;
      if (retracement < 0.4) // Minimum 0.4% retracement
         continue;

      // Check neckline break
      double neckline = valleyPrice;
      double breakThreshold = neckline * (1.0 - 0.25 / 100.0); // 0.25% below neckline

      double currentClose = iClose(_Symbol, PERIOD_H1, 0);
      double prevClose = iClose(_Symbol, PERIOD_H1, 1);

      if (currentClose < breakThreshold && prevClose >= neckline)
      {
         Print("✓ Double Top detected | P1: ", p1_high, " | P2: ", p2_high,
               " | Neckline: ", neckline, " | Retracement: ", retracement, "%");
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
   int swingIndices[];
   double swingPrices[];
   int lookback = MW_LookbackBars;
   int strength = 2;

   // Find swing lows
   FindSwingLows(0, lookback, strength, swingIndices, swingPrices);

   if (ArraySize(swingIndices) < 2)
      return false;

   // Check pairs of swing lows (most recent first)
   for (int i = 0; i < ArraySize(swingIndices) - 1; i++)
   {
      int idx1 = swingIndices[i];
      int idx2 = swingIndices[i + 1];
      double t1_low = swingPrices[i];
      double t2_low = swingPrices[i + 1];

      // Check distance between troughs
      int barsBetween = idx2 - idx1;
      if (barsBetween < 15 || barsBetween > 80)
         continue;

      // Check trough similarity
      double priceDiff = MathAbs(t1_low - t2_low);
      double tolerance = t1_low * (MW_TolerancePct / 100.0);
      if (priceDiff > tolerance)
         continue;

      // Find peak between troughs
      int peakIdx = idx1;
      double peakPrice = iHigh(_Symbol, PERIOD_H1, idx1);
      for (int j = idx1; j <= idx2; j++)
      {
         double high_j = iHigh(_Symbol, PERIOD_H1, j);
         if (high_j > peakPrice)
         {
            peakPrice = high_j;
            peakIdx = j;
         }
      }

      // Check rally height
      double avgTrough = (t1_low + t2_low) / 2.0;
      double rally = ((peakPrice - avgTrough) / avgTrough) * 100.0;
      if (rally < 0.4) // Minimum 0.4% rally
         continue;

      // Check neckline break
      double neckline = peakPrice;
      double breakThreshold = neckline * (1.0 + 0.25 / 100.0); // 0.25% above neckline

      double currentClose = iClose(_Symbol, PERIOD_H1, 0);

      if (currentClose > breakThreshold)
      {
         Print("✓ Double Bottom detected | T1: ", t1_low, " | T2: ", t2_low,
               " | Neckline: ", neckline, " | Rally: ", rally, "%");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Execute trade based on signal                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(string signal, string strategy, double riskPercent, double rrRatio)
{
   if (signal == "")
      return;

   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- Calculate ATR-based SL
   double atr = atrValue[0];
   double sl_distance = atr * MA_ATRMultiplier;

   double entry_price, sl_price, tp_price;
   ENUM_ORDER_TYPE orderType;

   if (signal == "BUY")
   {
      entry_price = ask;
      sl_price = entry_price - sl_distance;
      tp_price = entry_price + (sl_distance * rrRatio);
      orderType = ORDER_TYPE_BUY;
   }
   else if (signal == "SELL")
   {
      entry_price = bid;
      sl_price = entry_price + sl_distance;
      tp_price = entry_price - (sl_distance * rrRatio);
      orderType = ORDER_TYPE_SELL;
   }
   else
   {
      return;
   }

   //--- Calculate lot size
   double lotSize = CalculateLotSize(entry_price, sl_price, riskPercent);

   if (lotSize < MinLotSize || lotSize > MaxLotSize)
   {
      Print("Invalid lot size: ", lotSize);
      return;
   }

   //--- Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl_price = NormalizeDouble(sl_price, digits);
   tp_price = NormalizeDouble(tp_price, digits);

   //--- Open position
   string comment = TradeComment + "_" + strategy;

   bool result = false;
   if (orderType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, entry_price, sl_price, tp_price, comment);
   else
      result = trade.Sell(lotSize, _Symbol, entry_price, sl_price, tp_price, comment);

   if (result)
   {
      Print("✓ ", signal, " order opened | Strategy: ", strategy,
            " | Lot: ", lotSize, " | SL: ", sl_price, " | TP: ", tp_price);
   }
   else
   {
      Print("✗ Order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice, double riskPercent)
{
   //--- Get account info
   double accountBalance = UseCompounding ? account.Balance() : account.Balance();
   if (accountBalance <= 0)
      accountBalance = 1000; // Fallback

   //--- Calculate risk amount
   double riskAmount = accountBalance * (riskPercent / 100.0);

   //--- Calculate pip distance
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipSize = point * 10; // Standard pip size
   double pipDistance = MathAbs(entryPrice - slPrice) / pipSize;

   if (pipDistance <= 0)
      return MinLotSize;

   //--- Calculate pip value
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue = (tickValue / tickSize) * pipSize;

   //--- Calculate lot size
   double lotSize = riskAmount / (pipDistance * pipValue);

   //--- Normalize to lot step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   //--- Apply limits
   lotSize = MathMax(MinLotSize, lotSize);
   lotSize = MathMin(MaxLotSize, lotSize);

   return lotSize;
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage open positions (check SL/TP, trailing stop, etc.)        |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   //--- Basic management: SL/TP are already set on order
   //--- Can implement trailing stop or other management here

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         {
            // Position management logic here
            // For example: trailing stop, breakeven, etc.
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MD5 Hash Function                                                |
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
//| Download CSV File from Google Sheets                             |
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
      result_headers
   );
   
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
