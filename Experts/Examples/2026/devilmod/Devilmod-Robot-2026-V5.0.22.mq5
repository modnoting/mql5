//+------------------------------------------------------------------+
//|                          Devilmod-Robot-2026-V5.0.22.mq5         |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DevilMod"
#property version "5.022"
#property strict
#property description "Devilmod Robot Martingale EA V5.0.22 - Fixed Version"
#property description ""
#property description "=== ระบบการทำงาน ==="
#property description "1. Entry Signal: 3-Layer (Trend + Momentum + Price Action)"
#property description "2. Entry Signal: OB/OS (Overbought/Oversold RSI+Stoch MTF)"
#property description "3. Martingale Open: เปิด Order ใหม่เมื่อราคาห่าง >= MartingaleDistancePoints + Signal"
#property description "4. Runaway Close: ปิด Order ที่亏损มากที่สุดเมื่อครบทั้ง MaxTrades + ราคาไหลเกิน TriggerDistance"
#property description "5. Trailing Stop: เลื่อน SL สำหรับทุก Order เมื่อกำไร >= TrailingPoints"
#property description "6. UpdateMartingaleTP: ตั้ง TP เท่ากันทุก Order จาก Weighted Average"
#property description "7. Margin Critical: ปิดทั้งหมดเมื่อ Margin >= 90"
#property description "8. Hedge Prevention: ป้องกัน BUY+SELL พร้อมกัน"
#property description "9. First Order SL: ตั้ง SL สำหรับคำสั่งแรก"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- CSV Authentication
input string CSV_Password = "123456";
string GoogleSheetURL = "https://docs.google.com/spreadsheets/d/1RPm23hggq0cyL_2i5D58LvNhu-KRhYP3veurdplQNoU/export?format=csv&gid=0";

//--- Trading Parameters (FIX #4: ปรับค่าสำหรับ XAUUSD)
input double Lots = 0.02;      // Lots Fixed: ลดจาก 0.03 เป็น 0.02
input int MaxTrades = 8;       // MaxTrades Fixed: ลดจาก 15 เป็น 8
input double Multiplier = 1.1; // Multiplier Fixed: ลดจาก 1.15 เป็น 1.1
input int MaxLotDecimals = 2;
input double MaxLotPerOrder = 0.20; // MaxLotPerOrder Fixed: ลดจาก 0.50 เป็น 0.20
input double MaxTotalLot = 1.00;    // MaxTotalLot Fixed: ลดจาก 3.00 เป็น 1.00

//--- TP/SL (Points)
input double TakeProfitPoints = 3000.0; // TakeProfitPoints Fixed: เพิ่มจาก 2000 เป็น 3000
input double StopLossPoints = 2500.0;   // StopLossPoints Fixed: เพิ่มจาก 1500 เป็น 2500
input double TrailingPoints = 1000.0;   // TrailingPoints Fixed: เพิ่มจาก 600 เป็น 1000
input double DistancePoints = 2000.0;   // DistancePoints Fixed: เพิ่มจาก 1000 เป็น 2000

//--- Margin Risk Management (V4.0)
input bool UseMarginRiskManagement = true;
input double MarginRiskThreshold = 75.0;
input double MarginCriticalThreshold = 90.0;
input double MinTrailingProfitToOffset = 10.0;

//--- Price Runaway Detection (V4.0)
input double TriggerDistance = 1500.0; // TriggerDistance Fixed: เพิ่มจาก 500 เป็น 1500
input double RiskTriggerMultiplier = 1.5;

//--- Martingale Distance (V4.15)
input double MartingaleDistancePoints = 2500.0; // MartingaleDistancePoints Fixed: เพิ่มจาก 1000 เป็น 2500

//--- Runaway Recovery (V4.01)
input bool UseRunawayRecovery = true;
input double RecoveryDistancePoints = 2000.0; // RecoveryDistancePoints Fixed: เพิ่มจาก 800 เป็น 2000

//--- Entry Signal (V4.0 - 3 Layer System)
input bool UseEasyMode = true;
input bool UseADXFilter = false;
input double ADX_Threshold = 20.0;
input int ADX_Period = 14;
input int RSI_Period = 14;
input int RequiredLayers = 1;

//--- Time Filter (FIX #7: ปรับเวลาเทรด)
input bool UseHourTrade = true;
input int StartHour = 0; // StartHour Fixed: เปลี่ยนจาก 8 เป็น 0
input int EndHour = 23;
input int MagicNumber = 0;
input int MaxPositionHours = 24; // MaxPositionHours Fixed: ลดจาก 48 เป็น 24

