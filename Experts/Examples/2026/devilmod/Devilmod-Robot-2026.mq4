//+------------------------------------------------------------------+
//|                                      Expert-Robot-Forex-2025.mq4 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod "
//#property link      "https://www.mql5.com"
#property version   "2.01"
#property strict

// CSV Authentication Parameters
input string CSV_Password = "";           // Password for authentication
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

// การใช้งาน:

// ใส่ Password ตรงๆ ใน EA Settings
// EA จะเข้ารหัสเป็น MD5 อัตโนมัติก่อนตรวจสอบ
// ใน Google Sheets ต้องเก็บ password เป็น MD5 hash เท่านั้น
// วิธีสร้าง MD5 hash สำหรับ Google Sheets:

// Password: 123456 → MD5: e10adc3949ba59abbe56e057f20f883e
// ใช้เว็บ: https://www.md5hashgenerator.com/
//
int gi_76 = 1;
bool gi_80 = FALSE;
bool gi_84 = TRUE;
double gd_88 = 1.2;
double g_slippage_96 = 5.0;
extern double Lots = 0.01; 
double gd_112 = 2.0;
extern double g_pips_120 = 3100.0;// TP With Point 
double g_pips_128 = 0.0;
input double gd_136 = 2500.0; // Tialing
extern double gd_144 = 1000.0;//  SL
extern double distance = 1200.0; // Distance From Befor Price
double g_pips_152 = 7.0; // Distance From Befor Price
extern int MaxTrades = 23; 
bool gi_164 = FALSE;
double gd_168 = 20.0;
bool gi_176 = TRUE;
bool gi_180 = FALSE;
double gd_184 = 0.0;
bool gi_192 = FALSE;
extern bool UseManualTrade = FALSE;
extern bool UseHourTrade = TRUE;
extern int StartHour = 15; // Local Time Computer
extern int EndHour = 23; // Local Time Computer
extern int g_magic_208 = 0;
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
string gs_296 = "Devilmod-Robot-2025 V2";
int g_time_304 = 0;
int gi_308;
int gi_312 = 0;
double gd_316;
int g_pos_324 = 0;
int gi_328;
double gd_332 = 0.0;
bool gi_340 = FALSE;
bool gi_344 = FALSE;
bool gi_348 = FALSE;
int gi_352;
bool gi_356 = FALSE;
int g_datetime_360 = 0;
int g_datetime_364 = 0;
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

extern int X_trend = 270; // x position button 
extern int Y_trend = 35; // y position button 
// Indicator

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
   if(CryptEncode(CRYPT_HASH_MD5, data, key, hash))
   {
      string result = "";
      for(int i = 0; i < ArraySize(hash); i++)
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
   
   for(int i = 0; i < len; i++)
   {
      string charStr = StringSubstr(inputStr, i, 1);
      uchar charArray[];
      StringToCharArray(charStr, charArray, 0, WHOLE_ARRAY, CP_UTF8);
      if(ArraySize(charArray) > 0)
      {
         ulong c = (ulong)charArray[0];
         hashValue = ((hashValue << 5) + hashValue) + c;
      }
   }
   
   return StringFormat("%016I64X", hashValue);
}

// Input parameters
 int MACD_Fast = 12;
 int MACD_Slow = 26;
 int MACD_Signal = 9;
 int Sto_K = 14;
 int Sto_D = 3;
 int Sto_Slowing = 3;
 //double Lot_Size = 0.1;
 //int Slippage = 3;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
// Get MACD value
double GetMACD(string symbol, ENUM_TIMEFRAMES timeframe,int mode,int shift)
{
   
    return iMACD(symbol, timeframe, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE, MODE_MAIN, shift);
}

