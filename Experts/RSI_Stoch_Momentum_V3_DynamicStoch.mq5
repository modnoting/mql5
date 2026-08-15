//+------------------------------------------------------------------+
//|                           RSI_Stoch_Momentum_V3_DynamicStoch.mq5 |
//|                           Plan 1: Dynamic Stochastic SL           |
//+------------------------------------------------------------------+
#property copyright "RSI+Stoch+Momentum EA V3 - DynamicStoch"
#property link      ""
#property version   "3.01"
#property description "ระบบ Dynamic Stochastic SL"
#property description "- ปิดออเดอร์เมื่อ Stochastic ย้อนกลับ"
#property description "- ไม่ใช้ Fixed SL"
#property description "- เหมาะสำหรับ Scalping"
#property description ""
#property description "ระบบที่มีอยู่:"
#property description "- Entry: RSI + Stochastic + Momentum + EMA200 (Scoring System)"
#property description "- Exit: Dynamic SL ตาม Stochastic (ใหม่)"
#property description "- Trailing: ไม่มี"

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
input double   RSI_Oversold = 35.0;
input double   RSI_Overbought = 65.0;

//--- Stochastic Levels
input double   Stoch_Oversold = 25.0;
input double   Stoch_Overbought = 75.0;

//--- Risk Management
input double   LotSize = 0.05;
input int      TakeProfitPoints = 2250;
input int      MaxSpreadPoints = 300;

//--- Dynamic Stoch SL (ใหม่)
input bool     UseDynamicSL = true;
input int      StochSLThreshold = 5;

//--- Time Filter
input bool     UseTimeFilter = true;
input int      StartHour = 8;
input int      EndHour = 20;

//--- Confirmation Required
input int      MinConfirmation = 3;

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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   handleEMA = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);
   handleStochMain = iStochastic(_Symbol, PERIOD_M1, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleStochSignal = iStochastic(_Symbol, PERIOD_M1, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   handleMomentum = iMomentum(_Symbol, PERIOD_M1, Momentum_Period, PRICE_CLOSE);

   if(handleEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE ||
      handleStochMain == INVALID_HANDLE || handleStochSignal == INVALID_HANDLE ||
      handleMomentum == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== RSI+Stoch+Momentum EA V3-DynamicStoch Initialized ===");
   Print("Dynamic SL: ", UseDynamicSL, " | Threshold: ", StochSLThreshold);
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

   if(UseDynamicSL)
      ManageDynamicSL();

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
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
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
   double close0 = iClose(_Symbol, PERIOD_M1, 1);

   double ema = GetEMA(1);

   double rsi = GetRSI(1);
   double stochMain = GetStochMain(1);
   double stochSignal = GetStochSignal(1);
   double momentum = GetMomentum(1);

   double rsiPrev = GetRSI(2);
   double stochMainPrev = GetStochMain(2);
   double stochSignalPrev = GetStochSignal(2);
   double momentumPrev = GetMomentum(2);

   int buyScore = 0;
   int sellScore = 0;

   bool trendBuy = (close0 > ema);
   bool rsiBuy = (rsi <= RSI_Oversold + 5 && rsi > rsiPrev);
   bool stochBuy = (stochMain < Stoch_Oversold + 10 &&
                    stochMain > stochSignal &&
                    stochMainPrev <= stochSignalPrev);
   bool momBuy = (momentum > 100 || (momentum > momentumPrev && momentum > 99.5));

   bool trendSell = (close0 < ema);
   bool rsiSell = (rsi >= RSI_Overbought - 5 && rsi < rsiPrev);
   bool stochSell = (stochMain > Stoch_Overbought - 10 &&
                     stochMain < stochSignal &&
                     stochMainPrev >= stochSignalPrev);
   bool momSell = (momentum < 100 || (momentum < momentumPrev && momentum < 100.5));

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

   if((ask - bid) / point > MaxSpreadPoints)
   {
      Print("Spread too high: ", (ask - bid) / point);
      return;
   }

   double lot = GetLotSize();
   if(lot <= 0)
      return;

   //--- Dynamic SL: ตั้ง SL = 0 (ใช้ Dynamic SL แทน)
   double sl = 0;
   double tp = ask + TakeProfitPoints * point;

   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   //--- เก็บค่า Stoch ตอนเปิดออเดอร์
   g_stochAtBuyEntry = GetStochMain(0);

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "RSI_Stoch_BUY_DS"))
   {
      Print("BUY V3-DynamicStoch Opened: ", trade.ResultOrder(), " @ ", ask);
      Print("Stoch at Entry: ", g_stochAtBuyEntry, " | Threshold: ", StochSLThreshold);
   }
   else
      Print("BUY V3-DynamicStoch Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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

   if((ask - bid) / point > MaxSpreadPoints)
   {
      Print("Spread too high: ", (ask - bid) / point);
      return;
   }

   double lot = GetLotSize();
   if(lot <= 0)
      return;

   //--- Dynamic SL: ตั้ง SL = 0 (ใช้ Dynamic SL แทน)
   double sl = 0;
   double tp = bid - TakeProfitPoints * point;

   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   //--- เก็บค่า Stoch ตอนเปิดออเดอร์
   g_stochAtSellEntry = GetStochMain(0);

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "RSI_Stoch_SELL_DS"))
   {
      Print("SELL V3-DynamicStoch Opened: ", trade.ResultOrder(), " @ ", bid);
      Print("Stoch at Entry: ", g_stochAtSellEntry, " | Threshold: ", StochSLThreshold);
   }
   else
      Print("SELL V3-DynamicStoch Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
//| Manage Dynamic Stochastic SL                                     |
//+------------------------------------------------------------------+
void ManageDynamicSL()
{
   double stochCurrent = GetStochMain(0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         //--- BUY: ปิดถ้า Stoch ลงต่ำกว่าค่าที่เปิด - Threshold
         if(stochCurrent < g_stochAtBuyEntry - StochSLThreshold)
         {
            if(trade.PositionClose(ticket))
            {
               Print("BUY Closed by Dynamic Stoch SL");
               Print("Stoch Current: ", stochCurrent, " < Entry: ", g_stochAtBuyEntry, " - ", StochSLThreshold, " = ", g_stochAtBuyEntry - StochSLThreshold);
            }
            else
               Print("BUY Close Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         //--- SELL: ปิดถ้า Stoch สูงกว่าค่าที่เปิด + Threshold
         if(stochCurrent > g_stochAtSellEntry + StochSLThreshold)
         {
            if(trade.PositionClose(ticket))
            {
               Print("SELL Closed by Dynamic Stoch SL");
               Print("Stoch Current: ", stochCurrent, " > Entry: ", g_stochAtSellEntry, " + ", StochSLThreshold, " = ", g_stochAtSellEntry + StochSLThreshold);
            }
            else
               Print("SELL Close Failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
      }
   }
}
//+------------------------------------------------------------------+