//--- Hedge Prevention (FIX #5)
input bool PreventHedge = true; // PreventHedge Fixed: เพิ่ม input ใหม่

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

//--- Global Variables
string EA_Version = "V5.0.22";
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
   if (CopyBuffer(handle, buffer, shift, 1, value) < 1)
      return 0;
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
//| Trend Layer: MACD M1 Cross + MACD M15 Momentum + Stoch H1/H4   |
//+------------------------------------------------------------------+
int CheckTrendLayer()
{
   double macdM1 = GetMACD(HandleMACD_M1, 1);
   double macdM1_prev = GetMACD(HandleMACD_M1, 2);
   double signalM1 = GetMACDSignal(HandleMACD_M1, 1);
   double signalM1_prev = GetMACDSignal(HandleMACD_M1, 2);

   double stochM1 = GetIndicatorValue(HandleSto_M1, 0, 1);
   double stochM1_prev = GetIndicatorValue(HandleSto_M1, 0, 2);
   // bool macdM1_CrossUp = (macdM1_prev <= signalM1_prev && macdM1 > signalM1);
   bool macdM1_CrossUp = (macdM1 > macdM1_prev);
   // bool macdM1_CrossDown = (macdM1_prev >= signalM1_prev && macdM1 < signalM1);
   bool macdM1_CrossDown = (macdM1 < macdM1_prev);

   double stochM15 = GetIndicatorValue(HandleSto_M15, 0, 1);
   double stochM15_prev = GetIndicatorValue(HandleSto_M1, 0, 2);
   double macdM15 = GetMACD(HandleMACD_M15, 1);
   double macdM15_prev = GetMACD(HandleMACD_M15, 2);

   bool macdM15_Bull = (macdM15 > macdM15_prev && stochM15 > stochM15_prev);
   bool macdM15_Bear = (macdM15 < macdM15_prev && stochM15 < stochM15_prev);

   double stochH1 = GetIndicatorValue(HandleSto_H1, 0, 1);
   double stochH1_prev = GetIndicatorValue(HandleSto_H1, 0, 2);

   bool stochH1_Bull = (stochH1 > stochH1_prev && stochH1 >= 30 && stochH1 <= 75);
   bool stochH1_Bear = (stochH1 < stochH1_prev && stochH1 < 70 && stochH1 >= 30);

   double stochH4 = GetIndicatorValue(HandleSto_H4, 0, 1);
   double stochH4_prev = GetIndicatorValue(HandleSto_H4, 0, 2);

   bool stochH4_Bull = (stochH4 > stochH4_prev);
   bool stochH4_Bear = (stochH4 < stochH4_prev);

   if (macdM1_CrossUp && macdM15_Bull)
   // if (macdM1_CrossUp )
   {
      Print("TREND BUY: CrossUp M15_Bull=", macdM15_Bull, " H1_Bull=", stochH1_Bull, " H4_Bull=", stochH4_Bull,
            " | M1=", DoubleToString(macdM1, 6), " M1_prev=", DoubleToString(macdM1_prev, 6),
            " M15=", DoubleToString(macdM15, 6),
            " StoH1=", DoubleToString(stochH1, 1), " StoH4=", DoubleToString(stochH4, 1));
      return 1;
   }

   if (macdM1_CrossDown && macdM15_Bear)
   // if (macdM1_CrossDown )
   {
      Print("TREND SELL: CrossDown M15_Bear=", macdM15_Bear, " H1_Bear=", stochH1_Bear, " H4_Bear=", stochH4_Bear,
            " | M1=", DoubleToString(macdM1, 6), " M1_prev=", DoubleToString(macdM1_prev, 6),
            " M15=", DoubleToString(macdM15, 6),
            " StoH1=", DoubleToString(stochH1, 1), " StoH4=", DoubleToString(stochH4, 1));
      return -1;
   }

   Print("TREND NO SIGNAL: CrossUp=", macdM1_CrossUp, " CrossDown=", macdM1_CrossDown,
         " | M1=", DoubleToString(macdM1, 6), " M1_prev=", DoubleToString(macdM1_prev, 6));

   return 0;
}

//+------------------------------------------------------------------+
//| Entry Signal                                                     |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   return CheckTrendLayer();
}