// Get Stochastic value
double GetStochastic(string symbol, ENUM_TIMEFRAMES timeframe, int shift)
{
    return  iStochastic(symbol, timeframe, Sto_K, Sto_D, Sto_Slowing, MODE_SMA, 0,MODE_SIGNAL,shift);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// FiboLevel
//+------------------------------------------------------------------+
string FiboLevel()
  {
   static double fibLow, fibHigh,fibLowM60,fibHighM60;
   
   // Detect swing high and swing low on the chart
   int bars = 60; // Check the last 20 bars for high/low
   string Action = "";
   fibLow = Low[iLowest(NULL, 0, MODE_LOW, bars, 0)];
   fibHigh = High[iHighest(NULL, 0, MODE_HIGH, bars, 0)];
   fibLowM60 = Low[iLowest(NULL, PERIOD_M5, MODE_LOW, bars, 0)];
   fibHighM60 = High[iHighest(NULL, PERIOD_M5, MODE_HIGH, bars, 0)];

   // Calculate Fibonacci levels
   double fib382 = fibHigh - (fibHigh - fibLow) * 0.382;
   double fib618 = fibHigh - (fibHigh - fibLow) * 0.618;
   double fib382M60 = fibHighM60 - (fibHighM60 - fibLowM60) * 0.382;
   double fib618M60 = fibHighM60 - (fibHighM60 - fibLowM60) * 0.618;

   // Print Fibonacci levels to check calculations
   //Print("Fibonacci Levels: Low=", fibLow, " High=", fibHigh, " 38.2%=", fib382, " 61.8%=", fib618);
   
   
   // Example condition to buy at 61.8% retracement
   if (Ask <= fib618 && Ask <= fib618M60 && OrdersTotal() == 0)
     {
      Action = "UP";
     }

   // Example condition to sell at 38.2% retracement
   if (Bid >= fib382 && Bid >= fib382M60 && OrdersTotal() == 0)
     {
      Action = "DN";
     }
   return Action;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |    
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   gd_284 = MarketInfo(Symbol(), MODE_SPREAD) * Point;
   
   // CSV Authentication Check - Use Account Number as Username
   string accountUsername = IntegerToString(AccountNumber());
   if(isCSVAuthenticated && isChecked){ 
      
      return(INIT_SUCCEEDED); 
   }

   if(StringLen(CSV_Password) > 0)
   {
      Print("=== Starting CSV Authentication ===");
      Print("Account Number: ", accountUsername);
      
      if(DownloadCSVFile())
      {
         if(ValidateCSVUser(accountUsername, CSV_Password))
         {
            Alert("Login Successful! Account: ", accountUsername);
            Print("=== Authentication Successful ===");
            Print("Days remaining: ", csvDaysRemaining);
            isCSVAuthenticated = true;
            isChecked = true;
         }
         else
         {
            Alert("Login Failed: Invalid password or account expired");
            Print("=== Authentication Failed ===");
            isChecked = false;
            return(INIT_FAILED);
         }
      }
      else
      {
         Alert("Failed to download CSV data. Check internet connection and URL settings.");
         Print("ERROR: Failed to download CSV file");
         isChecked = false;
         return(INIT_FAILED);
      }
   }
   else
   {
      Print("CSV Authentication disabled (Password not provided)");
      isChecked = false;
      isCSVAuthenticated = true; // Allow EA to run without CSV check
   }
   
   if (IsTesting() == TRUE) Display_Info();
   if (IsTesting() == FALSE) Display_Info();

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   // Check CSV Authentication Status
   if(StringLen(CSV_Password) > 0 && !isCSVAuthenticated)
   {
      Comment("CSV Authentication Failed! EA is disabled.");
      return;
   }
   
   if (IsTesting() == TRUE) Display_Info();
   if (IsTesting() == FALSE) Display_Info();   

   //--------------------------------------
    // Get MACD values for all required timeframes MODE_SIGNAL
    double macdH1 = GetMACD(_Symbol, PERIOD_H1,MODE_MAIN ,0);
    double macdH1_prev = GetMACD(_Symbol, PERIOD_H1, MODE_MAIN ,1);
    double macdH1_prev1 = GetMACD(_Symbol, PERIOD_H1, MODE_MAIN ,2);
    
    double macdH1_Sig = GetMACD(_Symbol, PERIOD_H1,MODE_SIGNAL ,0);
    double macdH1_Sigprev = GetMACD(_Symbol, PERIOD_H1, MODE_SIGNAL ,1);
    double macdH1_Sigprev1 = GetMACD(_Symbol, PERIOD_H1, MODE_SIGNAL ,2);
    
    double macdM30 = GetMACD(_Symbol, PERIOD_M30, MODE_MAIN, 0);
    double macdM30_prev = GetMACD(_Symbol, PERIOD_M30, MODE_MAIN, 1);
    double macdM30_prev1 = GetMACD(_Symbol, PERIOD_M30, MODE_MAIN, 2);
    
    double macdM30_Sig = GetMACD(_Symbol, PERIOD_M30, MODE_SIGNAL, 0);
    double macdM30_Sigprev = GetMACD(_Symbol, PERIOD_M30, MODE_SIGNAL, 1);
    double macdM30_Sigprev1 = GetMACD(_Symbol, PERIOD_M30, MODE_SIGNAL, 2);
    
    double macdM15 = GetMACD(_Symbol, PERIOD_M15, MODE_MAIN, 0);
    double macdM15_prev = GetMACD(_Symbol, PERIOD_M15, MODE_MAIN, 1);
    double macdM15_prev1 = GetMACD(_Symbol, PERIOD_M15, MODE_MAIN, 2);
    
    double macdM15_Sig = GetMACD(_Symbol, PERIOD_M15, MODE_SIGNAL, 0);
    double macdM15_Sigprev = GetMACD(_Symbol, PERIOD_M15, MODE_SIGNAL, 1);
    double macdM15_Sigprev1 = GetMACD(_Symbol, PERIOD_M15, MODE_SIGNAL, 2);
    
    double macdM5 = GetMACD(_Symbol, PERIOD_M5, MODE_MAIN, 0);
    double macdM5_prev = GetMACD(_Symbol, PERIOD_M5, MODE_MAIN, 1);
    double macdM5_prev1 = GetMACD(_Symbol, PERIOD_M5, MODE_MAIN, 2);
    
    double macdM5_Sig = GetMACD(_Symbol, PERIOD_M5, MODE_SIGNAL, 0);
    double macdM5_Sigprev = GetMACD(_Symbol, PERIOD_M5, MODE_SIGNAL, 1);
    double macdM5_Sigprev1 = GetMACD(_Symbol, PERIOD_M5, MODE_SIGNAL, 2);
    
    double macdM1 = GetMACD(_Symbol, PERIOD_M1, MODE_MAIN, 0);
    double macdM1_prev = GetMACD(_Symbol, PERIOD_M1, MODE_MAIN, 1);
    double macdM1_prev1 = GetMACD(_Symbol, PERIOD_M1, MODE_MAIN, 2);
    
    double macdM1_Sig = GetMACD(_Symbol, PERIOD_M1, MODE_SIGNAL, 0);
    double macdM1_Sigprev = GetMACD(_Symbol, PERIOD_M1, MODE_SIGNAL, 1);
    double macdM1_Sigprev1 = GetMACD(_Symbol, PERIOD_M1, MODE_SIGNAL, 2);

    // Get Stochastic values for all required timeframes
    double stoH1 = GetStochastic(_Symbol, PERIOD_H1, 0);
    double stoH1_prev = GetStochastic(_Symbol, PERIOD_H1, 1);
    double rsiH1 = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 0);
    double rsiH1_prev = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 1);
    double stoM30 = GetStochastic(_Symbol, PERIOD_M30, 0);
    double stoM30_prev = GetStochastic(_Symbol, PERIOD_M30, 1);
    double rsiM30 = iRSI(Symbol(), PERIOD_M30, 14, PRICE_CLOSE, 0);
    double rsiM30_prev = iRSI(Symbol(), PERIOD_M30, 14, PRICE_CLOSE, 1);
    double stoM15 = GetStochastic(_Symbol, PERIOD_M15, 0);
    double stoM15_prev = GetStochastic(_Symbol, PERIOD_M15, 1);
    double rsiM15 = iRSI(Symbol(), PERIOD_M15, 14, PRICE_CLOSE, 0);
    double rsiM15_prev = iRSI(Symbol(), PERIOD_M15, 14, PRICE_CLOSE, 1);
    double stoM5 = GetStochastic(_Symbol, PERIOD_M5, 0);
    double stoM5_prev = GetStochastic(_Symbol, PERIOD_M5, 1);
    double rsiM5 = iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, 0);
    double rsiM5_prev = iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, 1);
    double stoM1 = GetStochastic(_Symbol, PERIOD_M1, 0);
    double stoM1_prev = GetStochastic(_Symbol, PERIOD_M1, 1);
    bool is_buy=false,is_sell=false;
    double h1_2 = iClose(Symbol(), PERIOD_H1, 2);
    double h1_1 = iClose(Symbol(), PERIOD_H1, 1);
    double h1_0 = iClose(Symbol(), PERIOD_H1, 0);
    double m30_2 = iClose(Symbol(), PERIOD_M30, 2);
    double m30_1 = iClose(Symbol(), PERIOD_M30, 1);
    double m30_0 = iClose(Symbol(), PERIOD_M30, 0);
    double m15_2 = iClose(Symbol(), PERIOD_M15, 2);
    double m15_1 = iClose(Symbol(), PERIOD_M15, 1);
    double m15_0 = iClose(Symbol(), PERIOD_M15, 0);
    string GetAction = FiboLevel();
    //double g_pips_120 
    //int    vspread = (int)MarketInfo(Symbol(),MODE_SPREAD);
    //g_pips_120 = vspread;
    //Comment(g_pips_120);
    // Buy Condition
    if (OrdersTotal() == 0 &&
        h1_1>h1_2 && h1_0>h1_2 &&
        m30_1>m30_2 && m30_0>m30_2 && 
        m15_1>m15_2 && m15_0>m15_2 &&
        rsiH1>rsiH1_prev &&
        stoH1 > stoH1_prev && stoH1 >30 &&
        stoM5 > 30 &&
        //GetAction == "UP" &&
        macdH1 > macdH1_prev && macdM30 > macdM30_prev &&
        stoH1 > stoH1_prev && stoM30 > stoM30_prev &&
        macdM5 > macdM5_prev && stoM5 > stoM5_prev &&
        macdM1 > macdM1_prev
        //macdM1>0 && 
        //macdM1 > macdM1_Sig && macdM1_prev < macdM1_Sigprev
        )  // MACD cross up in M1
    {
        is_buy=true;
        is_sell=false;
    }

    // Sell Condition
    else if (OrdersTotal() == 0 &&
        h1_1<h1_2 && h1_0<h1_2 &&
        m30_1<m30_2 && m30_0<m30_2 &&
        m15_1<m15_2 && m15_0<m15_2 &&
        rsiH1<rsiH1_prev &&
        stoH1 < stoH1_prev && stoH1 < 70 &&
        stoM5 < 70 &&
        //GetAction == "DN" &&
        macdH1 < macdH1_prev && macdM30 < macdM30_prev &&
        stoH1 < stoH1_prev && stoM30 < stoM30_prev &&
        macdM5 < macdM5_prev && stoM5 < stoM5_prev &&
        macdM1 < macdM1_prev
        //macdM1<0 && 
        //macdM1 < macdM1_Sig && macdM1_prev > macdM1_Sigprev
        )  // MACD cross down in M1
    {
        is_buy=false;
        is_sell=true;
    }
   //--------------------------------------
   double l_ord_lots_0;
   double l_ord_lots_8;
   double l_iclose_16;
   double l_iclose_24;
   
   // Get local computer time
   datetime localTime = TimeLocal();
   
   // Get day of week (0=Sunday, 1=Monday, ... 6=Saturday)
   int dayOfWeek = TimeDayOfWeek(localTime);
   
   // Get hour (0..23)
   int hourOfDay = TimeHour(localTime);
   
   // Print results
   //Print("Local Day of Week = ", dayOfWeek, "  Local Hour = ", hourOfDay);
   //if(DayOfWeek()==0 || DayOfWeek()==6){
   if(dayOfWeek==0 || dayOfWeek==6){
    Comment("Do not work on Holidays. !");
    return;
   }
   if(dayOfWeek==5){
      StartHour=7;
      EndHour=10;
      if (!(hourOfDay >= StartHour && hourOfDay <= EndHour)) {
         if(OrdersTotal() < 1){
         CloseThisSymbolAll();
         Comment("Friday Non-Trading Hours!");
         return ;
         }
      }
   }
   if(dayOfWeek==1){
      StartHour=15;
      EndHour=23;
      if (!(hourOfDay >= StartHour && hourOfDay <= EndHour)) {
         if(OrdersTotal() < 1){
         CloseThisSymbolAll();
         Comment("Monday Non-Trading Hours!");
         return ;
         }
      }
   }
   if (UseHourTrade) {
      if (!(hourOfDay >= StartHour && hourOfDay <= EndHour)) {
         if(OrdersTotal() < 1){
         CloseThisSymbolAll();
         Comment("Non-Trading Hours!");
         return ;
         }
      }
   }
   string ls_32 = "false";
   string ls_40 = "false";
   if (gi_192 == FALSE || (gi_192 && (EndHour > StartHour && (hourOfDay >= StartHour && hourOfDay <= EndHour)) || (StartHour > EndHour && !(hourOfDay >= EndHour && hourOfDay <= StartHour)))) ls_32 = "true";
   if (gi_192 && (EndHour > StartHour && !(hourOfDay >= StartHour && hourOfDay <= EndHour)) || (StartHour > EndHour && (hourOfDay >= EndHour && hourOfDay <= StartHour))) ls_40 = "true";
   if (gi_176) TrailingAlls(gd_136, gd_144, g_price_244);
   if (gi_180) {
      if (TimeCurrent() >= gi_308) {
         if(OrdersTotal() < 1){
         CloseThisSymbolAll();
         Print("Closed All due to TimeOut");
         }
      }
   }
   if (g_time_304 == Time[0]) return ;
   g_time_304 = Time[0];
   double ld_48 = CalculateProfit();
   if (gi_164) {
      if (ld_48 < 0.0 && MathAbs(ld_48) > gd_168 / 100.0 * AccountEquityHigh()) {
         CloseThisSymbolAll();
         Print("Closed All due to Stop Out");
         gi_356 = FALSE;
      }
   }
   gi_328 = CountTrades();
   if (gi_328 == 0) gi_292 = FALSE;
   for (g_pos_324 = OrdersTotal() - 1; g_pos_324 >= 0; g_pos_324--) {
      OrderSelect(g_pos_324, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
         if (OrderType() == OP_BUY) {
            gi_344 = TRUE;
            gi_348 = FALSE;
            l_ord_lots_0 = OrderLots();
            break;
         }
      }
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
         if (OrderType() == OP_SELL) {
            gi_344 = FALSE;
            gi_348 = TRUE;
            l_ord_lots_8 = OrderLots();
            break;
         }
      }
   }
   if (gi_328 > 0 && gi_328 <= MaxTrades) {
      RefreshRates();
      gd_268 = FindLastBuyPrice();
      gd_276 = FindLastSellPrice();
      if (gi_344 && gd_268 - Ask >= g_pips_152 * Point) gi_340 = TRUE;
      if (gi_348 && Bid - gd_276 >= g_pips_152 * Point) gi_340 = TRUE;
   }
   if (gi_328 < 1) {
      gi_348 = FALSE;
      gi_344 = FALSE;
      gi_340 = TRUE;
      gd_220 = AccountEquity();
   }
   if (gi_340) { // Openorder Next ..
      gd_268 = FindLastBuyPrice();
      gd_276 = FindLastSellPrice();
      if (gi_348) {
         if (gi_80 || ls_40 == "true") {
            fOrderCloseMarket(0, 1);
            gd_316 = NormalizeDouble(gd_88 * l_ord_lots_8, gd_112);
         } else gd_316 = fGetLots(OP_SELL);
         if (gi_84 && ls_32 == "true") {
            gi_312 = gi_328;
            double LastSellPrice = FindLastSellPrice();
            double currentPriceSell = Ask;
            double pointDiffSell = MathAbs(currentPriceSell - LastSellPrice) / Point;
            if (gd_316 > 0.0) {
               if(pointDiffSell<distance){return;}
               RefreshRates();
               gi_352 = OpenPendingOrder(1, gd_316, Bid, g_slippage_96, Ask, 0, 0, gs_296 + "-" + gi_312, g_magic_208, 0, HotPink);
               if (gi_352 < 0) {
                  Print("Error: ", GetLastError());
                  return ;
               }
               gd_276 = FindLastSellPrice();
               gi_340 = FALSE;
               gi_356 = TRUE;
            }
         }
      } else {
         if (gi_344) {
            if (gi_80 || ls_40 == "true") {
               fOrderCloseMarket(1, 0);
               gd_316 = NormalizeDouble(gd_88 * l_ord_lots_0, gd_112);
            } else gd_316 = fGetLots(OP_BUY);
            if (gi_84 && ls_32 == "true") {
               gi_312 = gi_328;
               double LastBuyPrice = FindLastBuyPrice();
               double currentPriceBuy = Bid;
               double pointDiffBuy = MathAbs(currentPriceBuy - LastBuyPrice) / Point;
               if (gd_316 > 0.0) {
                  if(pointDiffBuy<distance){return;}
                  gi_352 = OpenPendingOrder(0, gd_316, Ask, g_slippage_96, Bid, 0, 0, gs_296 + "-" + gi_312, g_magic_208, 0, Lime);
                  if (gi_352 < 0) {
                     Print("Error: ", GetLastError());
                     return ;
                  }
                  gd_268 = FindLastBuyPrice();
                  gi_340 = FALSE;
                  gi_356 = TRUE;
               }
            }
         }
      }
   }
   if (gi_340 && gi_328 < 1) {
   //---------------------------------------------------------------------------------------------------
   /*H1,M30
    sto up and macd up
   M5 sto up and macd up
   M1 macd cross up*/
   
   //Loss 21/08/2025
   //----- Open Buy ------------
   
   //----- End Buy -------------
   //---------------------------------------------------------------------------------------------------
      l_iclose_16 = iClose(Symbol(), 0, 2);
      l_iclose_24 = iClose(Symbol(), 0, 1);
      g_bid_252 = Bid;
      g_ask_260 = Ask;
      if (!gi_348 && !gi_344 && ls_32 == "true") {
         gi_312 = gi_328;
         // Fist Order 
         if(UseManualTrade){ return;}
         //if (l_iclose_16 > l_iclose_24) {
         if(OrdersTotal() <= 0 && is_sell){
            gd_316 = fGetLots(OP_SELL);
            if (gd_316 > 0.0) {
               gi_352 = OpenPendingOrder(1, gd_316, g_bid_252, g_slippage_96, g_bid_252, 0, 0, gs_296 + "-" + gi_312, g_magic_208, 0, HotPink);
               if (gi_352 < 0) {
                  Print(gd_316, "Error: ", GetLastError());
                  return ;
               }
               gd_268 = FindLastBuyPrice();
               gi_356 = TRUE;
            }
         //} else {
         } else if (OrdersTotal() <= 0 && is_buy){
            gd_316 = fGetLots(OP_BUY);
            if (gd_316 > 0.0) {
               gi_352 = OpenPendingOrder(0, gd_316, g_ask_260, g_slippage_96, g_ask_260, 0, 0, gs_296 + "-" + gi_312, g_magic_208, 0, Lime);
               if (gi_352 < 0) {
                  Print(gd_316, "Error: ", GetLastError());
                  return ;
               }
               gd_276 = FindLastSellPrice();
               gi_356 = TRUE;
            }
         }
      }
      if (gi_352 > 0) gi_308 = TimeCurrent() + 60.0 * (60.0 * gd_184);
      gi_340 = FALSE;
   }
   gi_328 = CountTrades();
   g_price_244 = 0;
   double ld_56 = 0;
   for (g_pos_324 = OrdersTotal() - 1; g_pos_324 >= 0; g_pos_324--) {
      OrderSelect(g_pos_324, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
         if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
            g_price_244 += OrderOpenPrice() * OrderLots();
            ld_56 += OrderLots();
         }
      }
   }
   if (gi_328 > 0) g_price_244 = NormalizeDouble(g_price_244 / ld_56, Digits);
   if (gi_356) {
      for (g_pos_324 = OrdersTotal() - 1; g_pos_324 >= 0; g_pos_324--) {
         OrderSelect(g_pos_324, SELECT_BY_POS, MODE_TRADES);
         if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
            if (OrderType() == OP_BUY) {
               g_price_212 = g_price_244 + g_pips_120 * Point;
               gd_unused_228 = g_price_212;
               gd_332 = g_price_244 - g_pips_128 * Point;
               gi_292 = TRUE;
            }
         }
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
            if (OrderType() == OP_SELL) {
               g_price_212 = g_price_244 - g_pips_120 * Point;
               gd_unused_236 = g_price_212;
               gd_332 = g_price_244 + g_pips_128 * Point;
               gi_292 = TRUE;
            }
         }
      }
   }
   if (gi_356) {
      if (gi_292 == TRUE) {
         for (g_pos_324 = OrdersTotal() - 1; g_pos_324 >= 0; g_pos_324--) {
            OrderSelect(g_pos_324, SELECT_BY_POS, MODE_TRADES);
            if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) OrderModify(OrderTicket(), g_price_244, OrderStopLoss(), g_price_212, 0, Yellow);
            gi_356 = FALSE;
         }
      }
   }
   return ;
  }
