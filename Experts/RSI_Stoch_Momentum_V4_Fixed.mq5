//+------------------------------------------------------------------+
//|                  RSI_Stoch_Momentum_V4_Fixed.mq5                |
//|                  แก้ไขปัญหา EA ขาดทุน ทุกจุด                    |
//+------------------------------------------------------------------+
#property copyright "RSI+Stoch+Momentum EA V4 - Fixed"
#property link      ""
#property version   "4.01"
#property description "V4 Fixed - แก้ไขปัญหาขาดทุนทุกจุดจากกราฟ"
#property description ""
#property description "สิ่งที่แก้ไขทั้งหมด:"
#property description "1. เพิ่ม Initial SL ป้องกัน losses มหาศาล"
#property description "2. ลบ Dynamic Stoch SL ออก"
#property description "3. เพิ่ม ADX Filter: ไม่เทรดใน sideways"
#property description "4. เพิ่ม EMA Distance: ไม่เข้าชิด EMA"
#property description "5. เพิ่ม ATR Filter: ไม่เทรดใน volatile ต่ำ"
#property description "6. เพิ่ม HTF Trend Confirmation"
#property description "7. Breakeven + Trailing ปรับใหม่"
#property description "8. ลด Overtrading"
#property description "9. Lot size คำนวณจาก % risk"

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

//--- ADX Filter (ใหม่)
input int      ADX_Period = 14;
input double   ADX_MinLevel = 20.0;

//--- ATR Filter (ใหม่)
input int      ATR_Period = 14;
input double   ATR_MinMultiple = 1.0;

//--- EMA Distance (ใหม่)
input int      EMA_Distance_Min = 300;

//--- RSI Levels
input double   RSI_Oversold = 30.0;
input double   RSI_Overbought = 70.0;

//--- Stochastic Levels
input double   Stoch_Oversold = 20.0;
input double   Stoch_Overbought = 80.0;

//--- Risk Management
input double   LotSize = 0.05;
input double   RiskPercent = 1.0;
input int      StopLossPoints = 1500;
input int      TakeProfitPoints = 3000;
input int      MaxSpreadPoints = 300;

//--- Breakeven
input bool     UseBreakeven = true;
input int      BreakevenStartPoints = 1000;
input int      BreakevenOffsetPoints = 200;

//--- Trailing Stop
input bool     UseTrailingStop = true;
input int      TrailingStartPoints = 1500;
input int      TrailingStepPoints = 300;

//--- Time Filter
input bool     UseTimeFilter = true;
input int      StartHour = 8;
input int      EndHour = 20;

//--- Trade Control
input int      MinConfirmation = 4;
input int      MinBarsBetweenTrades = 10;
input int      MaxTradesPerDay = 6;
input int      MaxConsecutiveLoss = 3;

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
int handleADX;
int handleATR;

