//+------------------------------------------------------------------+
//|                                       Devilmod_MA_Crossover.mq5 |
//|                                      Based on Python Backtest    |
//|                              MACD Crossover with Trend Filter    |
//+------------------------------------------------------------------+
#property copyright "Devilmod 2026"
#property link ""
#property version "1.00"
#property description "MA Crossover Strategy - MACD histogram zero-line crossover"
#property description "with MA50/MA200 trend filter, ADX confirmation, and optional ROC momentum"
#property description "Optimized for XAUUSD M15 timeframe - Balanced Configuration"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// === Risk Management ===
input group "=== Risk Management ===" input double InpRiskPercent = 1.0; // Risk per trade (%)
input double InpRiskReward = 2.0;                                        // Risk:Reward ratio (1:X)
input double InpATRMultiplier = 1.8;                                     // ATR multiplier for SL

// === Filter Settings ===
input group "=== Filter Settings ===" input bool InpUseTrendFilter = true; // Use MA50/MA200 trend filter
input bool InpUseADXFilter = true;                                         // Use ADX strength filter
input double InpMinADX = 25.0;                                             // Minimum ADX value
input bool InpUseROCFilter = false;                                        // Use ROC momentum filter
input double InpROCThreshold = 0.1;                                        // ROC threshold (%)

// === Indicator Periods ===
input group "=== Indicator Periods ===" input int InpMAFastPeriod = 50; // MA Fast period
input int InpMASlowPeriod = 200;                                        // MA Slow period
input int InpMACDFast = 12;                                             // MACD Fast EMA
input int InpMACDSlow = 26;                                             // MACD Slow EMA
input int InpMACDSignal = 9;                                            // MACD Signal SMA
input int InpADXPeriod = 14;                                            // ADX period
input int InpATRPeriod = 14;                                            // ATR period
input int InpROCPeriod = 12;                                            // ROC period

// === Trading Time Filter ===
input group "=== Trading Time Filter ===" input bool InpUseTimeFilter = false; // Enable time filter
input int InpStartHour = 0;                                                    // Start hour (0-23)
input int InpEndHour = 23;                                                     // End hour (0-23)

// === Trade Management ===
input group "=== Trade Management ===" input int InpMagicNumber = 20260511; // Magic number
input string InpTradeComment = "MA_Cross";                                  // Trade comment prefix
input bool InpEnableNotifications = false;                                  // Enable push notifications
input int InpSlippage = 30;                                                 // Max slippage (points)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// Indicator handles
int handleMA50, handleMA200;
int handleMACD;
int handleADX;
int handleATR;

// Indicator buffers
double bufferMA50[], bufferMA200[];
double bufferMACDMain[], bufferMACDSignal[];
double bufferADXMain[];
double bufferATR[];

// ROC calculation buffer
double bufferClose[];

// Trade management
bool newBar = false;
datetime lastBarTime = 0;

