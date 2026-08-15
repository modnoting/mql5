//+------------------------------------------------------------------+
//|                           RSI_Stoch_Momentum_V3_Combined.mq5     |
//|                           Plan 3: Combined System (สมบูรณ์ที่สุด) |
//+------------------------------------------------------------------+
#property copyright "RSI+Stoch+Momentum EA V3 - Combined"
#property link      ""
#property version   "3.04"
#property description "ระบบ Combined V3 - Fixed v3.04 (3-digit XAUUSDc)"
#property description ""
#property description "แก้ไขทั้งหมด:"
#property description "1. SL 1500->5000 ($5), TP 3000->8000 ($8)"
#property description "2. Dynamic Stoch SL: Threshold 15->25"
#property description "3. Breakeven: Start 1000->3000, Offset 200->500"
#property description "4. Trailing: Start 1500->5000, Step 300->1000"
#property description "5. MinConfirmation = 3"
#property description "6. MaxTradesPerDay = 6"
#property description "7. แก้ M1->Period() ทุกจุด"
#property description "8. แก้ TimeLocal->TimeCurrent"
#property description "9. Signal conditions ไม่ขัดแย้ง"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- Indicator Periods
input int      RSI_Period = 14;
input int      Stoch_K = 5;
input int      Stoch_D = 3;
input int      Stoch_Slowing = 3;
input int      Momentum_Period = 14;
input int      EMA_Period = 200;

//--- RSI Levels
input double   RSI_Oversold = 30.0;
input double   RSI_Overbought = 70.0;

//--- Stochastic Levels
input double   Stoch_Oversold = 20.0;
input double   Stoch_Overbought = 80.0;

//--- Risk Management
input double   LotSize = 0.05;
input int      InitialSLPoints = 5000;
input int      TakeProfitPoints = 8000;
input int      MaxSpreadPoints = 300;

//--- Dynamic Stoch SL (ปรับปรุง)
input bool     UseDynamicSL = true;
input int      StochSLThreshold = 25;

//--- Breakeven SL (ปรับปรุง)
input bool     UseBreakeven = true;
input int      BreakevenStartPoints = 3000;
input int      BreakevenOffsetPoints = 500;

//--- Trailing Stop (ปรับปรุง)
input bool     UseTrailingStop = true;
input int      TrailingStartPoints = 5000;
input int      TrailingStepPoints = 1000;

//--- Time Filter
input bool     UseTimeFilter = true;
input int      StartHour = 8;
input int      EndHour = 20;

//--- Confirmation Required
input int      MinConfirmation = 3;

//--- Trade Control
input int      MaxTradesPerDay = 6;
input int      MinBarsBetweenTrades = 10;

//--- Magic Number
input int      MagicNumber = 123456;

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
CTrade   trade;

int handleEMA;
int handleRSI;
int handleStochMain;
int handleStochSignal;
int handleMomentum;

//--- Dynamic SL: เก็บค่า Stoch ตอนเปิดออเดอร์
double g_stochAtBuyEntry = 0;
double g_stochAtSellEntry = 0;

//--- Trade Control
datetime g_lastTradeTime = 0;
int g_tradesToday = 0;
datetime g_lastDay = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   handleEMA = iMA(_Symbol, Period(), EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, Period(), RSI_Period, PRICE_CLOSE);
   handleStochMain = iStochastic(_Symbol, Period(), Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleStochSignal = iStochastic(_Symbol, Period(), Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleMomentum = iMomentum(_Symbol, Period(), Momentum_Period, PRICE_CLOSE);

   if(handleEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE ||
      handleStochMain == INVALID_HANDLE || handleStochSignal == INVALID_HANDLE ||
      handleMomentum == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== RSI+Stoch+Momentum EA V3-Combined Initialized ===");
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   Print("Point: ", point, " | Digits: ", digits);
   Print("SL Distance: ", InitialSLPoints * point, " | TP Distance: ", TakeProfitPoints * point);
   Print("InitialSL: ", InitialSLPoints, " | TP: ", TakeProfitPoints);
   Print("Dynamic SL: ", UseDynamicSL, " | Threshold: ", StochSLThreshold);
   Print("Breakeven: ", UseBreakeven, " | Start: ", BreakevenStartPoints, " | Offset: ", BreakevenOffsetPoints);
   Print("Trailing: ", UseTrailingStop, " | Start: ", TrailingStartPoints, " | Step: ", TrailingStepPoints);
   Print("MaxTrades/Day: ", MaxTradesPerDay, " | MinBarsBetween: ", MinBarsBetweenTrades);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleStochMain);
   IndicatorRelease(handleStochSignal);
   IndicatorRelease(handleMomentum);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(UseTimeFilter && !IsTradeTime())
      return;

   if(!IsNewBar())
      return;

   ResetDailyCounter();

   //--- จัดการ Exit ตามลำดับ: Dynamic SL > Breakeven > Trailing
   ManageDynamicSL();

   if(!CanTrade())
      return;

   int signal = GetEntrySignal();

   if(signal == 1)
      ExecuteBuy();
   else if(signal == -1)
      ExecuteSell();
}

//+------------------------------------------------------------------+
//| Get indicator buffer value                                        |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int buffer, int shift)
{
   double buf[];
   if(CopyBuffer(handle, buffer, shift, 1, buf) <= 0)
      return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, Period(), 0);
   if(currentBarTime == g_lastBarTime)
      return false;
   g_lastBarTime = currentBarTime;
   return true;
}