//+------------------------------------------------------------------+
double ND(double ad_0) {
   return (NormalizeDouble(ad_0, Digits));
}

int fOrderCloseMarket(bool ai_0 = TRUE, bool ai_4 = TRUE) {
   int li_ret_8 = 0;
   for (int l_pos_12 = OrdersTotal() - 1; l_pos_12 >= 0; l_pos_12--) {
      if (OrderSelect(l_pos_12, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
            if (OrderType() == OP_BUY && ai_0) {
               RefreshRates();
               if (!IsTradeContextBusy()) {
                  if (!OrderClose(OrderTicket(), OrderLots(), ND(Bid), 5, CLR_NONE)) {
                     Print("Error close BUY " + OrderTicket());
                     li_ret_8 = -1;
                  }
               } else {
                  if (g_datetime_360 != iTime(NULL, 0, 0)) {
                     g_datetime_360 = iTime(NULL, 0, 0);
                     Print("Need close BUY " + OrderTicket() + ". Trade Context Busy");
                  }
                  return (-2);
               }
            }
            if (OrderType() == OP_SELL && ai_4) {
               RefreshRates();
               if (!IsTradeContextBusy()) {
                  if (!OrderClose(OrderTicket(), OrderLots(), ND(Ask), 5, CLR_NONE)) {
                     Print("Error close SELL " + OrderTicket());
                     li_ret_8 = -1;
                  }
               } else {
                  if (g_datetime_364 != iTime(NULL, 0, 0)) {
                     g_datetime_364 = iTime(NULL, 0, 0);
                     Print("Need close SELL " + OrderTicket() + ". Trade Context Busy");
                  }
                  return (-2);
               }
            }
         }
      }
   }
   return (li_ret_8);
}

