//+------------------------------------------------------------------+
//|                                      StarCascadingSystem.mq5     |
//|                          Trading System based on Star Cascading   |
//|                            ADX Cross + Goldminer + MA Crossover   |
//+------------------------------------------------------------------+
#property copyright "Star Cascading Trading System"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== Trade Settings ==="
input double   LotSize          = 0.1;        // Lot Size
input int      StopLoss         = 2000;       // Stop Loss (points)
input int      TakeProfit       = 5000;       // Take Profit (points)
input int      MagicNumber      = 777777;     // Magic Number
input int      Slippage         = 3;          // Slippage (points)

input group "=== ADX Settings ==="
input int      ADX_Period       = 14;         // ADX Period
input int      ADX_Shift_M1    = 1;          // Shift for M1
input int      ADX_Shift_M5    = 3;          // Shift for M5
input int      ADX_Shift_M15   = 5;          // Shift for M15
input int      ADX_Shift_M30   = 10;         // Shift for M30
input int      ADX_Shift_H1    = 15;         // Shift for H1
input int      ADX_Shift_H4    = 20;         // Shift for H4
input int      ADX_Shift_D1    = 80;         // Shift for D1

input group "=== Goldminer Settings ==="
input int      SSP              = 7;          // Goldminer SSP Period
input double   Kmax             = 50.6;       // Goldminer Kmax

input group "=== MA Crossover Settings ==="
input int      MA_Fast_Period   = 5;          // Fast MA Period (Yellow)
input int      MA_Slow_Period   = 12;         // Slow MA Period (Blue)
input ENUM_MA_METHOD MA_Method  = MODE_EMA;   // MA Method

input group "=== Exit Settings ==="
input int      BreakevenTrigger = 500;        // Breakeven Trigger (points profit)
input bool     UseTrailingStop  = true;       // Use Trailing Stop
input int      TrailingStart    = 500;        // Trailing Start (points)
input int      TrailingStep     = 100;        // Trailing Step (points)

input group "=== Star Cascading Settings ==="
input int      StarLookback     = 5;          // Star Lookback Period
input double   StarThreshold    = 0.5;        // Star Threshold (0-1)

//--- Global Variables
CTrade trade;
CPositionInfo pos;

int adxHandle;
int maFastHandle;
int maSlowHandle;

double adxPlusDI[];
double adxMinusDI[];
double maFastBuffer[];
double maSlowBuffer[];

datetime lastBarTime = 0;
int adxShift = 10;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set magic number
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   // Create ADX handle
   adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   if(adxHandle == INVALID_HANDLE)
   {
      Print("Failed to create ADX handle");
      return(INIT_FAILED);
   }
   
   // Create MA handles
   maFastHandle = iMA(_Symbol, PERIOD_CURRENT, MA_Fast_Period, 0, MA_Method, PRICE_CLOSE);
   maSlowHandle = iMA(_Symbol, PERIOD_CURRENT, MA_Slow_Period, 0, MA_Method, PRICE_CLOSE);
   
   if(maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE)
   {
      Print("Failed to create MA handles");
      return(INIT_FAILED);
   }
   
   // Set ADX shift based on timeframe
   switch(_Period)
   {
      case PERIOD_M1:  adxShift = ADX_Shift_M1;  break;
      case PERIOD_M5:  adxShift = ADX_Shift_M5;  break;
      case PERIOD_M15: adxShift = ADX_Shift_M15; break;
      case PERIOD_M30: adxShift = ADX_Shift_M30; break;
      case PERIOD_H1:  adxShift = ADX_Shift_H1;  break;
      case PERIOD_H4:  adxShift = ADX_Shift_H4;  break;
      case PERIOD_D1:  adxShift = ADX_Shift_D1;  break;
      default:         adxShift = 10; break;
   }
   
   Print("Star Cascading System initialized on ", _Symbol, " ", EnumToString(_Period));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);
   if(maFastHandle != INVALID_HANDLE)
      IndicatorRelease(maFastHandle);
   if(maSlowHandle != INVALID_HANDLE)
      IndicatorRelease(maSlowHandle);
      
   Comment("");
}