// Position tracking
bool hasOpenPosition = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if (InpRiskPercent <= 0 || InpRiskPercent > 10)
   {
      Print("Error: Risk percent must be between 0 and 10");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpRiskReward <= 0)
   {
      Print("Error: Risk:Reward ratio must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpATRMultiplier <= 0)
   {
      Print("Error: ATR multiplier must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Create indicator handles
   handleMA50 = iMA(_Symbol, PERIOD_CURRENT, InpMAFastPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if (handleMA50 == INVALID_HANDLE)
   {
      Print("Error creating MA50 indicator: ", GetLastError());
      return INIT_FAILED;
   }

   handleMA200 = iMA(_Symbol, PERIOD_CURRENT, InpMASlowPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if (handleMA200 == INVALID_HANDLE)
   {
      Print("Error creating MA200 indicator: ", GetLastError());
      return INIT_FAILED;
   }

   handleMACD = iMACD(_Symbol, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   if (handleMACD == INVALID_HANDLE)
   {
      Print("Error creating MACD indicator: ", GetLastError());
      return INIT_FAILED;
   }

   handleADX = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   if (handleADX == INVALID_HANDLE)
   {
      Print("Error creating ADX indicator: ", GetLastError());
      return INIT_FAILED;
   }

   handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if (handleATR == INVALID_HANDLE)
   {
      Print("Error creating ATR indicator: ", GetLastError());
      return INIT_FAILED;
   }

   // Set buffer arrays as series
   ArraySetAsSeries(bufferMA50, true);
   ArraySetAsSeries(bufferMA200, true);
   ArraySetAsSeries(bufferMACDMain, true);
   ArraySetAsSeries(bufferMACDSignal, true);
   ArraySetAsSeries(bufferADXMain, true);
   ArraySetAsSeries(bufferATR, true);
   ArraySetAsSeries(bufferClose, true);

   Print("===========================================");
   Print("Devilmod MA Crossover EA initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Risk per trade: ", InpRiskPercent, "%");
   Print("Risk:Reward: 1:", InpRiskReward);
   Print("Filters: Trend=", InpUseTrendFilter, " ADX=", InpUseADXFilter, " ROC=", InpUseROCFilter);
   Print("===========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if (handleMA50 != INVALID_HANDLE)
      IndicatorRelease(handleMA50);
   if (handleMA200 != INVALID_HANDLE)
      IndicatorRelease(handleMA200);
   if (handleMACD != INVALID_HANDLE)
      IndicatorRelease(handleMACD);
   if (handleADX != INVALID_HANDLE)
      IndicatorRelease(handleADX);
   if (handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);

   Print("Devilmod MA Crossover EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if (!IsNewBar())
      return;

   // Check if already have open position
   if (HasOpenPosition())
   {
      hasOpenPosition = true;
      return; // Only one position at a time
   }
   else
   {
      hasOpenPosition = false;
   }

   // Check time filter
   if (InpUseTimeFilter && !IsValidTradingTime())
   {
      return;
   }

   // Copy indicator data
   if (!CopyIndicatorData())
   {
      Print("Error copying indicator data");
      return;
   }

   // Detect signal
   int signal = DetectSignal();

   if (signal == 1) // BUY signal
   {
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if (signal == -1) // SELL signal
   {
      OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   if (lastBarTime != currentBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if position already open                                   |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0)
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int currentHour = dt.hour;

   if (InpStartHour <= InpEndHour)
   {
      return (currentHour >= InpStartHour && currentHour <= InpEndHour);
   }
   else
   {
      // Handle overnight sessions (e.g., 22:00 to 02:00)
      return (currentHour >= InpStartHour || currentHour <= InpEndHour);
   }
}

//+------------------------------------------------------------------+
//| Copy indicator data to buffers                                   |
//+------------------------------------------------------------------+
bool CopyIndicatorData()
{
   // Copy MA data
   if (CopyBuffer(handleMA50, 0, 0, 3, bufferMA50) <= 0)
      return false;
   if (CopyBuffer(handleMA200, 0, 0, 3, bufferMA200) <= 0)
      return false;

   // Copy MACD data (Main line and Signal line)
   if (CopyBuffer(handleMACD, 0, 0, 3, bufferMACDMain) <= 0)
      return false;
   if (CopyBuffer(handleMACD, 1, 0, 3, bufferMACDSignal) <= 0)
      return false;

   // Copy ADX data
   if (CopyBuffer(handleADX, 0, 0, 3, bufferADXMain) <= 0)
      return false;

   // Copy ATR data
   if (CopyBuffer(handleATR, 0, 0, 3, bufferATR) <= 0)
      return false;

   // Copy close prices for ROC calculation
   if (InpUseROCFilter)
   {
      if (CopyClose(_Symbol, PERIOD_CURRENT, 0, InpROCPeriod + 3, bufferClose) <= 0)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate MACD Histogram                                         |
//+------------------------------------------------------------------+
double CalculateMACDHistogram(int shift)
{
   return bufferMACDMain[shift] - bufferMACDSignal[shift];
}

//+------------------------------------------------------------------+
//| Calculate ROC (Rate of Change)                                   |
//+------------------------------------------------------------------+
double CalculateROC(int shift)
{
   if (ArraySize(bufferClose) < InpROCPeriod + shift + 1)
      return 0.0;

   double currentClose = bufferClose[shift];
   double pastClose = bufferClose[shift + InpROCPeriod];

   if (pastClose == 0)
      return 0.0;

   return ((currentClose - pastClose) / pastClose) * 100.0;
}

//+------------------------------------------------------------------+
//| Detect MACD crossover signal                                     |
//+------------------------------------------------------------------+
int DetectSignal()
{
   // Calculate MACD histogram for current and previous bar
   double histogramCurrent = CalculateMACDHistogram(1);  // Bar 1 (completed bar)
   double histogramPrevious = CalculateMACDHistogram(2); // Bar 2

   int signal = 0;

   // Check for bullish crossover (histogram crosses above zero)
   if (histogramPrevious <= 0 && histogramCurrent > 0)
   {
      signal = 1; // BUY signal
   }
   // Check for bearish crossover (histogram crosses below zero)
   else if (histogramPrevious >= 0 && histogramCurrent < 0)
   {
      signal = -1; // SELL signal
   }

   if (signal == 0)
      return 0; // No signal

   // Apply filters
   if (!CheckTrendFilter(signal))
      return 0;
   if (!CheckADXFilter())
      return 0;
   if (!CheckROCFilter(signal))
      return 0;

   return signal;
}

//+------------------------------------------------------------------+
//| Check MA50/MA200 trend filter                                    |
//+------------------------------------------------------------------+
bool CheckTrendFilter(int signal)
{
   if (!InpUseTrendFilter)
      return true;

   double ma50 = bufferMA50[1];
   double ma200 = bufferMA200[1];

   // BUY signal requires uptrend (MA50 > MA200)
   if (signal == 1)
   {
      return (ma50 > ma200);
   }
   // SELL signal requires downtrend (MA50 < MA200)
   else if (signal == -1)
   {
      return (ma50 < ma200);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check ADX strength filter                                        |
//+------------------------------------------------------------------+
bool CheckADXFilter()
{
   if (!InpUseADXFilter)
      return true;

   double adx = bufferADXMain[1];

   return (adx >= InpMinADX);
}

//+------------------------------------------------------------------+
//| Check ROC momentum filter                                        |
//+------------------------------------------------------------------+
bool CheckROCFilter(int signal)
{
   if (!InpUseROCFilter)
      return true;

   double roc = CalculateROC(1);

   // BUY signal requires positive momentum
   if (signal == 1)
   {
      return (roc > InpROCThreshold);
   }
   // SELL signal requires negative momentum
   else if (signal == -1)
   {
      return (roc < -InpROCThreshold);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double slPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (InpRiskPercent / 100.0);

   double slDistance = MathAbs(entryPrice - slPrice);
   if (slDistance == 0)
      return 0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double slPips = slDistance / tickSize;
   double lotSize = riskAmount / (slPips * tickValue);

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(lotSize, maxLot));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate SL and TP levels                                       |
//+------------------------------------------------------------------+
void CalculateSLTP(ENUM_ORDER_TYPE orderType, double entryPrice, double &sl, double &tp)
{
   double atr = bufferATR[1];
   double slDistance = atr * InpATRMultiplier;

   if (orderType == ORDER_TYPE_BUY)
   {
      sl = entryPrice - slDistance;
      tp = entryPrice + (slDistance * InpRiskReward);
   }
   else // ORDER_TYPE_SELL
   {
      sl = entryPrice + slDistance;
      tp = entryPrice - (slDistance * InpRiskReward);
   }

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Calculate signal strength score                                  |
//+------------------------------------------------------------------+
double CalculateSignalStrength()
{
   double strength = 0.0;

   // Factor 1: MACD histogram strength (0-0.4)
   double histogram = CalculateMACDHistogram(1);
   double histScore = MathMin(MathAbs(histogram) / 2.0, 1.0) * 0.4;
   strength += histScore;

   // Factor 2: ADX strength (0-0.3)
   double adx = bufferADXMain[1];
   double adxScore = MathMin((adx - 20) / 30.0, 1.0) * 0.3;
   strength += MathMax(adxScore, 0);

   // Factor 3: Distance from MA50 (0-0.3) - closer is better
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ma50 = bufferMA50[1];
   double distancePct = MathAbs((close - ma50) / ma50) * 100.0;
   double maScore = MathMax(0.3 - (distancePct * 0.3), 0);
   strength += maScore;

   return MathMin(strength, 1.0);
}

//+------------------------------------------------------------------+
//| Open trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   // Get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? ask : bid;

   // Calculate SL and TP
   double sl, tp;
   CalculateSLTP(orderType, entryPrice, sl, tp);

   // Calculate position size
   double lotSize = CalculatePositionSize(entryPrice, sl);

   if (lotSize == 0)
   {
      Print("Error: Calculated lot size is zero");
      return;
   }

   // Calculate signal strength
   double signalStrength = CalculateSignalStrength();

   // Prepare trade comment
   string comment = StringFormat("%s|%s|ADX:%.1f|Str:%.2f",
                                 InpTradeComment,
                                 (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                                 bufferADXMain[1],
                                 signalStrength);

   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = entryPrice;
   request.sl = sl;
   request.tp = tp;
   request.deviation = InpSlippage;
   request.magic = InpMagicNumber;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;

   // Send order
   if (!OrderSend(request, result))
   {
      Print("OrderSend error: ", GetLastError());
      Print("Return code: ", result.retcode, " - ", result.comment);
      return;
   }

   if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("========================================");
      Print("TRADE OPENED: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
      Print("Ticket: ", result.order);
      Print("Entry: ", entryPrice);
      Print("SL: ", sl, " (", MathAbs(entryPrice - sl) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), " pips)");
      Print("TP: ", tp, " (", MathAbs(tp - entryPrice) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), " pips)");
      Print("Lot: ", lotSize);
      Print("Signal Strength: ", signalStrength);
      Print("========================================");

      // Send notification
      if (InpEnableNotifications)
      {
         string notification = StringFormat("Trade Opened: %s %s %.2f lots at %.2f",
                                            _Symbol,
                                            (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                                            lotSize,
                                            entryPrice);
         SendNotification(notification);
      }
   }
   else
   {
      Print("Trade failed. Return code: ", result.retcode, " - ", result.comment);
   }
}

//+------------------------------------------------------------------+