double fGetLots(int a_cmd_0) {
   double l_lots_4;
   int l_datetime_12;
   switch (gi_76) {
   case 0:
      l_lots_4 = Lots;
      break;
   case 1:
      l_lots_4 = NormalizeDouble(Lots * MathPow(gd_88, gi_312), gd_112);
      break;
   case 2:
      l_datetime_12 = 0;
      l_lots_4 = Lots;
      for (int l_pos_20 = OrdersHistoryTotal() - 1; l_pos_20 >= 0; l_pos_20--) {
         if (OrderSelect(l_pos_20, SELECT_BY_POS, MODE_HISTORY)) {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
               if (l_datetime_12 < OrderCloseTime()) {
                  l_datetime_12 = OrderCloseTime();
                  if (OrderProfit() < 0.0) l_lots_4 = NormalizeDouble(OrderLots() * gd_88, gd_112);
                  else l_lots_4 = Lots;
               }
            }
         } else return (-3);
      }
   }
   if (AccountFreeMarginCheck(Symbol(), a_cmd_0, l_lots_4) <= 0.0) return (-1);
   if (GetLastError() == 134/* NOT_ENOUGH_MONEY */) return (-2);
   return (l_lots_4);
}

int CountTrades() {
   int l_count_0 = 0;
   for (int l_pos_4 = OrdersTotal() - 1; l_pos_4 >= 0; l_pos_4--) {
      OrderSelect(l_pos_4, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208)
         if (OrderType() == OP_SELL || OrderType() == OP_BUY) l_count_0++;
   }
   return (l_count_0);
}

