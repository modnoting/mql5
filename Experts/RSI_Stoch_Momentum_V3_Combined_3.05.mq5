//+------------------------------------------------------------------+
//|                  RSI_Stoch_Momentum_V3_Combined_3.05.mq5        |
//|                  Plan 3: Combined System (v3.05 fix15)           |
//+------------------------------------------------------------------+
#property copyright "RSI+Stoch+Momentum EA V3 - Combined v3.05"
#property link      ""
#property version   "3.05"
#property description "=== v3.05 fix15 - H1+M5 Trend Filter (Dual TF) ==="
#property description ""
#property description "fix14: SELL ทั้งที่ H1 บอก downtrend แต่ราคาขึ้น $100"
#property description "สาเหตุ: H1 EMA lagging, M5 EMA ไม่ได้ใช้"
#property description "fix15: เพิ่ม M5 Trend Filter (H1+M5 ต้องตรงกัน)"
#property description ""
#property description "fix15 แก้ไข:"
#property description "1. trendBuy = H1 UP && M5 UP && ADX>20"
#property description "2. trendSell = H1 DOWN && M5 DOWN && ADX>20"
#property description "3. Lot=0.02 (ลดความเสี่ยง)"
#property description "4. TP=9000 SL=6000 (R:R=1:1.5)"
#property description "5. BE/Trail=OFF (let it run)"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int      RSI_Period = 14;
input int      Stoch_K = 5;
input int      Stoch_D = 3;
input int      Stoch_Slowing = 3;
input int      Momentum_Period = 14;
input int      EMA_Short_Period = 50;
input int      EMA_Long_Period = 200;
input int      ADX_Period = 14;

input double   RSI_Oversold = 30.0;
input double   RSI_Overbought = 70.0;

input double   Stoch_Oversold = 20.0;
input double   Stoch_Overbought = 80.0;

input double   LotSize = 0.02;
input bool     UseDynamicLot = false;
input double   RiskPercent = 3.0;
input int      InitialSLPoints = 6000;
input int      TakeProfitPoints = 9000;
input int      MaxSpreadPoints = 400;

input bool     UseBreakeven = false;
input int      BreakevenStartPoints = 5000;
input int      BreakevenOffsetPoints = 2000;

input bool     UseTrailingStop = false;
input int      TrailingStartPoints = 8000;
input int      TrailingStepPoints = 3000;

input bool     UseTimeFilter = true;
input int      StartHour = 8;
input int      EndHour = 22;

input double   MinADX = 20.0;
input int      MinConfirmation = 4;
input int      MaxTradesPerDay = 2;
input int      MinBarsBetweenTrades = 30;

input bool     UseDailyTarget = false;
input double   DailyProfitTarget = 10.0;
input bool     CloseOnTrendReversal = true;

input int      MagicNumber = 123456;

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
CTrade   trade;

int handleEMAShort;
int handleEMALong;
int handleRSI;
int handleStochMain;
int handleStochSignal;
int handleMomentum;
int handleADX;

int handleH1EMAShort;
int handleH1EMALong;