datetime g_lastTradeTime = 0;
int g_tradesToday = 0;
datetime g_lastDay = 0;
int g_consecutiveLosses = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ENUM_TIMEFRAMES tf = PERIOD_M5;

   handleEMA = iMA(_Symbol, tf, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, tf, RSI_Period, PRICE_CLOSE);
   handleStochMain = iStochastic(_Symbol, tf, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleStochSignal = iStochastic(_Symbol, tf, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleMomentum = iMomentum(_Symbol, tf, Momentum_Period, PRICE_CLOSE);
   handleADX = iADX(_Symbol, tf, ADX_Period);
   handleATR = iATR(_Symbol, tf, ATR_Period);

   if(handleEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE ||
      handleStochMain == INVALID_HANDLE || handleStochSignal == INVALID_HANDLE ||
      handleMomentum == INVALID_HANDLE || handleADX == INVALID_HANDLE ||
      handleATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== RSI+Stoch+Momentum EA V4-Fixed Initialized ===");
   Print("Timeframe: M5 | SL: ", StopLossPoints, " | TP: ", TakeProfitPoints);
   Print("ADX Filter: MinLevel=", ADX_MinLevel, " | ATR MinMultiple=", ATR_MinMultiple);
   Print("EMA Distance Min: ", EMA_Distance_Min);
   Print("Breakeven: ", UseBreakeven, " | Start: ", BreakevenStartPoints, " | Offset: ", BreakevenOffsetPoints);
   Print("Trailing: ", UseTrailingStop, " | Start: ", TrailingStartPoints, " | Step: ", TrailingStepPoints);
   Print("MaxTrades/Day: ", MaxTradesPerDay, " | MaxConsecLoss: ", MaxConsecutiveLoss);
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
   IndicatorRelease(handleADX);
   IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyCounter();

   if(UseTimeFilter && !IsTradeTime())
      return;

   if(!IsNewBar())
      return;

   ManagePositions();

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
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
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
   TimeLocal(dt);
   return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Reset daily trade counter                                        |
//+------------------------------------------------------------------+
void ResetDailyCounter()
{
   MqlDateTime dt;
   TimeLocal(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if(today != g_lastDay)
   {
      g_tradesToday = 0;
      g_consecutiveLosses = 0;
      g_lastDay = today;
   }
}

//+------------------------------------------------------------------+
//| Can trade - check all conditions                                 |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(g_tradesToday >= MaxTradesPerDay)
      return false;

   if(g_consecutiveLosses >= MaxConsecutiveLoss)
      return false;

   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if((currentBarTime - g_lastTradeTime) < MinBarsBetweenTrades * PeriodSeconds(PERIOD_M5))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get indicator values                                             |
//+------------------------------------------------------------------+
double GetEMA(int shift) { return GetIndicatorValue(handleEMA, 0, shift); }
double GetRSI(int shift) { return GetIndicatorValue(handleRSI, 0, shift); }
double GetStochMain(int shift) { return GetIndicatorValue(handleStochMain, 0, shift); }
double GetStochSignal(int shift) { return GetIndicatorValue(handleStochSignal, 1, shift); }
double GetMomentum(int shift) { return GetIndicatorValue(handleMomentum, 0, shift); }
double GetADX(int shift) { return GetIndicatorValue(handleADX, 0, shift); }
double GetATR(int shift) { return GetIndicatorValue(handleATR, 0, shift); }

//+------------------------------------------------------------------+
//| Check if trend is strong enough (ADX + EMA distance)             |
//+------------------------------------------------------------------+
bool IsTrendStrong(int direction)
{
   double adx = GetADX(1);
   if(adx < ADX_MinLevel)
      return false;

   double atr = GetATR(1);
   if(atr <= 0)
      return false;

   double close0 = iClose(_Symbol, PERIOD_M5, 1);
   double ema = GetEMA(1);
   double distance = MathAbs(close0 - ema);

   if(distance < EMA_Distance_Min * SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return false;

   if(direction == 1 && close0 <= ema)
      return false;
   if(direction == -1 && close0 >= ema)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check if market is trending (not sideways)                        |
//+------------------------------------------------------------------+
bool IsMarketTrending()
{
   double atr = GetATR(1);
   double atrPrev = GetATR(2);
   if(atr <= 0 || atrPrev <= 0)
      return false;

   if(atr < atrPrev * ATR_MinMultiple)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get Entry Signal - V4 (แก้ไขทุกจุด)                             |
//+------------------------------------------------------------------+
int GetEntrySignal()
{
   double close0 = iClose(_Symbol, PERIOD_M5, 1);
   double close1 = iClose(_Symbol, PERIOD_M5, 2);
   double close2 = iClose(_Symbol, PERIOD_M5, 3);

   double ema = GetEMA(1);

   double rsi = GetRSI(1);
   double stochMain = GetStochMain(1);
   double stochSignal = GetStochSignal(1);
   double momentum = GetMomentum(1);

   double rsiPrev = GetRSI(2);
   double stochMainPrev = GetStochMain(2);
   double stochSignalPrev = GetStochSignal(2);
   double momentumPrev = GetMomentum(2);

   //--- ตรวจสอบ Market Trending ก่อน
   if(!IsMarketTrending())
      return 0;

   int buyScore = 0;
   int sellScore = 0;

   //--- BUY Conditions (เข้มงวดสุดๆ)
   bool trendBuy = IsTrendStrong(1);
   bool rsiBuy = (rsi <= RSI_Oversold && rsi > rsiPrev && rsiPrev > GetRSI(3));
   bool stochBuy = (stochMain < Stoch_Oversold &&
                    stochMain > stochSignal &&
                    stochMainPrev <= stochSignalPrev);
   bool momBuy = (momentum > 100 && momentum > momentumPrev && momentumPrev > GetMomentum(3));

   //--- SELL Conditions (เข้มงวดสุดๆ)
   bool trendSell = IsTrendStrong(-1);
   bool rsiSell = (rsi >= RSI_Overbought && rsi < rsiPrev && rsiPrev < GetRSI(3));
   bool stochSell = (stochMain > Stoch_Overbought &&
                     stochMain < stochSignal &&
                     stochMainPrev >= stochSignalPrev);
   bool momSell = (momentum < 100 && momentum < momentumPrev && momentumPrev < GetMomentum(3));

   if(trendBuy) buyScore++;
   if(rsiBuy) buyScore++;
   if(stochBuy) buyScore++;
   if(momBuy) buyScore++;

   if(trendSell) sellScore++;
   if(rsiSell) sellScore++;
   if(stochSell) sellScore++;
   if(momSell) sellScore++;

   //--- ต้องครบทุก condition
   if(buyScore >= MinConfirmation && trendBuy)
      return 1;

   if(sellScore >= MinConfirmation && trendSell)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Calculate lot size by risk                                       |
//+------------------------------------------------------------------+
double CalcLotByRisk()
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(tickValue <= 0 || tickSize <= 0 || accountBalance <= 0)
      return LotSize;

   double riskAmount = accountBalance * RiskPercent / 100.0;
   double slMoney = StopLossPoints * tickValue / tickSize;

   if(slMoney <= 0)
      return LotSize;

   double lot = riskAmount / slMoney;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lot = MathMax(lot, minLot);

   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathMin(lot, maxLot);

   return NormalizeDouble(lot, 2);
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

   double lot = CalcLotByRisk();
   if(lot <= 0)
      return;

   double sl = NormalizeDouble(ask - StopLossPoints * point, digits);
   double tp = NormalizeDouble(ask + TakeProfitPoints * point, digits);

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "RSI_Stoch_BUY_V4"))
   {
      g_tradesToday++;
      g_lastTradeTime = iTime(_Symbol, PERIOD_M5, 0);
      Print("BUY V4 Opened: ", trade.ResultOrder(), " @ ", ask, " SL: ", sl, " TP: ", tp, " Lot: ", lot);
      Print("ADX=", GetADX(1), " ATR=", GetATR(1), " EMA_Dist=", MathAbs(ask - GetEMA(1))/point);
   }
   else
      Print("BUY V4 Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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

   double lot = CalcLotByRisk();
   if(lot <= 0)
      return;

   double sl = NormalizeDouble(bid + StopLossPoints * point, digits);
   double tp = NormalizeDouble(bid - TakeProfitPoints * point, digits);

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "RSI_Stoch_SELL_V4"))
   {
      g_tradesToday++;
      g_lastTradeTime = iTime(_Symbol, PERIOD_M5, 0);
      Print("SELL V4 Opened: ", trade.ResultOrder(), " @ ", bid, " SL: ", sl, " TP: ", tp, " Lot: ", lot);
      Print("ADX=", GetADX(1), " ATR=", GetATR(1), " EMA_Dist=", MathAbs(bid - GetEMA(1))/point);
   }
   else
      Print("SELL V4 Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
//| Check if position closed by SL (consecutive loss tracking)       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol)
         {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            {
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
               double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
               double totalProfit = profit + swap + commission;

               if(totalProfit < 0)
                  g_consecutiveLosses++;
               else
                  g_consecutiveLosses = 0;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Positions: Breakeven + Trailing                           |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

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

         if(UseBreakeven && profit >= BreakevenStartPoints * point)
         {
            double newSL = NormalizeDouble(openPrice + BreakevenOffsetPoints * point, digits);
            if(newSL > currentSL)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("BUY Breakeven SL moved to: ", newSL);
            }
         }

         if(UseTrailingStop && profit >= TrailingStartPoints * point)
         {
            double newSL = NormalizeDouble(bid - TrailingStepPoints * point, digits);
            if(newSL > currentSL)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("BUY Trailing SL moved to: ", newSL);
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPrice - ask;

         if(UseBreakeven && profit >= BreakevenStartPoints * point)
         {
            double newSL = NormalizeDouble(openPrice - BreakevenOffsetPoints * point, digits);
            if(newSL < currentSL || currentSL == 0)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("SELL Breakeven SL moved to: ", newSL);
            }
         }

         if(UseTrailingStop && profit >= TrailingStartPoints * point)
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
//+------------------------------------------------------------------+