//+------------------------------------------------------------------+
//| Combined Entry Signal                                            |
//+------------------------------------------------------------------+
int CheckCombinedEntrySignal()
{
   return CheckEntrySignal();
}

//+------------------------------------------------------------------+
//| Calculate Margin Usage                                           |
//+------------------------------------------------------------------+
double CalculateMarginUsage()
{
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if (equity <= 0)
      return 100.0;
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
//| Calculate Total Profit (All Orders)                             |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
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

         totalProfit += PositionGetDouble(POSITION_PROFIT);
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
//| FIX #3: Find Most Loss Ticket (for Runaway Recovery)            |
//+------------------------------------------------------------------+
ulong FindMostLossTicket()
{
   ulong worstTicket = 0;
   double maxLoss = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
             PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

         double profit = PositionGetDouble(POSITION_PROFIT);
         if (profit < maxLoss) // 亏损มากที่สุด
         {
            maxLoss = profit;
            worstTicket = ticket;
         }
      }
   }
   return worstTicket;
}

//+------------------------------------------------------------------+
//| Manage Runaway Recovery (FIX #3: ตรวจสอบกำไรก่อนปิด)         |
//+------------------------------------------------------------------+
void ManageRunawayRecovery()
{
   if (!UseRunawayRecovery)
      return;
   if (CountTrades() < MaxTrades)
      return;

   ExtSymbolInfo.RefreshRates();
   double currentBid = ExtSymbolInfo.Bid();
   double currentAsk = ExtSymbolInfo.Ask();

   if (g_isBuy)
   {
      double lastBuyPrice = FindLastBuyPrice();
      if (lastBuyPrice <= 0)
         return;

      double distancePoints = (lastBuyPrice - currentBid) / _Point;
      if (distancePoints < RecoveryDistancePoints)
         return;

      // FIX #3: หาคำสั่งที่亏损มากที่สุดแทนคำสั่งเก่าสุด
      ulong worstTicket = FindMostLossTicket();
      if (worstTicket == 0)
         return;

      if (!PositionSelectByTicket(worstTicket))
         return;

      double worstEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double worstProfit = PositionGetDouble(POSITION_PROFIT);

      // FIX #3: ตรวจสอบว่ากำลัง亏损จริงหรือไม่
      if (worstProfit >= 0)
      {
         Print("RECOVERY SKIPPED: Worst ticket (", DoubleToString(worstEntry, _Digits), ") is profitable: $",
               DoubleToString(worstProfit, 2));
         return;
      }

      if (TimeCurrent() - g_lastRecoveryTime < 300)
         return;

      if (ExtTrade.PositionClose(worstTicket))
      {
         g_lastRecoveryTime = TimeCurrent();
         g_recoveryActive = true;
         Print("RECOVERY: Closed worst loss ticket at ", DoubleToString(worstEntry, _Digits),
               " | Distance: ", DoubleToString(distancePoints, 0), " pts | Profit: ", DoubleToString(worstProfit, 2));
      }
   }
   else if (g_isSell)
   {
      double lastSellPrice = FindLastSellPrice();
      if (lastSellPrice <= 0)
         return;

      double distancePoints = (currentAsk - lastSellPrice) / _Point;
      if (distancePoints < RecoveryDistancePoints)
         return;

      // FIX #3: หาคำสั่งที่亏损มากที่สุด
      ulong worstTicket = FindMostLossTicket();
      if (worstTicket == 0)
         return;

      if (!PositionSelectByTicket(worstTicket))
         return;

      double worstEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double worstProfit = PositionGetDouble(POSITION_PROFIT);

      // FIX #3: ตรวจสอบว่ากำลัง亏损จริงหรือไม่
      if (worstProfit >= 0)
      {
         Print("RECOVERY SKIPPED: Worst ticket (", DoubleToString(worstEntry, _Digits), ") is profitable: $",
               DoubleToString(worstProfit, 2));
         return;
      }

      if (TimeCurrent() - g_lastRecoveryTime < 300)
         return;

      if (ExtTrade.PositionClose(worstTicket))
      {
         g_lastRecoveryTime = TimeCurrent();
         g_recoveryActive = true;
         Print("RECOVERY: Closed worst loss ticket at ", DoubleToString(worstEntry, _Digits),
               " | Distance: ", DoubleToString(distancePoints, 0), " pts | Profit: ", DoubleToString(worstProfit, 2));
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
   if (!UseMarginRiskManagement)
      return;

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
   if (tradeCount == 0)
      return;

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
   // ปิด Order ที่亏损มากที่สุด 1 รายการ + Cooldown 120s
   if (maxedOut && g_priceRunaway)
   {
      int cooldownSeconds = 120;
      if (TimeCurrent() - g_lastRunawayCloseTime > cooldownSeconds)
      {
         Print("RUNAWAY CLOSE - MaxTrades (", tradeCount, "/", MaxTrades,
               ") + Distance (", DoubleToString(TriggerDistance, 0), " pts) - Closing worst loss order");

         // FIX #3: ปิดคำสั่งที่亏损มากที่สุดแทนคำสั่งเก่าสุด
         ulong worstTicket = FindMostLossTicket();
         if (worstTicket > 0)
         {
            if (!PositionSelectByTicket(worstTicket))
               return;
            double profit = PositionGetDouble(POSITION_PROFIT);

            if (profit < 0) // ปิดเฉพาะถ้ากำลัง亏损
            {
               if (ExtTrade.PositionClose(worstTicket))
               {
                  g_lastRunawayCloseTime = TimeCurrent();
                  Print("SUCCESS: Closed worst loss order (Profit: $", DoubleToString(profit, 2),
                        ") - Next close in ", cooldownSeconds, "s");
               }
               else
                  Print("FAILED: Close worst loss order error: ", GetLastError());
            }
            else
            {
               Print("RUNAWAY CLOSE SKIPPED: Worst ticket is profitable ($", DoubleToString(profit, 2), ")");
            }
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

   stopLoss = MathMin(stopLoss, 4000.0);     // Fixed: เพิ่ม cap จาก 2500 เป็น 4000
   takeProfit = MathMin(takeProfit, 8000.0); // Fixed: เพิ่ม cap จาก 5000 เป็น 8000
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

   dynamicDist = MathMax(dynamicDist, 1500.0); // Fixed: เพิ่ม min จาก 800 เป็น 1500
   dynamicDist = MathMin(dynamicDist, 5000.0); // Fixed: เพิ่ม max จาก 3000 เป็น 5000

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

   if (lot < minlot)
      lot = minlot;
   if (lot > maxlot)
      lot = maxlot;
   lot = NormalizeDouble(MathFloor(lot / lotstep) * lotstep, MaxLotDecimals);

   if (lot <= 0)
      return -1;

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
//| Check Position Time Limit (FIX #6: ตรวจสอบกำไรก่อนปิด)     |
//+------------------------------------------------------------------+
void CheckPositionTimeLimit()
{
   if (MaxPositionHours <= 0)
      return;

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
      // FIX #6: ตรวจสอบกำไรก่อนปิด
      double totalProfit = CalculateTotalProfit();

      if (totalProfit > 0)
      {
         // กำลังกำไร → ไม่ปิดทั้งหมด แต่ลด lot แทน
         Print("TIME LIMIT: Position open ", DoubleToString(hoursOpen, 1),
               "h >= ", MaxPositionHours, "h - Still profitable ($", DoubleToString(totalProfit, 2),
               ") - NOT closing");
         // ในอนาคต: ลด lot แทนการปิดทั้งหมด
      }
      else
      {
         // กำลัง亏损 → ปิดทั้งหมด
         Print("TIME LIMIT: Position open ", DoubleToString(hoursOpen, 1),
               "h >= ", MaxPositionHours, "h - Loss ($", DoubleToString(totalProfit, 2),
               ") - Closing all");
         CloseThisSymbolAll();
      }
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
   if (slPoints == 0)
      return 0;
   return price - slPoints * _Point;
}

double StopShort(double price, int slPoints)
{
   if (slPoints == 0)
      return 0;
   return price + slPoints * _Point;
}

double TakeLong(double price, int tpPoints)
{
   if (tpPoints == 0)
      return 0;
   return price + tpPoints * _Point;
}

double TakeShort(double price, int tpPoints)
{
   if (tpPoints == 0)
      return 0;
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
   if (TrailingPoints == 0)
      return;

   ExtSymbolInfo.RefreshRates();
   double bid = ExtSymbolInfo.Bid();
   double ask = ExtSymbolInfo.Ask();
   double trailDist = TrailingPoints * _Point;

   int trailed = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;

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
   if (signal == 1)
      signalText = "BUY";
   else if (signal == -1)
      signalText = "SELL";

   string recoveryStatus = "";
   if (g_recoveryActive)
      recoveryStatus = "\nRecovery: ACTIVE (Last: " + TimeToString(g_lastRecoveryTime, TIME_SECONDS) + ")";

   double totalProfit = CalculateTotalProfit();
   string profitStatus = " | P/L: $" + DoubleToString(totalProfit, 2);
   if (totalProfit > 0)
      profitStatus += " (+)";
   else if (totalProfit < 0)
      profitStatus += " (-)";

   Comment(
       "\n=== Devilmod Robot ", EA_Version, " ===",
       "\n", csvStatus,
       "\nSymbol: ", _Symbol,
       "\nBalance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
       " | Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
       profitStatus,
       "\nMargin: ", marginStatus,
       " | Free: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2),
       "\nOrders: ", CountTrades(), " / ", MaxTrades,
       " | Lot: ", DoubleToString(GetCurrentTotalLot(), 2),
       "\nSignal: ", signalText,
       recoveryStatus,
       "\nBroker: ", BrokerTime,
       " | Local: ", LocalTime,
       "\n========================");
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

   if (lineCount < 2)
      return false;

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

   Display_Info();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- 3-Layer System
   if (HandleMACD_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleMACD_H4);
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
   if (HandleSto_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleSto_H4);
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
   if (HandleRSI_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleRSI_H4);
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
   if (HandleATR_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_H4);
   if (HandleATR_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_H1);
   if (HandleATR_M30 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_M30);
   if (HandleATR_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_M15);
   if (HandleATR_M5 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_M5);
   if (HandleATR_M1 != INVALID_HANDLE)
      IndicatorRelease(HandleATR_M1);
   if (HandleADX_H4 != INVALID_HANDLE)
      IndicatorRelease(HandleADX_H4);
   if (HandleADX_H1 != INVALID_HANDLE)
      IndicatorRelease(HandleADX_H1);
   if (HandleADX_M30 != INVALID_HANDLE)
      IndicatorRelease(HandleADX_M30);
   if (HandleADX_M15 != INVALID_HANDLE)
      IndicatorRelease(HandleADX_M15);
}

//+------------------------------------------------------------------+
//| Expert tick function (FIX #1, #2, #5)                           |
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
      // FIX #3: เรียก ManageRunawayRecovery ทุก tick
      ManageRunawayRecovery();
   }

   datetime localTime = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   int dayOfWeek = dt.day_of_week;
   int hourOfDay = dt.hour;

   if (dayOfWeek == 0 || dayOfWeek == 6)
      return;
   if (dayOfWeek == 1 && !(hourOfDay >= 8 && hourOfDay <= 23) && PositionsTotal() < 1)
      return;
   if (dayOfWeek == 5 && !(hourOfDay >= 1 && hourOfDay <= 3) && PositionsTotal() < 1)
      return;

   if (UseHourTrade && !(hourOfDay >= StartHour && hourOfDay <= EndHour) && PositionsTotal() < 1)
      return;

   datetime currentTime[];
   ArraySetAsSeries(currentTime, true);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime);

   if (g_timeLastBar == currentTime[0])
      return;
   g_timeLastBar = currentTime[0];

   // V4.13: เรียก TrailingStop และ UpdateMartingaleTP ทุก Bar
   TrailingStopFirstOrder();
   if (CountTrades() > 0)
      UpdateMartingaleTP();

   g_tradeCount = CountTrades();

   // FIX #5: ตรวจสอบทั้ง BUY และ SELL (ไม่ break ทันที)
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
            g_isBuy = true;
         else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            g_isSell = true;
      }
   }

   Print("DEBUG POSITIONS: tradeCount=", g_tradeCount, " isBuy=", g_isBuy, " isSell=", g_isSell);

   // FIX #5: ป้องกัน Hedge - ปิดฝั่งตรงข้ามถ้ามีทั้ง BUY และ SELL
   if (PreventHedge && g_isBuy && g_isSell)
   {
      Print("WARNING: Both BUY and SELL exist - Closing opposite side");
      // เลือกปิด SELL ถ้ามี BUY signal หรือปิด BUY ถ้ามี SELL signal
      int currentSignal = CheckCombinedEntrySignal();
      if (currentSignal == 1)
      {
         // มี BUY signal → ปิด SELL
         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket))
            {
               if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
                   PositionGetInteger(POSITION_MAGIC) != MagicNumber)
                  continue;
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               {
                  ExtTrade.PositionClose(ticket);
                  Print("HEDGE PREVENTION: Closed SELL ticket ", ticket);
                  Sleep(500);
               }
            }
         }
      }
      else if (currentSignal == -1)
      {
         // มี SELL signal → ปิด BUY
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
                  ExtTrade.PositionClose(ticket);
                  Print("HEDGE PREVENTION: Closed BUY ticket ", ticket);
                  Sleep(500);
               }
            }
         }
      }
      else
      {
         // ไม่มี signal → ปิดทั้งคู่
         Print("HEDGE PREVENTION: No signal - Closing all");
         CloseThisSymbolAll();
      }

      // อัพเดทสถานะหลังปิด
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
               g_isBuy = true;
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               g_isSell = true;
         }
      }
      return;
   }

   // V5.0: Combined Entry Signal (3-Layer + OB/OS)
   int signal = CheckCombinedEntrySignal();

   Print("DEBUG: signal=", signal, " tradeCount=", g_tradeCount,
         " isBuy=", g_isBuy, " isSell=", g_isSell,
         " MaxTrades=", MaxTrades,
         " marginFree=", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

   if (g_tradeCount < MaxTrades)
   {
      ExtSymbolInfo.RefreshRates();

      // FIX #1 & #2: First order - ต้องมี signal + ตั้ง SL/TP
      if (g_tradeCount == 0)
      {
         double dynamicTP = 0, dynamicSL = 0;
         CalculateDynamicTPSL(dynamicTP, dynamicSL);

         if (signal == 1)
         {
            double lot = fGetLots(ORDER_TYPE_BUY);
            Print("DEBUG BUY: lot=", DoubleToString(lot, 2),
                  " ask=", DoubleToString(ExtSymbolInfo.Ask(), _Digits),
                  " sl=", DoubleToString(StopLong(ExtSymbolInfo.Ask(), (int)dynamicSL), _Digits),
                  " tp=", DoubleToString(TakeLong(ExtSymbolInfo.Ask(), (int)dynamicTP), _Digits));
            if (lot > 0)
            {
               double entryPrice = ExtSymbolInfo.Ask();
               double sl = StopLong(entryPrice, (int)dynamicSL);
               double tp = TakeLong(entryPrice, (int)dynamicTP);

               if (ExtTrade.Buy(lot, _Symbol, entryPrice, sl, tp, "V5.0-BUY"))
               {
                  Print("BUY OPENED OK - Lot:", lot,
                        " SL:", DoubleToString(sl, _Digits),
                        " TP:", DoubleToString(tp, _Digits));
                  UpdateMartingaleTP();
               }
               else
               {
                  Print("BUY FAILED! Error=", GetLastError(),
                        " retcode=", ExtTrade.ResultRetcode(),
                        " comment=", ExtTrade.ResultRetcodeDescription());
               }
            }
            else
            {
               Print("DEBUG BUY SKIPPED: lot <= 0 (lot=", DoubleToString(lot, 2), ")");
            }
         }
         else if (signal == -1)
         {
            double lot = fGetLots(ORDER_TYPE_SELL);
            Print("DEBUG SELL: lot=", DoubleToString(lot, 2),
                  " bid=", DoubleToString(ExtSymbolInfo.Bid(), _Digits),
                  " sl=", DoubleToString(StopShort(ExtSymbolInfo.Bid(), (int)dynamicSL), _Digits),
                  " tp=", DoubleToString(TakeShort(ExtSymbolInfo.Bid(), (int)dynamicTP), _Digits));
            if (lot > 0)
            {
               double entryPrice = ExtSymbolInfo.Bid();
               double sl = StopShort(entryPrice, (int)dynamicSL);
               double tp = TakeShort(entryPrice, (int)dynamicTP);

               if (ExtTrade.Sell(lot, _Symbol, entryPrice, sl, tp, "V5.0-SELL"))
               {
                  Print("SELL OPENED OK - Lot:", lot,
                        " SL:", DoubleToString(sl, _Digits),
                        " TP:", DoubleToString(tp, _Digits));
                  UpdateMartingaleTP();
               }
               else
               {
                  Print("SELL FAILED! Error=", GetLastError(),
                        " retcode=", ExtTrade.ResultRetcode(),
                        " comment=", ExtTrade.ResultRetcodeDescription());
               }
            }
            else
            {
               Print("DEBUG SELL SKIPPED: lot <= 0 (lot=", DoubleToString(lot, 2), ")");
            }
         }
         else
         {
            Print("DEBUG: signal=0 - ไม่มีสัญญาณเข้าเทรด");
         }
      }
      // FIX #1: Martingale - ตรวจสอบ signal direction ก่อนเปิด
      else if (g_tradeCount > 0)
      {
         Print("DEBUG MART: tradeCount=", g_tradeCount, " signal=", signal,
               " isBuy=", g_isBuy, " isSell=", g_isSell);
         // FIX #1: ต้องมี signal direction ตรงกับ position ที่มีอยู่
         if (g_isBuy && signal == 1) // FIX #1: ตรวจสอบ BUY signal
         {
            double lastBuy = FindLastBuyPrice();
            if (lastBuy > 0)
            {
               double pointDiff = (lastBuy - ExtSymbolInfo.Bid()) / _Point;
               Print("DEBUG MART BUY: lastBuy=", DoubleToString(lastBuy, _Digits),
                     " bid=", DoubleToString(ExtSymbolInfo.Bid(), _Digits),
                     " pointDiff=", DoubleToString(pointDiff, 0),
                     " require>=", DoubleToString(MartingaleDistancePoints, 0));
               // BUY: ราคาต้องลงมาห่างจาก Order สุดท้าย >= MartingaleDistancePoints
               if (pointDiff >= MartingaleDistancePoints)
               {
                  double lot = fGetLots(ORDER_TYPE_BUY);
                  Print("DEBUG MART BUY: lot=", DoubleToString(lot, 2));
                  if (lot > 0)
                  {
                     if (ExtTrade.Buy(lot, _Symbol, ExtSymbolInfo.Ask(),
                                      0, 0,
                                      "V5.0-MART-BUY"))
                     {
                        Print("MART BUY OPENED - Lot:", lot, " Distance:", DoubleToString(pointDiff, 0));
                        UpdateMartingaleTP();
                     }
                     else
                     {
                        Print("MART BUY FAILED! Error=", GetLastError(),
                              " retcode=", ExtTrade.ResultRetcode());
                     }
                  }
               }
               else
               {
                  Print("DEBUG MART BUY SKIPPED: distance=", DoubleToString(pointDiff, 0),
                        " < ", DoubleToString(MartingaleDistancePoints, 0));
               }
            }
         }
         else if (g_isSell && signal == -1) // FIX #1: ตรวจสอบ SELL signal
         {
            double lastSell = FindLastSellPrice();
            if (lastSell > 0)
            {
               double pointDiff = (ExtSymbolInfo.Ask() - lastSell) / _Point;
               Print("DEBUG MART SELL: lastSell=", DoubleToString(lastSell, _Digits),
                     " ask=", DoubleToString(ExtSymbolInfo.Ask(), _Digits),
                     " pointDiff=", DoubleToString(pointDiff, 0),
                     " require>=", DoubleToString(MartingaleDistancePoints, 0));
               // SELL: ราคาต้องขึ้นมาห่างจาก Order สุดท้าย >= MartingaleDistancePoints
               if (pointDiff >= MartingaleDistancePoints)
               {
                  double lot = fGetLots(ORDER_TYPE_SELL);
                  Print("DEBUG MART SELL: lot=", DoubleToString(lot, 2));
                  if (lot > 0)
                  {
                     if (ExtTrade.Sell(lot, _Symbol, ExtSymbolInfo.Bid(),
                                       0, 0,
                                       "V5.0-MART-SELL"))
                     {
                        Print("MART SELL OPENED - Lot:", lot, " Distance:", DoubleToString(pointDiff, 0));
                        UpdateMartingaleTP();
                     }
                     else
                     {
                        Print("MART SELL FAILED! Error=", GetLastError(),
                              " retcode=", ExtTrade.ResultRetcode());
                     }
                  }
               }
               else
               {
                  Print("DEBUG MART SELL SKIPPED: distance=", DoubleToString(pointDiff, 0),
                        " < ", DoubleToString(MartingaleDistancePoints, 0));
               }
            }
         }
         else
         {
            Print("DEBUG MART: signal mismatch - isBuy=", g_isBuy, " isSell=", g_isSell, " signal=", signal);
         }
      }
   }
   else
   {
      Print("DEBUG: tradeCount=", g_tradeCount, " >= MaxTrades=", MaxTrades, " - SKIP entry");
   }
}
//+------------------------------------------------------------------+