//+------------------------------------------------------------------+
//| Check trading time                                               |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Reset daily trade counter                                        |
//+------------------------------------------------------------------+
void ResetDailyCounter()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if(today != g_lastDay)
   {
      g_tradesToday = 0;
      g_lastDay = today;
   }
}

//+------------------------------------------------------------------+
//| Can trade - check trade limits                                   |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(g_tradesToday >= MaxTradesPerDay)
      return false;

   datetime currentBarTime = iTime(_Symbol, Period(), 0);
   if((currentBarTime - g_lastTradeTime) < MinBarsBetweenTrades * PeriodSeconds(Period()))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get EMA value                                                    |
//+------------------------------------------------------------------+
double GetEMA(int shift)
{
   return GetIndicatorValue(handleEMA, 0, shift);
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSI(int shift)
{
   return GetIndicatorValue(handleRSI, 0, shift);
}

//+------------------------------------------------------------------+
//| Get Stochastic Main (K) value                                    |
//+------------------------------------------------------------------+
double GetStochMain(int shift)
{
   return GetIndicatorValue(handleStochMain, 0, shift);
}

//+------------------------------------------------------------------+
//| Get Stochastic Signal (D) value                                  |
//+------------------------------------------------------------------+
double GetStochSignal(int shift)
{
   return GetIndicatorValue(handleStochSignal, 1, shift);
}

//+------------------------------------------------------------------+
//| Get Momentum value                                               |
//+------------------------------------------------------------------+
double GetMomentum(int shift)
{
   return GetIndicatorValue(handleMomentum, 0, shift);
}

//+------------------------------------------------------------------+
//| Get Entry Signal - V3                                            |
//+------------------------------------------------------------------+
int GetEntrySignal()
{
   double close0 = iClose(_Symbol, Period(), 1);
   double close1 = iClose(_Symbol, Period(), 2);

   double ema = GetEMA(1);

   double rsi = GetRSI(1);
   double stochMain = GetStochMain(1);
   double stochSignal = GetStochSignal(1);
   double momentum = GetMomentum(1);

   double rsiPrev = GetRSI(2);
   double stochMainPrev = GetStochMain(2);
   double stochSignalPrev = GetStochSignal(2);
   double momentumPrev = GetMomentum(2);

   double rsiPrev2 = GetRSI(3);
   double momentumPrev2 = GetMomentum(3);

   int buyScore = 0;
   int sellScore = 0;

   //--- BUY Conditions (สอดคล้องกัน: uptrend + pullback reversal)
   bool trendBuy = (close0 > ema);
   bool rsiBuy = (rsi <= RSI_Oversold && rsi > rsiPrev);
   bool stochBuy = (stochMain < Stoch_Oversold && stochMain > stochSignal);
   bool momBuy = (momentum > momentumPrev);

   //--- SELL Conditions (สอดคล้องกัน: downtrend + pullback reversal)
   bool trendSell = (close0 < ema);
   bool rsiSell = (rsi >= RSI_Overbought && rsi < rsiPrev);
   bool stochSell = (stochMain > Stoch_Overbought && stochMain < stochSignal);
   bool momSell = (momentum < momentumPrev);

   if(trendBuy) buyScore++;
   if(rsiBuy) buyScore++;
   if(stochBuy) buyScore++;
   if(momBuy) buyScore++;

   if(trendSell) sellScore++;
   if(rsiSell) sellScore++;
   if(stochSell) sellScore++;
   if(momSell) sellScore++;

   if(buyScore >= MinConfirmation && trendBuy)
      return 1;

   if(sellScore >= MinConfirmation && trendSell)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   if(HasOpenPosition(POSITION_TYPE_BUY))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if((ask - bid) / point > MaxSpreadPoints)
   {
      Print("Spread too high: ", (ask - bid) / point);
      return;
   }

   double lot = GetLotSize();
   if(lot <= 0)
      return;

   //--- เพิ่ม Initial SL ป้องกัน losses
   double sl = NormalizeDouble(ask - InitialSLPoints * point, digits);
   double tp = NormalizeDouble(ask + TakeProfitPoints * point, digits);

   //--- เก็บค่า Stoch ตอนเปิดออเดอร์
   g_stochAtBuyEntry = GetStochMain(0);

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "RSI_Stoch_BUY_CMB"))
   {
       g_tradesToday++;
       g_lastTradeTime = iTime(_Symbol, Period(), 0);
       Print("BUY V3-Combined Opened: ", trade.ResultOrder(), " @ ", ask, " SL: ", sl, " TP: ", tp);
       Print("Stoch at Entry: ", g_stochAtBuyEntry, " | Dynamic SL + Breakeven + Trailing Active");
   }
   else
      Print("BUY V3-Combined Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                               |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   if(HasOpenPosition(POSITION_TYPE_SELL))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if((ask - bid) / point > MaxSpreadPoints)
   {
      Print("Spread too high: ", (ask - bid) / point);
      return;
   }

   double lot = GetLotSize();
   if(lot <= 0)
      return;

   //--- เพิ่ม Initial SL ป้องกัน losses
   double sl = NormalizeDouble(bid + InitialSLPoints * point, digits);
   double tp = NormalizeDouble(bid - TakeProfitPoints * point, digits);

   //--- เก็บค่า Stoch ตอนเปิดออเดอร์
   g_stochAtSellEntry = GetStochMain(0);

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "RSI_Stoch_SELL_CMB"))
   {
       g_tradesToday++;
       g_lastTradeTime = iTime(_Symbol, Period(), 0);
       Print("SELL V3-Combined Opened: ", trade.ResultOrder(), " @ ", bid, " SL: ", sl, " TP: ", tp);
       Print("Stoch at Entry: ", g_stochAtSellEntry, " | Dynamic SL + Breakeven + Trailing Active");
   }
   else
      Print("SELL V3-Combined Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Check open position                                              |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get lot size                                                     |
//+------------------------------------------------------------------+
double GetLotSize()
{
   double lot = LotSize;
   lot = NormalizeDouble(lot, 2);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < minLot) lot = minLot;

   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lot > maxLot) lot = maxLot;

   double marginRequired = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      Print("Cannot calculate margin");
      return 0;
   }

   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < marginRequired)
   {
      Print("Not enough free margin");
      return 0;
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Manage Dynamic SL + Breakeven + Trailing (Combined)              |
//+------------------------------------------------------------------+
void ManageDynamicSL()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stochCurrent = GetStochMain(0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPrice;

         //--- 1. Dynamic Stoch SL: ปิดถ้า Stoch ย้อนกลับ (Threshold 15)
         if(UseDynamicSL)
         {
            if(stochCurrent < g_stochAtBuyEntry - StochSLThreshold)
            {
               if(trade.PositionClose(ticket))
               {
                  Print("BUY Closed by Dynamic Stoch SL");
                  Print("Stoch: ", stochCurrent, " < Entry-", StochSLThreshold, " = ", g_stochAtBuyEntry - StochSLThreshold);
               }
               continue;
            }
         }

         //--- 2. Breakeven: เลื่อน SL เหนือจุดคุ้มทุน (มี offset)
         if(UseBreakeven)
         {
            if(profit >= BreakevenStartPoints * point)
            {
               double newSL = NormalizeDouble(openPrice + BreakevenOffsetPoints * point, digits);
               if(newSL > currentSL)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("BUY Breakeven SL moved to: ", newSL);
               }
            }
         }

         //--- 3. Trailing Stop: ล็อคกำไร
         if(UseTrailingStop)
         {
            if(profit >= TrailingStartPoints * point)
            {
               double newSL = NormalizeDouble(bid - TrailingStepPoints * point, digits);
               if(newSL > currentSL)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("BUY Trailing SL moved to: ", newSL);
               }
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPrice - ask;

         //--- 1. Dynamic Stoch SL: ปิดถ้า Stoch ย้อนกลับ (Threshold 15)
         if(UseDynamicSL)
         {
            if(stochCurrent > g_stochAtSellEntry + StochSLThreshold)
            {
               if(trade.PositionClose(ticket))
               {
                  Print("SELL Closed by Dynamic Stoch SL");
                  Print("Stoch: ", stochCurrent, " > Entry+", StochSLThreshold, " = ", g_stochAtSellEntry + StochSLThreshold);
               }
               continue;
            }
         }

         //--- 2. Breakeven: เลื่อน SL ต่ำกว่าจุดคุ้มทุน (มี offset)
         if(UseBreakeven)
         {
            if(profit >= BreakevenStartPoints * point)
            {
               double newSL = NormalizeDouble(openPrice - BreakevenOffsetPoints * point, digits);
               if(newSL < currentSL || currentSL == 0)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("SELL Breakeven SL moved to: ", newSL);
               }
            }
         }

         //--- 3. Trailing Stop: ล็อคกำไร
         if(UseTrailingStop)
         {
            if(profit >= TrailingStartPoints * point)
            {
               double newSL = NormalizeDouble(ask + TrailingStepPoints * point, digits);
               if(newSL < currentSL || currentSL == 0)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("SELL Trailing SL moved to: ", newSL);
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+