datetime g_lastTradeTime = 0;
int g_tradesToday = 0;
datetime g_lastDay = 0;
double g_dayStartBalance = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   handleEMAShort = iMA(_Symbol, Period(), EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMALong = iMA(_Symbol, Period(), EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, Period(), RSI_Period, PRICE_CLOSE);
   handleStochMain = iStochastic(_Symbol, Period(), Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleStochSignal = iStochastic(_Symbol, Period(), Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleMomentum = iMomentum(_Symbol, Period(), Momentum_Period, PRICE_CLOSE);
   handleADX = iADX(_Symbol, Period(), ADX_Period);

   handleH1EMAShort = iMA(_Symbol, PERIOD_H1, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleH1EMALong = iMA(_Symbol, PERIOD_H1, EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleEMAShort == INVALID_HANDLE || handleEMALong == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleStochMain == INVALID_HANDLE ||
      handleStochSignal == INVALID_HANDLE || handleMomentum == INVALID_HANDLE ||
      handleADX == INVALID_HANDLE ||
      handleH1EMAShort == INVALID_HANDLE || handleH1EMALong == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("=== v3.05 fix12 Conservative Trend Rider ===");
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Print("SL: ", InitialSLPoints, " ($", DoubleToString(InitialSLPoints*point,1), ")",
         " | TP: ", TakeProfitPoints, " ($", DoubleToString(TakeProfitPoints*point,1), ")",
         " | R:R = 1:", DoubleToString((double)TakeProfitPoints/InitialSLPoints,2));
   Print("Lot: ", LotSize,
         " | Breakeven: ", (UseBreakeven ? "ON" : "OFF"),
         " | Trailing: ", (UseTrailingStop ? "ON" : "OFF"));
   Print("MinADX: ", MinADX,
         " | MinConfirmation: ", MinConfirmation,
         " | MaxTrades: ", MaxTradesPerDay);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMAShort);
   IndicatorRelease(handleEMALong);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleStochMain);
   IndicatorRelease(handleStochSignal);
   IndicatorRelease(handleMomentum);
   IndicatorRelease(handleADX);
   IndicatorRelease(handleH1EMAShort);
   IndicatorRelease(handleH1EMALong);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(UseTimeFilter && !IsTradeTime()) return;

   ResetDailyCounter();

   if(UseDailyTarget && IsDailyTargetReached()) return;

   ManagePositions();

   if(!IsNewBar()) return;
   if(!CanTrade()) return;

   int signal = GetEntrySignal();
   if(signal == 1) ExecuteBuy();
   else if(signal == -1) ExecuteSell();
}

//+------------------------------------------------------------------+
double GetVal(int handle, int buffer, int shift)
{
   double buf[];
   if(CopyBuffer(handle, buffer, shift, 1, buf) <= 0) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, Period(), 0);
   if(t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

//+------------------------------------------------------------------+
bool IsTradeTime()
{
   MqlDateTime dt; TimeCurrent(dt);
   return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
void ResetDailyCounter()
{
   MqlDateTime dt; TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day));
   if(today != g_lastDay)
   {
      g_tradesToday = 0;
      g_lastDay = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }
}

//+------------------------------------------------------------------+
bool CanTrade()
{
   if(g_tradesToday >= MaxTradesPerDay) return false;
   datetime t = iTime(_Symbol, Period(), 0);
   if((t - g_lastTradeTime) < MinBarsBetweenTrades * PeriodSeconds(Period())) return false;
   return true;
}

//+------------------------------------------------------------------+
bool IsDailyTargetReached()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double profit = balance - g_dayStartBalance;
   if(profit >= DailyProfitTarget)
   {
      Print("Daily target reached: $", DoubleToString(profit,2));
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int GetEntrySignal()
{
   double close0 = iClose(_Symbol, Period(), 1);

   double emaShort = GetVal(handleEMAShort, 0, 1);
   double emaLong = GetVal(handleEMALong, 0, 1);
   double rsi = GetVal(handleRSI, 0, 1);
   double stochMain = GetVal(handleStochMain, 0, 1);
   double stochSignal = GetVal(handleStochSignal, 1, 1);
   double momentum = GetVal(handleMomentum, 0, 1);
   double rsiPrev = GetVal(handleRSI, 0, 2);
   double momentumPrev = GetVal(handleMomentum, 0, 2);
   double adx = GetVal(handleADX, 0, 1);

   double h1EmaShort = GetVal(handleH1EMAShort, 0, 0);
   double h1EmaLong = GetVal(handleH1EMALong, 0, 0);

    bool h1Uptrend = (h1EmaShort > h1EmaLong);
    bool h1Downtrend = (h1EmaShort < h1EmaLong);
    bool m5Uptrend = (emaShort > emaLong);
    bool m5Downtrend = (emaShort < emaLong);
    bool strongTrend = (adx >= MinADX);

    int buyScore = 0;
    int sellScore = 0;

    bool trendBuy = h1Uptrend && m5Uptrend && strongTrend;
    bool rsiBuy = (rsi <= RSI_Oversold && rsi > rsiPrev);
    bool stochBuy = (stochMain < Stoch_Oversold && stochMain > stochSignal);
    bool momBuy = (momentum > momentumPrev);

    bool trendSell = h1Downtrend && m5Downtrend && strongTrend;
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
void ExecuteBuy()
{
   if(HasOpenPosition(POSITION_TYPE_BUY)) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if((ask-bid)/point > MaxSpreadPoints) return;

   double lot = GetLotSize();
   if(lot <= 0) return;

   double sl = NormalizeDouble(ask - InitialSLPoints * point, digits);
   double tp = NormalizeDouble(ask + TakeProfitPoints * point, digits);

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "BUY_fix12"))
   {
      g_tradesToday++;
      g_lastTradeTime = iTime(_Symbol, Period(), 0);
   }
}

//+------------------------------------------------------------------+
void ExecuteSell()
{
   if(HasOpenPosition(POSITION_TYPE_SELL)) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if((ask-bid)/point > MaxSpreadPoints) return;

   double lot = GetLotSize();
   if(lot <= 0) return;

   double sl = NormalizeDouble(bid + InitialSLPoints * point, digits);
   double tp = NormalizeDouble(bid - TakeProfitPoints * point, digits);

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "SELL_fix12"))
   {
      g_tradesToday++;
      g_lastTradeTime = iTime(_Symbol, Period(), 0);
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
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
double GetLotSize()
{
   double lot = NormalizeDouble(LotSize, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < minLot) lot = minLot;
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lot > maxLot) lot = maxLot;

   if(UseDynamicLot)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue > 0 && tickSize > 0 && point > 0)
      {
         double slMoney = InitialSLPoints * point * tickValue / tickSize;
         if(slMoney > 0)
         {
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double riskAmount = balance * RiskPercent / 100.0;
            lot = riskAmount / slMoney;
            double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            lot = MathFloor(lot / lotStep) * lotStep;
            lot = MathMax(lot, minLot);
            lot = MathMin(lot, maxLot);
         }
      }
   }

   double margin = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
      return 0;
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin)
      return 0;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
void ManagePositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double h1EmaShort = GetVal(handleH1EMAShort, 0, 0);
   double h1EmaLong = GetVal(handleH1EMALong, 0, 0);

   for(int i = PositionsTotal()-1; i >= 0; i--)
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

         if(CloseOnTrendReversal && h1EmaShort < h1EmaLong && profit > 0)
         {
            trade.PositionClose(ticket);
            continue;
         }

         if(UseBreakeven && profit >= BreakevenStartPoints * point)
         {
            double newSL = NormalizeDouble(openPrice + BreakevenOffsetPoints * point, digits);
            if(newSL > currentSL)
               trade.PositionModify(ticket, newSL, currentTP);
         }

         if(UseTrailingStop && profit >= TrailingStartPoints * point)
         {
            double newSL = NormalizeDouble(bid - TrailingStepPoints * point, digits);
            if(newSL > currentSL)
               trade.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPrice - ask;

         if(CloseOnTrendReversal && h1EmaShort > h1EmaLong && profit > 0)
         {
            trade.PositionClose(ticket);
            continue;
         }

         if(UseBreakeven && profit >= BreakevenStartPoints * point)
         {
            double newSL = NormalizeDouble(openPrice - BreakevenOffsetPoints * point, digits);
            if(newSL < currentSL || currentSL == 0)
               trade.PositionModify(ticket, newSL, currentTP);
         }

         if(UseTrailingStop && profit >= TrailingStartPoints * point)
         {
            double newSL = NormalizeDouble(ask + TrailingStepPoints * point, digits);
            if(newSL < currentSL || currentSL == 0)
               trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}
//+------------------------------------------------------------------+