//+------------------------------------------------------------------+
//| Check if new bar                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Goldminer level                                         |
//+------------------------------------------------------------------+
double CalcGoldminerLevel(int shift)
{
   int highestIdx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, SSP, shift);
   int lowestIdx  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, SSP, shift);
   
   double highest = iHigh(_Symbol, PERIOD_CURRENT, highestIdx);
   double lowest  = iLow(_Symbol, PERIOD_CURRENT, lowestIdx);
   
   double level = highest - (highest - lowest) * Kmax / 100.0;
   return level;
}

//+------------------------------------------------------------------+
//| Check Star Cascading condition                                    |
//+------------------------------------------------------------------+
// Returns: 1 = bullish stars, -1 = bearish stars, 0 = no stars
int CheckStarCascading()
{
   double currentClose = iClose(_Symbol, PERIOD_CURRENT, 0);
   double goldminerLevel = CalcGoldminerLevel(0);
   
   // Check consecutive bars above/below goldminer level
   int bullishCount = 0;
   int bearishCount = 0;
   
   for(int i = 0; i < StarLookback; i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      double level = CalcGoldminerLevel(i);
      
      if(close > level)
         bullishCount++;
      else if(close < level)
         bearishCount++;
   }
   
   // Stars cascading = consistent direction
   if(bullishCount >= StarLookback * StarThreshold)
      return 1;   // Bullish stars (blue stars)
   if(bearishCount >= StarLookback * StarThreshold)
      return -1;  // Bearish stars (red stars)
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check ADX Crossover signal                                        |
//+------------------------------------------------------------------+
// Returns: 1 = buy signal, -1 = sell signal, 0 = no signal
int CheckADXCross()
{
   double plusDI[], minusDI[];
   
   if(CopyBuffer(adxHandle, 1, 0, 3, plusDI) <= 0)
      return 0;
   if(CopyBuffer(adxHandle, 2, 0, 3, minusDI) <= 0)
      return 0;
   
   // Check crossover
   double prevPlusDI = plusDI[2];
   double prevMinusDI = minusDI[2];
   double currPlusDI = plusDI[1];
   double currMinusDI = minusDI[1];
   
   // Buy: +DI crosses above -DI
   if(prevPlusDI <= prevMinusDI && currPlusDI > currMinusDI)
      return 1;
   
   // Sell: -DI crosses above +DI
   if(prevPlusDI >= prevMinusDI && currPlusDI < currMinusDI)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check MA Crossover signal                                         |
//+------------------------------------------------------------------+
// Returns: 1 = buy crossover, -1 = sell crossover, 0 = no crossover
int CheckMACrossover()
{
   double fast[], slow[];
   
   if(CopyBuffer(maFastHandle, 0, 0, 3, fast) <= 0)
      return 0;
   if(CopyBuffer(maSlowHandle, 0, 0, 3, slow) <= 0)
      return 0;
   
   // Check crossover
   double prevFast = fast[2];
   double prevSlow = slow[2];
   double currFast = fast[1];
   double currSlow = slow[1];
   
   // Buy: fast crosses above slow (yellow crosses above blue)
   if(prevFast <= prevSlow && currFast > currSlow)
      return 1;
   
   // Sell: fast crosses below slow (yellow crosses below blue)
   if(prevFast >= prevSlow && currFast < currSlow)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check all 3 BUY conditions                                        |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
{
   int stars = CheckStarCascading();
   int adxSignal = CheckADXCross();
   int maSignal = CheckMACrossover();
   
   // Condition 1: Bullish star cascading
   if(stars != 1)
      return false;
   
   // Condition 2: ADX buy signal
   if(adxSignal != 1)
      return false;
   
   // Condition 3: MA crossover buy
   if(maSignal != 1)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check all 3 SELL conditions                                       |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
   int stars = CheckStarCascading();
   int adxSignal = CheckADXCross();
   int maSignal = CheckMACrossover();
   
   // Condition 1: Bearish star cascading
   if(stars != -1)
      return false;
   
   // Condition 2: ADX sell signal
   if(adxSignal != -1)
      return false;
   
   // Condition 3: MA crossover sell
   if(maSignal != -1)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if opposite signal appeared (exit condition)                |
//+------------------------------------------------------------------+
bool CheckOppositeSignal(ENUM_POSITION_TYPE posType)
{
   int stars = CheckStarCascading();
   int adxSignal = CheckADXCross();
   int maSignal = CheckMACrossover();
   
   if(posType == POSITION_TYPE_BUY)
   {
      // Exit buy if sell conditions appear
      if(stars == -1 || adxSignal == -1 || maSignal == -1)
         return true;
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      // Exit sell if buy conditions appear
      if(stars == 1 || adxSignal == 1 || maSignal == 1)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get minimum stop distance                                          |
//+------------------------------------------------------------------+
int GetMinStopDistance()
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   
   int minDistance = MathMax(stopsLevel, freezeLevel);
   
   // For Gold (XAUUSD), ensure minimum distance is reasonable
   // Exness typically requires 200-500 points for Gold
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
   {
      minDistance = MathMax(minDistance, 500); // Minimum 500 points (0.50 price) for Gold
   }
   else
   {
      minDistance = MathMax(minDistance, 50); // Minimum 50 points for other symbols
   }
   
   return minDistance;
}

//+------------------------------------------------------------------+
//| Normalize stop price                                               |
//+------------------------------------------------------------------+
double NormalizeStop(double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                 |
//+------------------------------------------------------------------+
double CalcLotSize()
{
   return NormalizeDouble(LotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage open positions (breakeven & trailing)                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i))
         continue;
      if(pos.Magic() != MagicNumber)
         continue;
      if(pos.Symbol() != _Symbol)
         continue;
      
      double openPrice = pos.PriceOpen();
      double currentSL = pos.StopLoss();
      double currentTP = pos.TakeProfit();
      double currentPrice = pos.PriceCurrent();
      
      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         double profitPoints = (currentPrice - openPrice) / _Point;
         
         // Breakeven
         if(profitPoints >= BreakevenTrigger && currentSL < openPrice)
         {
            double newSL = openPrice + _Point * 10; // Small buffer above entry
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
         }
         
         // Trailing Stop
         if(UseTrailingStop && profitPoints >= TrailingStart)
         {
            double newSL = currentPrice - TrailingStep * _Point;
            if(newSL > currentSL && newSL > openPrice)
            {
               trade.PositionModify(pos.Ticket(), newSL, currentTP);
            }
         }
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         double profitPoints = (openPrice - currentPrice) / _Point;
         
         // Breakeven
         if(profitPoints >= BreakevenTrigger && (currentSL > openPrice || currentSL == 0))
         {
            double newSL = openPrice - _Point * 10; // Small buffer below entry
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
         }
         
         // Trailing Stop
         if(UseTrailingStop && profitPoints >= TrailingStart)
         {
            double newSL = currentPrice + TrailingStep * _Point;
            if(newSL < currentSL || currentSL == 0)
            {
               trade.PositionModify(pos.Ticket(), newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i))
         continue;
      if(pos.Magic() != MagicNumber)
         continue;
      if(pos.Symbol() != _Symbol)
         continue;
      if(pos.PositionType() == posType)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Display dashboard info                                             |
//+------------------------------------------------------------------+
void DisplayDashboard()
{
   int stars = CheckStarCascading();
   int adxSignal = CheckADXCross();
   int maSignal = CheckMACrossover();
   
   string starText = "NONE";
   if(stars == 1) starText = "BULLISH (Blue)";
   else if(stars == -1) starText = "BEARISH (Red)";
   
   string adxText = "NONE";
   if(adxSignal == 1) adxText = "BUY";
   else if(adxSignal == -1) adxText = "SELL";
   
   string maText = "NONE";
   if(maSignal == 1) maText = "BUY (Cross Up)";
   else if(maSignal == -1) maText = "SELL (Cross Down)";
   
   string buyText = CheckBuyConditions() ? ">>> ACTIVE <<<" : "Waiting...";
   string sellText = CheckSellConditions() ? ">>> ACTIVE <<<" : "Waiting...";
   
   Comment(
      "\n===== STAR CASCADING SYSTEM =====\n",
      "\n--- Conditions ---\n",
      "1. Star Cascading: ", starText, "\n",
      "2. ADX Signal:     ", adxText, "\n",
      "3. MA Crossover:   ", maText, "\n",
      "\n--- Entry Signals ---\n",
      "BUY Signal:  ", buyText, "\n",
      "SELL Signal: ", sellText, "\n",
      "\n--- Positions ---\n",
      "Open BUY:  ", CountPositions(POSITION_TYPE_BUY), "\n",
      "Open SELL: ", CountPositions(POSITION_TYPE_SELL), "\n",
      "-----------------------------------\n"
   );
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage existing positions
   ManagePositions();
   
   // Only trade on new bar
   if(!IsNewBar())
      return;
   
   // Check if trading is allowed
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;
   
   // Display dashboard
   DisplayDashboard();
   
   // Check for exit signals first
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i))
         continue;
      if(pos.Magic() != MagicNumber)
         continue;
      if(pos.Symbol() != _Symbol)
         continue;
      
      // Check opposite signal for exit
      if(CheckOppositeSignal(pos.PositionType()))
      {
         trade.PositionClose(pos.Ticket());
         Print("Closed position due to opposite signal");
      }
   }
   
   // Check for new entry signals
   bool buySignal = CheckBuyConditions();
   bool sellSignal = CheckSellConditions();
   
   // Open BUY
   if(buySignal && CountPositions(POSITION_TYPE_BUY) == 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int minDist = GetMinStopDistance();
      
      double sl = (StopLoss > 0) ? ask - StopLoss * _Point : 0;
      double tp = (TakeProfit > 0) ? ask + TakeProfit * _Point : 0;
      
      // Ensure SL is at least minDist points away
      if(StopLoss > 0 && (ask - sl) < minDist * _Point)
         sl = ask - minDist * _Point;
      
      // Ensure TP is at least minDist points away
      if(TakeProfit > 0 && (tp - ask) < minDist * _Point)
         tp = ask + minDist * _Point;
      
      sl = NormalizeStop(sl);
      tp = NormalizeStop(tp);
      
      Print("BUY Signal: ask=", ask, " sl=", sl, " tp=", tp, " minDist=", minDist);
      
      if(trade.Buy(CalcLotSize(), _Symbol, ask, sl, tp, "StarCascading BUY"))
      {
         Print("BUY order opened at ", ask, " SL=", sl, " TP=", tp);
      }
      else
      {
         Print("BUY order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      }
   }
   
   // Open SELL
   if(sellSignal && CountPositions(POSITION_TYPE_SELL) == 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int minDist = GetMinStopDistance();
      
      double sl = (StopLoss > 0) ? bid + StopLoss * _Point : 0;
      double tp = (TakeProfit > 0) ? bid - TakeProfit * _Point : 0;
      
      // Ensure SL is at least minDist points away
      if(StopLoss > 0 && (sl - bid) < minDist * _Point)
         sl = bid + minDist * _Point;
      
      // Ensure TP is at least minDist points away
      if(TakeProfit > 0 && (bid - tp) < minDist * _Point)
         tp = bid - minDist * _Point;
      
      sl = NormalizeStop(sl);
      tp = NormalizeStop(tp);
      
      Print("SELL Signal: bid=", bid, " sl=", sl, " tp=", tp, " minDist=", minDist);
      
      if(trade.Sell(CalcLotSize(), _Symbol, bid, sl, tp, "StarCascading SELL"))
      {
         Print("SELL order opened at ", bid, " SL=", sl, " TP=", tp);
      }
      else
      {
         Print("SELL order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      }
   }
}
//+------------------------------------------------------------------+