void CloseThisSymbolAll() {
   for (int l_pos_0 = OrdersTotal() - 1; l_pos_0 >= 0; l_pos_0--) {
      OrderSelect(l_pos_0, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() == Symbol()) {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208) {
            if (OrderType() == OP_BUY) OrderClose(OrderTicket(), OrderLots(), Bid, g_slippage_96, Blue);
            if (OrderType() == OP_SELL) OrderClose(OrderTicket(), OrderLots(), Ask, g_slippage_96, Red);
         }
         Sleep(1000);
      }
   }
}

void CloseSymbolAll() {
   for (int l_pos_0 = OrdersTotal() - 1; l_pos_0 >= 0; l_pos_0--) {
      OrderSelect(l_pos_0, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() == Symbol()) {
         if (OrderSymbol() == Symbol()) {
            if (OrderType() == OP_BUY) OrderClose(OrderTicket(), OrderLots(), Bid, g_slippage_96, clrBlue);
            if (OrderType() == OP_SELL) OrderClose(OrderTicket(), OrderLots(), Ask, g_slippage_96, clrYellow);
         }
         //Sleep(1000);
      }
   }
}

int OpenPendingOrder(int ai_0, double a_lots_4, double a_price_12, int a_slippage_20, double ad_24, int ai_unused_32, int ai_36, string a_comment_40, int a_magic_48, int a_datetime_52, color a_color_56) {
   int l_ticket_60 = 0;
   int l_error_64 = 0;
   int l_count_68 = 0;
   int li_72 = 100;
   switch (ai_0) {
   case 2:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         l_ticket_60 = OrderSend(Symbol(), OP_BUYLIMIT, a_lots_4, a_price_12, a_slippage_20, StopLong(ad_24, g_pips_128), TakeLong(a_price_12, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(1000);
      }
      break;
   case 4:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         l_ticket_60 = OrderSend(Symbol(), OP_BUYSTOP, a_lots_4, a_price_12, a_slippage_20, StopLong(ad_24, g_pips_128), TakeLong(a_price_12, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(5000);
      }
      break;
   case 0:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         RefreshRates();
         l_ticket_60 = OrderSend(Symbol(), OP_BUY, a_lots_4, Ask, a_slippage_20, StopLong(Bid, g_pips_128), TakeLong(Ask, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(5000);
      }
      break;
   case 3:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         l_ticket_60 = OrderSend(Symbol(), OP_SELLLIMIT, a_lots_4, a_price_12, a_slippage_20, StopShort(ad_24, g_pips_128), TakeShort(a_price_12, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(5000);
      }
      break;
   case 5:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         l_ticket_60 = OrderSend(Symbol(), OP_SELLSTOP, a_lots_4, a_price_12, a_slippage_20, StopShort(ad_24, g_pips_128), TakeShort(a_price_12, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(5000);
      }
      break;
   case 1:
      for (l_count_68 = 0; l_count_68 < li_72; l_count_68++) {
         l_ticket_60 = OrderSend(Symbol(), OP_SELL, a_lots_4, Bid, a_slippage_20, StopShort(Ask, g_pips_128), TakeShort(Bid, ai_36), a_comment_40, a_magic_48, a_datetime_52, a_color_56);
         l_error_64 = GetLastError();
         if (l_error_64 == 0/* NO_ERROR */) break;
         if (!((l_error_64 == 4/* SERVER_BUSY */ || l_error_64 == 137/* BROKER_BUSY */ || l_error_64 == 146/* TRADE_CONTEXT_BUSY */ || l_error_64 == 136/* OFF_QUOTES */))) break;
         Sleep(5000);
      }
   }
   return (l_ticket_60);
}

double StopLong(double ad_0, int ai_8) {
   if (ai_8 == 0) return (0);
   return (ad_0 - ai_8 * Point);
}

double StopShort(double ad_0, int ai_8) {
   if (ai_8 == 0) return (0);
   return (ad_0 + ai_8 * Point);
}

double TakeLong(double ad_0, int ai_8) {
   if (ai_8 == 0) return (0);
   return (ad_0 + ai_8 * Point);
}

double TakeShort(double ad_0, int ai_8) {
   if (ai_8 == 0) return (0);
   return (ad_0 - ai_8 * Point);
}

double CalculateProfit() {
   double ld_ret_0 = 0;
   for (g_pos_324 = OrdersTotal() - 1; g_pos_324 >= 0; g_pos_324--) {
      OrderSelect(g_pos_324, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208)
         if (OrderType() == OP_BUY || OrderType() == OP_SELL) ld_ret_0 += OrderProfit();
   }
   return (ld_ret_0);
}

void TrailingAlls(int ai_0, int ai_4, double a_price_8) {
   int li_16;
   double l_ord_stoploss_20;
   double l_price_28;
   if (ai_4 != 0) {
      for (int l_pos_36 = OrdersTotal() - 1; l_pos_36 >= 0; l_pos_36--) {
         if (OrderSelect(l_pos_36, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
            if (OrderSymbol() == Symbol() || OrderMagicNumber() == g_magic_208) {
               if (OrderType() == OP_BUY) {
                  li_16 = NormalizeDouble((Bid - a_price_8) / Point, 0);
                  if (li_16 < ai_0) continue;
                  l_ord_stoploss_20 = OrderStopLoss();
                  l_price_28 = Bid - ai_4 * Point;
                  if (l_ord_stoploss_20 == 0.0 || (l_ord_stoploss_20 != 0.0 && l_price_28 > l_ord_stoploss_20)) OrderModify(OrderTicket(), a_price_8, l_price_28, OrderTakeProfit(), 5, Aqua);
               }
               if (OrderType() == OP_SELL) {
                  li_16 = NormalizeDouble((a_price_8 - Ask) / Point, 0);
                  if (li_16 < ai_0) continue;
                  l_ord_stoploss_20 = OrderStopLoss();
                  l_price_28 = Ask + ai_4 * Point;
                  if (l_ord_stoploss_20 == 0.0 || (l_ord_stoploss_20 != 0.0 && l_price_28 < l_ord_stoploss_20)) OrderModify(OrderTicket(), a_price_8, l_price_28, OrderTakeProfit(), 5, Red);
               }
            }
            Sleep(1000);
         }
      }
   }
}

double AccountEquityHigh() {
   if (CountTrades() == 0) gd_368 = AccountEquity();
   if (gd_368 < gd_376) gd_368 = gd_376;
   else gd_368 = AccountEquity();
   gd_376 = AccountEquity();
   return (gd_368);
}

double FindLastBuyPrice() {
   double l_ord_open_price_0;
   int l_ticket_8;
   double ld_unused_12 = 0;
   int l_ticket_20 = 0;
   for (int l_pos_24 = OrdersTotal() - 1; l_pos_24 >= 0; l_pos_24--) {
      OrderSelect(l_pos_24, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208 && OrderType() == OP_BUY) {
         l_ticket_8 = OrderTicket();
         if (l_ticket_8 > l_ticket_20) {
            l_ord_open_price_0 = OrderOpenPrice();
            ld_unused_12 = l_ord_open_price_0;
            l_ticket_20 = l_ticket_8;
         }
      }
   }
   return (l_ord_open_price_0);
}

double FindLastSellPrice() {
   double l_ord_open_price_0;
   int l_ticket_8;
   double ld_unused_12 = 0;
   int l_ticket_20 = 0;
   for (int l_pos_24 = OrdersTotal() - 1; l_pos_24 >= 0; l_pos_24--) {
      OrderSelect(l_pos_24, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_magic_208 && OrderType() == OP_SELL) {
         l_ticket_8 = OrderTicket();
         if (l_ticket_8 > l_ticket_20) {
            l_ord_open_price_0 = OrderOpenPrice();
            ld_unused_12 = l_ord_open_price_0;
            l_ticket_20 = l_ticket_8;
         }
      }
   }
   return (l_ord_open_price_0);
}
double GetLastLotSize()
{
    double lastLotSize = 0;
    
    for (int i = OrdersTotal() - 1; i >= 0; i--) // Loop through all orders
    {
        if (OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic_208) continue;
        if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) // Select order from history
        {
            lastLotSize = OrderLots(); // Get lot size
            break; // Exit loop after finding the last order
        }
    }
    
    return lastLotSize;
}
//-------------------------------------------------------------------+
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
      result_headers
   );
   
   if(res == -1)
   {
      int error = GetLastError();
      Print("ERROR: WebRequest failed. Error code: ", error);
      
      if(error == 4060)
      {
         Print("ERROR: URL not allowed. Please add URL to Tools -> Options -> Expert Advisors -> Allow WebRequest");
         Print("Add this URL: https://docs.google.com");
         Alert("Please add https://docs.google.com to allowed URLs in MT4 settings!");
      }
      
      return false;
   }
   
   if(res == 200)
   {
      string content = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      bool success = ParseCSVFromMemory(content);
      
      content = "";
      ArrayResize(result, 0);
      
      if(success)
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
   
   if(lineCount < 2)
   {
      Print("ERROR: CSV content is empty or invalid");
      return false;
   }
   
   Print("CSV Header: ", lines[0]);
   
   for(int i = 1; i < lineCount; i++)
   {
      string line = lines[i];
      StringTrimRight(line);
      StringTrimLeft(line);
      
      if(StringLen(line) > 0)
      {
         string fields[];
         int count = StringSplit(line, ',', fields);
         
         if(count >= 3)
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
   if(StringLen(inputUsername) == 0 || StringLen(inputPassword) == 0)
   {
      Print("ERROR: Username or Password is empty");
      return false;
   }
   
   // Always use MD5 hash
   string inputPasswordHash = MD5Hash(inputPassword);
   Print("Using MD5 hash: ", StringSubstr(inputPasswordHash, 0, 8), "...");
   
   for(int i = 0; i < totalRecords; i++)
   {
      if(csvRecords[i].username == inputUsername && 
         csvRecords[i].passwordHash == inputPasswordHash)
      {
         Print("User found: ", inputUsername);
         
         datetime currentTime = TimeCurrent();
         datetime expireDate = csvRecords[i].expDate;
         
         Print("Current Time: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
         Print("Expire Date: ", TimeToString(expireDate, TIME_DATE|TIME_MINUTES));
         
         if(currentTime > expireDate)
         {
            Print("ERROR: Account Expired on: ", TimeToString(expireDate, TIME_DATE));
            Alert("Account Expired! Expired on: ", TimeToString(expireDate, TIME_DATE));
            csvDaysRemaining = 0;
            return false;
         }
         else
         {
            csvDaysRemaining = (int)((expireDate - currentTime) / 86400);
            Print("Account Active - ", csvDaysRemaining, " days remaining");
            
            if(csvDaysRemaining <= 7)
            {
               Alert("Warning: Account expires in ", csvDaysRemaining, " days!");
            }
            
            return true;
         }
      }
   }
   
   Print("ERROR: Username or Password is incorrect");
   Alert("Login Failed: Invalid Username or Password");
   return false;
}

//-------------------------------------------------------------------+
void Display_Info() {
   string BrokerTime = TimeToStr(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   string LocalComputerTime = TimeToStr(TimeLocal(),TIME_DATE|TIME_SECONDS);
   
   string csvStatus = "";
   if(StringLen(CSV_Password) > 0)
   {
      if(isCSVAuthenticated)
      {
         csvStatus = "CSV Auth: Account " + IntegerToString(AccountNumber()) + " (" + IntegerToString(csvDaysRemaining) + " days left)";
      }
      else
      {
         csvStatus = "CSV Auth: FAILED";
      }
   }

   Comment( 
      "Forex Account Server:", AccountServer(), 
      "\n", csvStatus != "" ? csvStatus + "\n" : "",
      "Lots:  ", NormalizeDouble(GetLastLotSize(),2)," OrderTotal=",CountTrades(),
      "\n", "Symbol: ", Symbol(),"    Account: ",NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE),2),
      "     MARGIN:",NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN),2),
      "     FREEMARGIN:",NormalizeDouble(AccountInfoDouble(ACCOUNT_FREEMARGIN),2),
      "\n", "SellPrice:  ",FindLastSellPrice()," BuyPrice: ",FindLastBuyPrice(),
      "\n", "BrokerTime: ", BrokerTime , 
      "\n", "LocalComputerTime: ", LocalComputerTime , 
   "\n");
   
}