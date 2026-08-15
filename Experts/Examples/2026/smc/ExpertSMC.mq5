//+------------------------------------------------------------------+
//|                                                    ExpertSMC.mq5 |
//|                                      Smart Money Concept EA      |
//|                          Based on 8-Core SMC Logic               |
//+------------------------------------------------------------------+
#property copyright "SMC EA 2026"
#property version   "1.00"
#property description "Smart Money Concept Expert Advisor"
#property description "Market Structure | Liquidity | BOS/CHOCH | Order Block"
#property description "FVG | Premium/Discount | Multi-Timeframe Analysis"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STRUCTURE
{
   STRUCTURE_UPTREND,      // Uptrend (HH/HL)
   STRUCTURE_DOWNTREND,    // Downtrend (LL/LH)
   STRUCTURE_RANGING       // Ranging/Sideways
};

enum ENUM_OB_TYPE
{
   OB_BULLISH,            // Bullish Order Block
   OB_BEARISH             // Bearish Order Block
};

enum ENUM_FVG_TYPE
{
   FVG_BULLISH,           // Bullish Fair Value Gap
   FVG_BEARISH            // Bearish Fair Value Gap
};

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SwingPoint
{
   datetime time;
   double price;
   int barIndex;
   bool isValid;
};

struct OrderBlock
{
   datetime time;
   double highPrice;
   double lowPrice;
   ENUM_OB_TYPE type;
   ENUM_TIMEFRAMES timeframe;
   bool isUsed;
   bool isValid;
};

struct FairValueGap
{
   datetime time;
   double topPrice;
   double bottomPrice;
   ENUM_FVG_TYPE type;
   bool isFilled;
   bool isValid;
};

struct LiquidityZone
{
   datetime time;
   double price;
   bool isSwept;
   bool isValid;
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//--- Timeframe Settings
input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES HTF_Timeframe = PERIOD_H1;          // Higher Timeframe (Structure)
input ENUM_TIMEFRAMES Entry_Timeframe = PERIOD_M15;       // Entry Timeframe
input ENUM_TIMEFRAMES Confirm_Timeframe = PERIOD_M5;      // Confirmation Timeframe

//--- Market Structure Settings
input group "=== Market Structure Settings ==="
input int SwingStrength = 3;                              // Swing Detection Strength (1-5)
input int LookbackBars = 200;                             // Lookback Period (bars)
input double StructureBuffer = 0.0002;                    // Structure Break Buffer (%)

//--- Liquidity Settings
input group "=== Liquidity Settings ==="
input int LiquidityLookback = 100;                        // Liquidity Lookback (bars)
input double LiquiditySweepBuffer = 10;                   // Sweep Buffer (pips)
input bool TrackMultipleLiquidity = true;                 // Track Multiple Liquidity Zones

//--- Order Block Settings
input group "=== Order Block Settings ==="
input double OB_RetestTolerance = 50.0;                   // OB Retest Tolerance (%)
input int OB_MaxAge = 50;                                 // Max OB Age (bars)
input bool OB_RequireImbalance = true;                    // Require Imbalance Before OB
input double OB_MinImpulseSize = 50;                      // Min Impulse Size (pips)

//--- Fair Value Gap Settings
input group "=== Fair Value Gap Settings ==="
input double FVG_MinGapSize = 5;                          // Min FVG Size (pips)
input bool FVG_AllowPartialFill = true;                   // Allow Partial Fill
input int FVG_MaxAge = 30;                                // Max FVG Age (bars)

//--- Premium/Discount Settings
input group "=== Premium/Discount Settings ==="
input bool UseFiboFilter = true;                          // Use Fibo Premium/Discount Filter
input double EquilibriumTolerance = 5.0;                  // Equilibrium Zone Tolerance (%)

//--- Trading Formula Settings
input group "=== Trading Formula Settings ==="
input bool UseFormula1 = true;                            // Formula 1: Liquidity Sweep + CHOCH + OB
input bool UseFormula2 = false;                           // Formula 2: BOS Continuation
input bool UseFormula3 = false;                           // Formula 3: London Kill Zone Filter
input bool UseSimplifiedMode = true;                      // Simplified Test Mode (easier entry)
input bool Formula1_RequireSweep = false;                 // Formula 1: Require Liquidity Sweep
input bool Formula1_RequireCHOCH = false;                 // Formula 1: Require CHOCH

//--- London Kill Zone Settings
input group "=== London Kill Zone Settings ==="
input bool UseLondonKillZone = false;                     // Use London Kill Zone (auto for XAU/GBP)
input int LondonStartHour = 2;                            // London Start Hour (GMT)
input int LondonEndHour = 5;                              // London End Hour (GMT)
input int NYStartHour = 13;                               // NY Start Hour (GMT)
input int NYEndHour = 16;                                 // NY End Hour (GMT)

//--- Entry Confirmation Settings
input group "=== Entry Confirmation Settings ==="
input bool RequireEngulfing = false;                      // Require Engulfing Pattern
input bool RequireMiniBOS = true;                         // Require Mini-BOS on Confirm TF
input int MinADX = 20;                                    // Minimum ADX for Entry
input bool UseSpreadFilter = true;                        // Use Spread Filter
input int MaxSpread = 30;                                 // Max Spread (pips)

//--- Risk Management Settings
input group "=== Risk Management Settings ==="
input double RiskPercent = 2.0;                           // Risk per Trade (%)
input double RR_Ratio = 2.0;                              // Risk:Reward Ratio (1:X)
input bool UseCompounding = true;                         // Use Compound Interest
input double MinLotSize = 0.01;                           // Minimum Lot Size
input double MaxLotSize = 10.0;                           // Maximum Lot Size
input int MaxPositions = 1;                               // Max Positions per Symbol

//--- General Settings
input group "=== General Settings ==="
input int MagicNumber = 100100;                           // Magic Number
input string TradeComment = "SMC_EA";                     // Trade Comment
input int Slippage = 30;                                  // Slippage (points)
input bool ShowVisualAids = false;                        // Show Visual Aids on Chart
input bool EnableDebugLog = true;                         // Enable Detailed Debug Logging

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CAccountInfo account;

// Indicator Handles
int handleATR_HTF;
int handleADX_HTF;
int handleATR_Entry;
int handleADX_Entry;

// Indicator Buffers
double atrBuffer_HTF[];
double adxBuffer_HTF[];
double atrBuffer_Entry[];
double adxBuffer_Entry[];

// Market Structure Arrays
SwingPoint swingHighs_HTF[];
SwingPoint swingLows_HTF[];
SwingPoint swingHighs_Entry[];
SwingPoint swingLows_Entry[];
ENUM_MARKET_STRUCTURE currentStructure_HTF = STRUCTURE_RANGING;
ENUM_MARKET_STRUCTURE currentStructure_Entry = STRUCTURE_RANGING;

// Liquidity Arrays
LiquidityZone bslZones[];  // Buy Side Liquidity
LiquidityZone sslZones[];  // Sell Side Liquidity

// Order Block Arrays
OrderBlock orderBlocks[];
int maxOrderBlocks = 20;

// Fair Value Gap Arrays
FairValueGap fvgZones[];
int maxFVGs = 30;

// Premium/Discount Levels
double currentPremiumLevel = 0;
double currentDiscountLevel = 0;
double currentEquilibrium = 0;
double swingHigh_Fibo = 0;
double swingLow_Fibo = 0;

// BOS/CHOCH Detection
datetime lastBOS_Time = 0;
double lastBOS_Price = 0;
datetime lastCHOCH_Time = 0;
double lastCHOCH_Price = 0;
bool isBullishBOS = false;
bool isBearishBOS = false;
bool isBullishCHOCH = false;
bool isBearishCHOCH = false;

// Trading State
datetime lastBarTime_HTF = 0;
datetime lastBarTime_Entry = 0;
datetime lastTradeTime = 0;
bool enableKillZoneFilter = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Setup trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   //--- Initialize indicator handles
   handleATR_HTF = iATR(_Symbol, HTF_Timeframe, 14);
   handleADX_HTF = iADX(_Symbol, HTF_Timeframe, 14);
   handleATR_Entry = iATR(_Symbol, Entry_Timeframe, 14);
   handleADX_Entry = iADX(_Symbol, Entry_Timeframe, 14);
   
   if(handleATR_HTF == INVALID_HANDLE || handleADX_HTF == INVALID_HANDLE ||
      handleATR_Entry == INVALID_HANDLE || handleADX_Entry == INVALID_HANDLE)
   {
      Print("Error initializing indicators!");
      return INIT_FAILED;
   }
   
   //--- Set arrays as series
   ArraySetAsSeries(atrBuffer_HTF, true);
   ArraySetAsSeries(adxBuffer_HTF, true);
   ArraySetAsSeries(atrBuffer_Entry, true);
   ArraySetAsSeries(adxBuffer_Entry, true);
   
   //--- Initialize arrays
   ArrayResize(swingHighs_HTF, 0);
   ArrayResize(swingLows_HTF, 0);
   ArrayResize(swingHighs_Entry, 0);
   ArrayResize(swingLows_Entry, 0);
   ArrayResize(bslZones, 0);
   ArrayResize(sslZones, 0);
   ArrayResize(orderBlocks, maxOrderBlocks);
   ArrayResize(fvgZones, maxFVGs);
   
   //--- Initialize Order Blocks
   for(int i = 0; i < maxOrderBlocks; i++)
   {
      orderBlocks[i].isValid = false;
      orderBlocks[i].isUsed = false;
   }
   
   //--- Initialize FVGs
   for(int i = 0; i < maxFVGs; i++)
   {
      fvgZones[i].isValid = false;
      fvgZones[i].isFilled = false;
   }
   
   //--- Check London Kill Zone auto-enable
   if(UseLondonKillZone || 
      StringFind(_Symbol, "XAU") >= 0 || 
      StringFind(_Symbol, "GBP") >= 0)
   {
      enableKillZoneFilter = true;
      Print("London Kill Zone Filter: ENABLED (Auto-detected for ", _Symbol, ")");
   }
   
   //--- Print initialization info
   Print("========================================");
   Print("SMC Expert Advisor Initialized");
   Print("========================================");
   Print("Symbol: ", _Symbol);
   Print("HTF: ", EnumToString(HTF_Timeframe));
   Print("Entry TF: ", EnumToString(Entry_Timeframe));
   Print("Confirm TF: ", EnumToString(Confirm_Timeframe));
   Print("Risk: ", RiskPercent, "% | RR: 1:", RR_Ratio);
   Print("Formula 1 (Sweep+CHOCH+OB): ", UseFormula1 ? "ON" : "OFF");
   Print("  - Require Sweep: ", Formula1_RequireSweep ? "YES" : "NO");
   Print("  - Require CHOCH: ", Formula1_RequireCHOCH ? "YES" : "NO");
   Print("Formula 2 (BOS Continuation): ", UseFormula2 ? "ON" : "OFF");
   Print("Formula 3 (Kill Zone): ", UseFormula3 ? "ON" : "OFF");
   Print("Kill Zone Filter: ", enableKillZoneFilter ? "ACTIVE" : "OFF");
   Print("Simplified Test Mode: ", UseSimplifiedMode ? "ON" : "OFF");
   Print("Debug Logging: ", EnableDebugLog ? "ON" : "OFF");
   Print("Visual Aids: ", ShowVisualAids ? "ON" : "OFF");
   Print("========================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleATR_HTF);
   IndicatorRelease(handleADX_HTF);
   IndicatorRelease(handleATR_Entry);
   IndicatorRelease(handleADX_Entry);
   
   //--- Remove visual objects if any
   if(ShowVisualAids)
   {
      ObjectsDeleteAll(0, "SMC_");
   }
   
   Print("SMC EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar on HTF
   datetime currentBarTime_HTF = iTime(_Symbol, HTF_Timeframe, 0);
   bool newBar_HTF = (currentBarTime_HTF != lastBarTime_HTF);
   
   //--- Check for new bar on Entry TF
   datetime currentBarTime_Entry = iTime(_Symbol, Entry_Timeframe, 0);
   bool newBar_Entry = (currentBarTime_Entry != lastBarTime_Entry);
   
   //--- Update indicators
   if(!UpdateIndicators())
      return;
   
   //--- On new HTF bar: Update market structure
   if(newBar_HTF)
   {
      lastBarTime_HTF = currentBarTime_HTF;
      
      if(EnableDebugLog)
         Print("[HTF] New bar detected: ", currentBarTime_HTF);
      
      // Update swing points
      FindSwingHighs(HTF_Timeframe, swingHighs_HTF);
      FindSwingLows(HTF_Timeframe, swingLows_HTF);
      
      if(EnableDebugLog)
         Print("[HTF] Swing Highs: ", ArraySize(swingHighs_HTF), " | Swing Lows: ", ArraySize(swingLows_HTF));
      
      // Detect market structure
      DetectMarketStructure(HTF_Timeframe, swingHighs_HTF, swingLows_HTF, currentStructure_HTF);
      
      if(EnableDebugLog)
      {
         string structureStr = "RANGING";
         if(currentStructure_HTF == STRUCTURE_UPTREND) structureStr = "UPTREND";
         else if(currentStructure_HTF == STRUCTURE_DOWNTREND) structureStr = "DOWNTREND";
         Print("[HTF] Market Structure: ", structureStr);
      }
      
      // Update liquidity zones
      UpdateLiquidityZones(HTF_Timeframe);
      
      if(EnableDebugLog)
         Print("[HTF] BSL Zones: ", ArraySize(bslZones), " | SSL Zones: ", ArraySize(sslZones));
      
      // Detect BOS/CHOCH
      DetectBOS_CHOCH(HTF_Timeframe);
      
      if(EnableDebugLog && (isBullishBOS || isBearishBOS || isBullishCHOCH || isBearishCHOCH))
      {
         if(isBullishBOS) Print("[HTF] ✓ Bullish BOS detected at ", lastBOS_Price);
         if(isBearishBOS) Print("[HTF] ✓ Bearish BOS detected at ", lastBOS_Price);
         if(isBullishCHOCH) Print("[HTF] ✓ Bullish CHOCH detected at ", lastCHOCH_Price);
         if(isBearishCHOCH) Print("[HTF] ✓ Bearish CHOCH detected at ", lastCHOCH_Price);
      }
      
      // Find Order Blocks
      FindOrderBlocks(HTF_Timeframe);
      
      int validOBs = 0;
      for(int i = 0; i < maxOrderBlocks; i++)
         if(orderBlocks[i].isValid && !orderBlocks[i].isUsed) validOBs++;
      
      if(EnableDebugLog)
         Print("[HTF] Valid Order Blocks: ", validOBs);
      
      // Calculate Premium/Discount zones
      CalculateFiboZones(HTF_Timeframe);
      
      if(EnableDebugLog)
         Print("[HTF] Fibo Levels - Premium: ", currentPremiumLevel, " | EQ: ", currentEquilibrium, " | Discount: ", currentDiscountLevel);
      
      // Detect FVGs
      DetectFVG(HTF_Timeframe);
      
      int validFVGs = 0;
      for(int i = 0; i < maxFVGs; i++)
         if(fvgZones[i].isValid && !fvgZones[i].isFilled) validFVGs++;
      
      if(EnableDebugLog)
         Print("[HTF] Valid FVGs: ", validFVGs);
      
      // Update visual aids
      if(ShowVisualAids)
      {
         DrawVisualAids();
      }
   }
   
   //--- On new Entry TF bar: Check for signals
   if(newBar_Entry)
   {
      lastBarTime_Entry = currentBarTime_Entry;
      
      if(EnableDebugLog)
         Print("[ENTRY] New bar detected: ", currentBarTime_Entry);
      
      // Update entry timeframe structure
      FindSwingHighs(Entry_Timeframe, swingHighs_Entry);
      FindSwingLows(Entry_Timeframe, swingLows_Entry);
      DetectMarketStructure(Entry_Timeframe, swingHighs_Entry, swingLows_Entry, currentStructure_Entry);
      
      // Check if we can trade (position limits)
      int currentPositions = CountPositions();
      if(currentPositions >= MaxPositions)
      {
         if(EnableDebugLog)
            Print("[ENTRY] ✗ Max positions reached: ", currentPositions, "/", MaxPositions);
         return;
      }
      
      // Check kill zone filter
      if(enableKillZoneFilter && UseFormula3)
      {
         if(!IsInKillZone())
         {
            if(EnableDebugLog)
               Print("[ENTRY] ✗ Outside Kill Zone");
            return;
         }
         else if(EnableDebugLog)
         {
            Print("[ENTRY] ✓ Inside Kill Zone");
         }
      }
      
      if(EnableDebugLog)
         Print("[ENTRY] Checking for trading signals...");
      
      // Check for trading signals
      CheckSMCSignals();
   }
   
   //--- Manage existing positions
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(handleATR_HTF, 0, 0, 3, atrBuffer_HTF) <= 0)
      return false;
   if(CopyBuffer(handleADX_HTF, 0, 0, 3, adxBuffer_HTF) <= 0)
      return false;
   if(CopyBuffer(handleATR_Entry, 0, 0, 3, atrBuffer_Entry) <= 0)
      return false;
   if(CopyBuffer(handleADX_Entry, 0, 0, 3, adxBuffer_Entry) <= 0)
      return false;
      
   return true;
}

//+------------------------------------------------------------------+
//| Find swing highs on specified timeframe                          |
//+------------------------------------------------------------------+
void FindSwingHighs(ENUM_TIMEFRAMES timeframe, SwingPoint &swings[])
{
   ArrayResize(swings, 0);
   
   int startBar = SwingStrength;
   int endBar = MathMin(LookbackBars, iBars(_Symbol, timeframe) - SwingStrength);
   
   for(int i = startBar; i < endBar; i++)
   {
      double high_i = iHigh(_Symbol, timeframe, i);
      bool isSwingHigh = true;
      
      // Check left side
      for(int j = 1; j <= SwingStrength; j++)
      {
         double high_left = iHigh(_Symbol, timeframe, i - j);
         if(high_i <= high_left)
         {
            isSwingHigh = false;
            break;
         }
      }
      
      // Check right side
      if(isSwingHigh)
      {
         for(int j = 1; j <= SwingStrength; j++)
         {
            double high_right = iHigh(_Symbol, timeframe, i + j);
            if(high_i <= high_right)
            {
               isSwingHigh = false;
               break;
            }
         }
      }
      
      // Add swing high
      if(isSwingHigh)
      {
         int newSize = ArraySize(swings) + 1;
         ArrayResize(swings, newSize);
         swings[newSize - 1].time = iTime(_Symbol, timeframe, i);
         swings[newSize - 1].price = high_i;
         swings[newSize - 1].barIndex = i;
         swings[newSize - 1].isValid = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Find swing lows on specified timeframe                           |
//+------------------------------------------------------------------+
void FindSwingLows(ENUM_TIMEFRAMES timeframe, SwingPoint &swings[])
{
   ArrayResize(swings, 0);
   
   int startBar = SwingStrength;
   int endBar = MathMin(LookbackBars, iBars(_Symbol, timeframe) - SwingStrength);
   
   for(int i = startBar; i < endBar; i++)
   {
      double low_i = iLow(_Symbol, timeframe, i);
      bool isSwingLow = true;
      
      // Check left side
      for(int j = 1; j <= SwingStrength; j++)
      {
         double low_left = iLow(_Symbol, timeframe, i - j);
         if(low_i >= low_left)
         {
            isSwingLow = false;
            break;
         }
      }
      
      // Check right side
      if(isSwingLow)
      {
         for(int j = 1; j <= SwingStrength; j++)
         {
            double low_right = iLow(_Symbol, timeframe, i + j);
            if(low_i >= low_right)
            {
               isSwingLow = false;
               break;
            }
         }
      }
      
      // Add swing low
      if(isSwingLow)
      {
         int newSize = ArraySize(swings) + 1;
         ArrayResize(swings, newSize);
         swings[newSize - 1].time = iTime(_Symbol, timeframe, i);
         swings[newSize - 1].price = low_i;
         swings[newSize - 1].barIndex = i;
         swings[newSize - 1].isValid = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect market structure (HH/HL or LL/LH)                         |
//+------------------------------------------------------------------+
void DetectMarketStructure(ENUM_TIMEFRAMES timeframe, SwingPoint &highs[], SwingPoint &lows[], ENUM_MARKET_STRUCTURE &structure)
{
   int highCount = ArraySize(highs);
   int lowCount = ArraySize(lows);
   
   if(highCount < 2 || lowCount < 2)
   {
      structure = STRUCTURE_RANGING;
      return;
   }
   
   // Check for Higher Highs and Higher Lows (Uptrend)
   bool hasHH = false;
   bool hasHL = false;
   
   if(highs[0].price > highs[1].price)
      hasHH = true;
   if(lows[0].price > lows[1].price)
      hasHL = true;
   
   // Check for Lower Lows and Lower Highs (Downtrend)
   bool hasLL = false;
   bool hasLH = false;
   
   if(lows[0].price < lows[1].price)
      hasLL = true;
   if(highs[0].price < highs[1].price)
      hasLH = true;
   
   // Determine structure
   if(hasHH && hasHL)
      structure = STRUCTURE_UPTREND;
   else if(hasLL && hasLH)
      structure = STRUCTURE_DOWNTREND;
   else
      structure = STRUCTURE_RANGING;
}

//+------------------------------------------------------------------+
//| Update liquidity zones (BSL/SSL)                                 |
//+------------------------------------------------------------------+
void UpdateLiquidityZones(ENUM_TIMEFRAMES timeframe)
{
   // Clear old zones
   ArrayResize(bslZones, 0);
   ArrayResize(sslZones, 0);
   
   // Get recent swing highs for BSL (Buy Side Liquidity)
   int limit = TrackMultipleLiquidity ? MathMin(5, ArraySize(swingHighs_HTF)) : MathMin(1, ArraySize(swingHighs_HTF));
   for(int i = 0; i < limit; i++)
   {
      if(swingHighs_HTF[i].isValid)
      {
         int newSize = ArraySize(bslZones) + 1;
         ArrayResize(bslZones, newSize);
         bslZones[newSize - 1].time = swingHighs_HTF[i].time;
         bslZones[newSize - 1].price = swingHighs_HTF[i].price;
         bslZones[newSize - 1].isSwept = false;
         bslZones[newSize - 1].isValid = true;
      }
   }
   
   // Get recent swing lows for SSL (Sell Side Liquidity)
   limit = TrackMultipleLiquidity ? MathMin(5, ArraySize(swingLows_HTF)) : MathMin(1, ArraySize(swingLows_HTF));
   for(int i = 0; i < limit; i++)
   {
      if(swingLows_HTF[i].isValid)
      {
         int newSize = ArraySize(sslZones) + 1;
         ArrayResize(sslZones, newSize);
         sslZones[newSize - 1].time = swingLows_HTF[i].time;
         sslZones[newSize - 1].price = swingLows_HTF[i].price;
         sslZones[newSize - 1].isSwept = false;
         sslZones[newSize - 1].isValid = true;
      }
   }
   
   // Check if liquidity has been swept
   double currentHigh = iHigh(_Symbol, timeframe, 0);
   double currentLow = iLow(_Symbol, timeframe, 0);
   double sweepBuffer = LiquiditySweepBuffer * _Point * 10; // Convert pips to price
   
   for(int i = 0; i < ArraySize(bslZones); i++)
   {
      if(currentHigh >= bslZones[i].price + sweepBuffer)
         bslZones[i].isSwept = true;
   }
   
   for(int i = 0; i < ArraySize(sslZones); i++)
   {
      if(currentLow <= sslZones[i].price - sweepBuffer)
         sslZones[i].isSwept = true;
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS) and Change of Character (CHOCH)  |
//+------------------------------------------------------------------+
void DetectBOS_CHOCH(ENUM_TIMEFRAMES timeframe)
{
   // Reset flags
   isBullishBOS = false;
   isBearishBOS = false;
   isBullishCHOCH = false;
   isBearishCHOCH = false;
   
   int highCount = ArraySize(swingHighs_HTF);
   int lowCount = ArraySize(swingLows_HTF);
   
   if(highCount < 2 || lowCount < 2)
      return;
   
   double currentHigh = iHigh(_Symbol, timeframe, 0);
   double currentLow = iLow(_Symbol, timeframe, 0);
   
   // BOS Detection (continuation of trend)
   if(currentStructure_HTF == STRUCTURE_UPTREND)
   {
      // Bullish BOS: Break above previous HH
      if(currentHigh > swingHighs_HTF[0].price)
      {
         isBullishBOS = true;
         lastBOS_Time = iTime(_Symbol, timeframe, 0);
         lastBOS_Price = currentHigh;
      }
   }
   else if(currentStructure_HTF == STRUCTURE_DOWNTREND)
   {
      // Bearish BOS: Break below previous LL
      if(currentLow < swingLows_HTF[0].price)
      {
         isBearishBOS = true;
         lastBOS_Time = iTime(_Symbol, timeframe, 0);
         lastBOS_Price = currentLow;
      }
   }
   
   // CHOCH Detection (reversal signal)
   if(currentStructure_HTF == STRUCTURE_DOWNTREND)
   {
      // Bullish CHOCH: Break above previous LH (swing high in downtrend)
      if(currentHigh > swingHighs_HTF[0].price)
      {
         isBullishCHOCH = true;
         lastCHOCH_Time = iTime(_Symbol, timeframe, 0);
         lastCHOCH_Price = currentHigh;
      }
   }
   else if(currentStructure_HTF == STRUCTURE_UPTREND)
   {
      // Bearish CHOCH: Break below previous HL (swing low in uptrend)
      if(currentLow < swingLows_HTF[0].price)
      {
         isBearishCHOCH = true;
         lastCHOCH_Time = iTime(_Symbol, timeframe, 0);
         lastCHOCH_Price = currentLow;
      }
   }
}

//+------------------------------------------------------------------+
//| Find Order Blocks                                                 |
//+------------------------------------------------------------------+
void FindOrderBlocks(ENUM_TIMEFRAMES timeframe)
{
   // Invalidate old order blocks
   for(int i = 0; i < maxOrderBlocks; i++)
   {
      if(orderBlocks[i].isValid)
      {
         int barsAge = iBarShift(_Symbol, timeframe, orderBlocks[i].time);
         if(barsAge > OB_MaxAge)
            orderBlocks[i].isValid = false;
      }
   }
   
   // Look for new order blocks after CHOCH
   if(isBullishCHOCH)
   {
      // Find bullish OB: Last bearish candle before bullish impulse
      for(int i = 1; i < 20; i++)
      {
         double open = iOpen(_Symbol, timeframe, i);
         double close = iClose(_Symbol, timeframe, i);
         double high = iHigh(_Symbol, timeframe, i);
         double low = iLow(_Symbol, timeframe, i);
         
         // Check if bearish candle
         if(close < open)
         {
            // Check if followed by bullish impulse
            double impulseSize = 0;
            for(int j = i - 1; j >= 0; j--)
            {
               impulseSize += MathAbs(iClose(_Symbol, timeframe, j) - iOpen(_Symbol, timeframe, j));
            }
            
            double minImpulse = OB_MinImpulseSize * _Point * 10;
            if(impulseSize >= minImpulse)
            {
               // Add order block
               AddOrderBlock(iTime(_Symbol, timeframe, i), high, low, OB_BULLISH, timeframe);
               break;
            }
         }
      }
   }
   
   if(isBearishCHOCH)
   {
      // Find bearish OB: Last bullish candle before bearish impulse
      for(int i = 1; i < 20; i++)
      {
         double open = iOpen(_Symbol, timeframe, i);
         double close = iClose(_Symbol, timeframe, i);
         double high = iHigh(_Symbol, timeframe, i);
         double low = iLow(_Symbol, timeframe, i);
         
         // Check if bullish candle
         if(close > open)
         {
            // Check if followed by bearish impulse
            double impulseSize = 0;
            for(int j = i - 1; j >= 0; j--)
            {
               impulseSize += MathAbs(iClose(_Symbol, timeframe, j) - iOpen(_Symbol, timeframe, j));
            }
            
            double minImpulse = OB_MinImpulseSize * _Point * 10;
            if(impulseSize >= minImpulse)
            {
               // Add order block
               AddOrderBlock(iTime(_Symbol, timeframe, i), high, low, OB_BEARISH, timeframe);
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add Order Block to array                                         |
//+------------------------------------------------------------------+
void AddOrderBlock(datetime time, double high, double low, ENUM_OB_TYPE type, ENUM_TIMEFRAMES tf)
{
   // Find empty slot
   for(int i = 0; i < maxOrderBlocks; i++)
   {
      if(!orderBlocks[i].isValid)
      {
         orderBlocks[i].time = time;
         orderBlocks[i].highPrice = high;
         orderBlocks[i].lowPrice = low;
         orderBlocks[i].type = type;
         orderBlocks[i].timeframe = tf;
         orderBlocks[i].isUsed = false;
         orderBlocks[i].isValid = true;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps                                           |
//+------------------------------------------------------------------+
void DetectFVG(ENUM_TIMEFRAMES timeframe)
{
   // Invalidate old FVGs
   for(int i = 0; i < maxFVGs; i++)
   {
      if(fvgZones[i].isValid)
      {
         int barsAge = iBarShift(_Symbol, timeframe, fvgZones[i].time);
         if(barsAge > FVG_MaxAge)
            fvgZones[i].isValid = false;
      }
   }
   
   // Check for new FVG (3-candle pattern)
   double high0 = iHigh(_Symbol, timeframe, 0);
   double low0 = iLow(_Symbol, timeframe, 0);
   double high1 = iHigh(_Symbol, timeframe, 1);
   double low1 = iLow(_Symbol, timeframe, 1);
   double high2 = iHigh(_Symbol, timeframe, 2);
   double low2 = iLow(_Symbol, timeframe, 2);
   
   double minGap = FVG_MinGapSize * _Point * 10;
   
   // Bullish FVG: gap between candle[2].high and candle[0].low
   if(low0 > high2)
   {
      double gapSize = low0 - high2;
      if(gapSize >= minGap)
      {
         AddFVG(iTime(_Symbol, timeframe, 1), low0, high2, FVG_BULLISH);
      }
   }
   
   // Bearish FVG: gap between candle[2].low and candle[0].high
   if(high0 < low2)
   {
      double gapSize = low2 - high0;
      if(gapSize >= minGap)
      {
         AddFVG(iTime(_Symbol, timeframe, 1), low2, high0, FVG_BEARISH);
      }
   }
}

//+------------------------------------------------------------------+
//| Add FVG to array                                                  |
//+------------------------------------------------------------------+
void AddFVG(datetime time, double top, double bottom, ENUM_FVG_TYPE type)
{
   for(int i = 0; i < maxFVGs; i++)
   {
      if(!fvgZones[i].isValid)
      {
         fvgZones[i].time = time;
         fvgZones[i].topPrice = top;
         fvgZones[i].bottomPrice = bottom;
         fvgZones[i].type = type;
         fvgZones[i].isFilled = false;
         fvgZones[i].isValid = true;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Premium/Discount zones using Fibonacci                 |
//+------------------------------------------------------------------+
void CalculateFiboZones(ENUM_TIMEFRAMES timeframe)
{
   if(ArraySize(swingHighs_HTF) < 1 || ArraySize(swingLows_HTF) < 1)
      return;
   
   swingHigh_Fibo = swingHighs_HTF[0].price;
   swingLow_Fibo = swingLows_HTF[0].price;
   
   double range = swingHigh_Fibo - swingLow_Fibo;
   
   currentEquilibrium = swingLow_Fibo + (range * 0.5);
   currentPremiumLevel = swingLow_Fibo + (range * 0.618);  // 61.8% = Premium start
   currentDiscountLevel = swingLow_Fibo + (range * 0.382); // 38.2% = Discount end
}

//+------------------------------------------------------------------+
//| Check if current time is in Kill Zone                            |
//+------------------------------------------------------------------+
bool IsInKillZone()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   
   // London session
   if(currentHour >= LondonStartHour && currentHour < LondonEndHour)
      return true;
   
   // NY session
   if(currentHour >= NYStartHour && currentHour < NYEndHour)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for SMC trading signals                                    |
//+------------------------------------------------------------------+
void CheckSMCSignals()
{
   // Formula 1: Liquidity Sweep + CHOCH + OB (Primary)
   if(UseFormula1)
   {
      CheckFormula1_Signal();
   }
   
   // Formula 2: BOS Continuation
   if(UseFormula2)
   {
      CheckFormula2_Signal();
   }
}

//+------------------------------------------------------------------+
//| Formula 1: Liquidity Sweep + CHOCH + OB                          |
//+------------------------------------------------------------------+
void CheckFormula1_Signal()
{
   if(EnableDebugLog)
      Print("[F1] Checking Formula 1 signals...");
   
   // SIMPLIFIED MODE: Trade on structure + OB only
   if(UseSimplifiedMode)
   {
      if(EnableDebugLog)
         Print("[F1] Using Simplified Mode");
      
      // Bullish setup: Uptrend + Bullish OB retest
      if(currentStructure_HTF == STRUCTURE_UPTREND || isBullishCHOCH)
      {
         if(EnableDebugLog)
            Print("[F1] Bullish structure detected");
         
         for(int i = 0; i < maxOrderBlocks; i++)
         {
            if(orderBlocks[i].isValid && !orderBlocks[i].isUsed && 
               orderBlocks[i].type == OB_BULLISH)
            {
               if(EnableDebugLog)
                  Print("[F1] Found valid Bullish OB at ", orderBlocks[i].lowPrice);
               
               if(CheckOBRetest(orderBlocks[i], true))
               {
                  if(EnableDebugLog)
                     Print("[F1] ✓ OB Retest confirmed");
                  
                  if(ConfirmEntry(true))
                  {
                     if(EnableDebugLog)
                        Print("[F1] ✓✓ Entry confirmed! Opening BUY order");
                     
                     ExecuteSMCTrade(true, "F1_SIMPLE_BUY");
                     orderBlocks[i].isUsed = true;
                     return;
                  }
                  else if(EnableDebugLog)
                  {
                     Print("[F1] ✗ Entry confirmation failed");
                  }
               }
               else if(EnableDebugLog)
               {
                  Print("[F1] ✗ OB Retest not detected");
               }
            }
         }
      }
      
      // Bearish setup: Downtrend + Bearish OB retest
      if(currentStructure_HTF == STRUCTURE_DOWNTREND || isBearishCHOCH)
      {
         if(EnableDebugLog)
            Print("[F1] Bearish structure detected");
         
         for(int i = 0; i < maxOrderBlocks; i++)
         {
            if(orderBlocks[i].isValid && !orderBlocks[i].isUsed && 
               orderBlocks[i].type == OB_BEARISH)
            {
               if(EnableDebugLog)
                  Print("[F1] Found valid Bearish OB at ", orderBlocks[i].highPrice);
               
               if(CheckOBRetest(orderBlocks[i], false))
               {
                  if(EnableDebugLog)
                     Print("[F1] ✓ OB Retest confirmed");
                  
                  if(ConfirmEntry(false))
                  {
                     if(EnableDebugLog)
                        Print("[F1] ✓✓ Entry confirmed! Opening SELL order");
                     
                     ExecuteSMCTrade(false, "F1_SIMPLE_SELL");
                     orderBlocks[i].isUsed = true;
                     return;
                  }
                  else if(EnableDebugLog)
                  {
                     Print("[F1] ✗ Entry confirmation failed");
                  }
               }
               else if(EnableDebugLog)
               {
                  Print("[F1] ✗ OB Retest not detected");
               }
            }
         }
      }
      
      return;
   }
   
   // FULL MODE: Original complex logic
   // Check for bullish setup
   if(currentStructure_HTF == STRUCTURE_UPTREND || isBullishCHOCH)
   {
      // Check if SSL was swept (optional)
      bool sslSwept = false;
      for(int i = 0; i < ArraySize(sslZones); i++)
      {
         if(sslZones[i].isSwept)
         {
            sslSwept = true;
            break;
         }
      }
      
      if(EnableDebugLog)
         Print("[F1] Bullish | SSL Swept: ", sslSwept, " | CHOCH: ", isBullishCHOCH);
      
      // Check conditions based on settings
      bool sweepOK = !Formula1_RequireSweep || sslSwept;
      bool chochOK = !Formula1_RequireCHOCH || isBullishCHOCH;
      
      if(sweepOK && chochOK)
      {
         // Look for bullish OB retest
         for(int i = 0; i < maxOrderBlocks; i++)
         {
            if(orderBlocks[i].isValid && !orderBlocks[i].isUsed && 
               orderBlocks[i].type == OB_BULLISH)
            {
               // Check if price is retesting OB
               if(CheckOBRetest(orderBlocks[i], true))
               {
                  // Confirm entry
                  if(ConfirmEntry(true))
                  {
                     ExecuteSMCTrade(true, "F1_SWEEP_CHOCH_OB");
                     orderBlocks[i].isUsed = true;
                     return;
                  }
               }
            }
         }
      }
   }
   
   // Check for bearish setup
   if(currentStructure_HTF == STRUCTURE_DOWNTREND || isBearishCHOCH)
   {
      // Check if BSL was swept (optional)
      bool bslSwept = false;
      for(int i = 0; i < ArraySize(bslZones); i++)
      {
         if(bslZones[i].isSwept)
         {
            bslSwept = true;
            break;
         }
      }
      
      if(EnableDebugLog)
         Print("[F1] Bearish | BSL Swept: ", bslSwept, " | CHOCH: ", isBearishCHOCH);
      
      // Check conditions based on settings
      bool sweepOK = !Formula1_RequireSweep || bslSwept;
      bool chochOK = !Formula1_RequireCHOCH || isBearishCHOCH;
      
      if(sweepOK && chochOK)
      {
         // Look for bearish OB retest
         for(int i = 0; i < maxOrderBlocks; i++)
         {
            if(orderBlocks[i].isValid && !orderBlocks[i].isUsed && 
               orderBlocks[i].type == OB_BEARISH)
            {
               // Check if price is retesting OB
               if(CheckOBRetest(orderBlocks[i], false))
               {
                  // Confirm entry
                  if(ConfirmEntry(false))
                  {
                     ExecuteSMCTrade(false, "F1_SWEEP_CHOCH_OB");
                     orderBlocks[i].isUsed = true;
                     return;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Formula 2: BOS Continuation                                      |
//+------------------------------------------------------------------+
void CheckFormula2_Signal()
{
   // Bullish BOS continuation
   if(isBullishBOS && currentStructure_HTF == STRUCTURE_UPTREND)
   {
      // Look for FVG retest
      for(int i = 0; i < maxFVGs; i++)
      {
         if(fvgZones[i].isValid && !fvgZones[i].isFilled &&
            fvgZones[i].type == FVG_BULLISH)
         {
            double currentLow = iLow(_Symbol, Entry_Timeframe, 0);
            if(currentLow <= fvgZones[i].topPrice && currentLow >= fvgZones[i].bottomPrice)
            {
               if(ConfirmEntry(true))
               {
                  ExecuteSMCTrade(true, "F2_BOS_CONTINUATION");
                  return;
               }
            }
         }
      }
   }
   
   // Bearish BOS continuation
   if(isBearishBOS && currentStructure_HTF == STRUCTURE_DOWNTREND)
   {
      // Look for FVG retest
      for(int i = 0; i < maxFVGs; i++)
      {
         if(fvgZones[i].isValid && !fvgZones[i].isFilled &&
            fvgZones[i].type == FVG_BEARISH)
         {
            double currentHigh = iHigh(_Symbol, Entry_Timeframe, 0);
            if(currentHigh >= fvgZones[i].bottomPrice && currentHigh <= fvgZones[i].topPrice)
            {
               if(ConfirmEntry(false))
               {
                  ExecuteSMCTrade(false, "F2_BOS_CONTINUATION");
                  return;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if price is retesting Order Block                          |
//+------------------------------------------------------------------+
bool CheckOBRetest(OrderBlock &ob, bool isBullish)
{
   double currentHigh = iHigh(_Symbol, Entry_Timeframe, 0);
   double currentLow = iLow(_Symbol, Entry_Timeframe, 0);
   
   double obHeight = ob.highPrice - ob.lowPrice;
   double tolerance = obHeight * (OB_RetestTolerance / 100.0);
   
   if(isBullish)
   {
      // Check if wick enters OB zone
      double retestLevel = ob.lowPrice + tolerance;
      if(currentLow <= retestLevel && currentLow >= ob.lowPrice)
         return true;
   }
   else
   {
      // Check if wick enters OB zone
      double retestLevel = ob.highPrice - tolerance;
      if(currentHigh >= retestLevel && currentHigh <= ob.highPrice)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Confirm entry conditions                                         |
//+------------------------------------------------------------------+
bool ConfirmEntry(bool isBullish)
{
   if(EnableDebugLog)
      Print("[CONFIRM] Checking entry confirmations for ", isBullish ? "BUY" : "SELL");
   
   // Check Premium/Discount filter
   if(UseFiboFilter)
   {
      double currentPrice = (iHigh(_Symbol, Entry_Timeframe, 0) + iLow(_Symbol, Entry_Timeframe, 0)) / 2;
      
      if(isBullish)
      {
         // Buy only in discount zone
         if(currentPrice > currentEquilibrium)
         {
            if(EnableDebugLog)
               Print("[CONFIRM] ✗ Price in Premium zone (", currentPrice, " > ", currentEquilibrium, ")");
            return false;
         }
         else if(EnableDebugLog)
         {
            Print("[CONFIRM] ✓ Price in Discount zone");
         }
      }
      else
      {
         // Sell only in premium zone
         if(currentPrice < currentEquilibrium)
         {
            if(EnableDebugLog)
               Print("[CONFIRM] ✗ Price in Discount zone (", currentPrice, " < ", currentEquilibrium, ")");
            return false;
         }
         else if(EnableDebugLog)
         {
            Print("[CONFIRM] ✓ Price in Premium zone");
         }
      }
   }
   
   // Check ADX
   if(adxBuffer_Entry[0] < MinADX)
   {
      if(EnableDebugLog)
         Print("[CONFIRM] ✗ ADX too low: ", adxBuffer_Entry[0], " < ", MinADX);
      return false;
   }
   else if(EnableDebugLog)
   {
      Print("[CONFIRM] ✓ ADX OK: ", adxBuffer_Entry[0]);
   }
   
   // Check spread
   if(UseSpreadFilter)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > MaxSpread * 10) // Convert pips to points
      {
         if(EnableDebugLog)
            Print("[CONFIRM] ✗ Spread too high: ", spread/10.0, " pips > ", MaxSpread, " pips");
         return false;
      }
      else if(EnableDebugLog)
      {
         Print("[CONFIRM] ✓ Spread OK: ", spread/10.0, " pips");
      }
   }
   
   // Check engulfing pattern
   if(RequireEngulfing)
   {
      if(!IsEngulfingPattern(isBullish))
      {
         if(EnableDebugLog)
            Print("[CONFIRM] ✗ No engulfing pattern");
         return false;
      }
      else if(EnableDebugLog)
      {
         Print("[CONFIRM] ✓ Engulfing pattern confirmed");
      }
   }
   
   // Check mini-BOS on confirmation timeframe
   if(RequireMiniBOS)
   {
      if(!CheckMiniBOS(isBullish))
      {
         if(EnableDebugLog)
            Print("[CONFIRM] ✗ No mini-BOS on confirmation TF");
         return false;
      }
      else if(EnableDebugLog)
      {
         Print("[CONFIRM] ✓ Mini-BOS confirmed");
      }
   }
   
   if(EnableDebugLog)
      Print("[CONFIRM] ✓✓ All confirmations passed!");
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for engulfing pattern                                      |
//+------------------------------------------------------------------+
bool IsEngulfingPattern(bool isBullish)
{
   double open0 = iOpen(_Symbol, Entry_Timeframe, 0);
   double close0 = iClose(_Symbol, Entry_Timeframe, 0);
   double open1 = iOpen(_Symbol, Entry_Timeframe, 1);
   double close1 = iClose(_Symbol, Entry_Timeframe, 1);
   
   if(isBullish)
   {
      // Bullish engulfing
      if(close1 < open1 && close0 > open0 && 
         close0 > open1 && open0 < close1)
         return true;
   }
   else
   {
      // Bearish engulfing
      if(close1 > open1 && close0 < open0 && 
         close0 < open1 && open0 > close1)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for mini-BOS on confirmation timeframe                     |
//+------------------------------------------------------------------+
bool CheckMiniBOS(bool isBullish)
{
   // Simple implementation: check if recent bar breaks previous high/low
   if(isBullish)
   {
      double high0 = iHigh(_Symbol, Confirm_Timeframe, 0);
      double high1 = iHigh(_Symbol, Confirm_Timeframe, 1);
      if(high0 > high1)
         return true;
   }
   else
   {
      double low0 = iLow(_Symbol, Confirm_Timeframe, 0);
      double low1 = iLow(_Symbol, Confirm_Timeframe, 1);
      if(low0 < low1)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute SMC Trade                                                |
//+------------------------------------------------------------------+
void ExecuteSMCTrade(bool isBuy, string formula)
{
   double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate SL/TP
   double sl, tp;
   CalculateSMC_SLTP(isBuy, entryPrice, sl, tp);
   
   // Calculate lot size
   double lotSize = CalculateLotSize(entryPrice, sl, RiskPercent);
   
   // Prepare comment
   string comment = TradeComment + "_" + formula;
   
   // Execute trade
   bool result = false;
   if(isBuy)
      result = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   else
      result = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   
   if(result)
   {
      lastTradeTime = TimeCurrent();
      Print("✓ ", isBuy ? "BUY" : "SELL", " order opened | Formula: ", formula,
            " | Lot: ", lotSize, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("✗ Order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate SL and TP based on SMC logic                           |
//+------------------------------------------------------------------+
void CalculateSMC_SLTP(bool isBuy, double entryPrice, double &sl, double &tp)
{
   double atr = atrBuffer_HTF[0];
   
   if(isBuy)
   {
      // SL below recent SSL
      if(ArraySize(sslZones) > 0)
         sl = sslZones[0].price - (LiquiditySweepBuffer * _Point * 10);
      else
         sl = entryPrice - (atr * 1.5);
      
      // TP based on RR ratio
      double distance = entryPrice - sl;
      tp = entryPrice + (distance * RR_Ratio);
   }
   else
   {
      // SL above recent BSL
      if(ArraySize(bslZones) > 0)
         sl = bslZones[0].price + (LiquiditySweepBuffer * _Point * 10);
      else
         sl = entryPrice + (atr * 1.5);
      
      // TP based on RR ratio
      double distance = sl - entryPrice;
      tp = entryPrice - (distance * RR_Ratio);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice, double riskPercent)
{
   double accountBalance = UseCompounding ? account.Balance() : account.Balance();
   if(accountBalance <= 0)
      accountBalance = 10000;
   
   double riskAmount = accountBalance * (riskPercent / 100.0);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipSize = point * 10;
   double pipDistance = MathAbs(entryPrice - slPrice) / pipSize;
   
   if(pipDistance <= 0)
      return MinLotSize;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue = (tickValue / tickSize) * pipSize;
   
   double lotSize = riskAmount / (pipDistance * pipValue);
   
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   lotSize = MathMax(MinLotSize, lotSize);
   lotSize = MathMin(MaxLotSize, lotSize);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Count positions for this EA                                      |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         {
            // Implement breakeven logic here if needed
            // Implement partial TP logic here if needed
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw visual aids on chart                                        |
//+------------------------------------------------------------------+
void DrawVisualAids()
{
   // Remove old objects
   ObjectsDeleteAll(0, "SMC_");
   
   // Draw swing highs
   for(int i = 0; i < ArraySize(swingHighs_HTF); i++)
   {
      if(swingHighs_HTF[i].isValid)
      {
         string name = "SMC_SwingHigh_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_TREND, 0, swingHighs_HTF[i].time, swingHighs_HTF[i].price,
                      TimeCurrent(), swingHighs_HTF[i].price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      }
   }
   
   // Draw swing lows
   for(int i = 0; i < ArraySize(swingLows_HTF); i++)
   {
      if(swingLows_HTF[i].isValid)
      {
         string name = "SMC_SwingLow_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_TREND, 0, swingLows_HTF[i].time, swingLows_HTF[i].price,
                      TimeCurrent(), swingLows_HTF[i].price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      }
   }
   
   // Draw Order Blocks
   for(int i = 0; i < maxOrderBlocks; i++)
   {
      if(orderBlocks[i].isValid && !orderBlocks[i].isUsed)
      {
         string name = "SMC_OB_" + IntegerToString(i);
         datetime endTime = TimeCurrent() + PeriodSeconds(HTF_Timeframe) * 50;
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, orderBlocks[i].time, orderBlocks[i].highPrice,
                      endTime, orderBlocks[i].lowPrice);
         ObjectSetInteger(0, name, OBJPROP_COLOR, orderBlocks[i].type == OB_BULLISH ? clrBlue : clrRed);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
      }
   }
   
   // Draw FVGs
   for(int i = 0; i < maxFVGs; i++)
   {
      if(fvgZones[i].isValid && !fvgZones[i].isFilled)
      {
         string name = "SMC_FVG_" + IntegerToString(i);
         datetime endTime = TimeCurrent() + PeriodSeconds(HTF_Timeframe) * 30;
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, fvgZones[i].time, fvgZones[i].topPrice,
                      endTime, fvgZones[i].bottomPrice);
         ObjectSetInteger(0, name, OBJPROP_COLOR, fvgZones[i].type == FVG_BULLISH ? clrLightBlue : clrLightPink);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
      }
   }
   
   // Draw BSL zones
   for(int i = 0; i < ArraySize(bslZones); i++)
   {
      if(bslZones[i].isValid)
      {
         string name = "SMC_BSL_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_TREND, 0, bslZones[i].time, bslZones[i].price,
                      TimeCurrent(), bslZones[i].price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, bslZones[i].isSwept ? clrGray : clrYellow);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      }
   }
   
   // Draw SSL zones
   for(int i = 0; i < ArraySize(sslZones); i++)
   {
      if(sslZones[i].isValid)
      {
         string name = "SMC_SSL_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_TREND, 0, sslZones[i].time, sslZones[i].price,
                      TimeCurrent(), sslZones[i].price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, sslZones[i].isSwept ? clrGray : clrYellow);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      }
   }
   
   // Draw Premium/Discount levels
   if(UseFiboFilter)
   {
      ObjectCreate(0, "SMC_Premium", OBJ_TREND, 0, iTime(_Symbol, HTF_Timeframe, 50), currentPremiumLevel,
                   TimeCurrent(), currentPremiumLevel);
      ObjectSetInteger(0, "SMC_Premium", OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "SMC_Premium", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SMC_Premium", OBJPROP_RAY_RIGHT, true);
      
      ObjectCreate(0, "SMC_Equilibrium", OBJ_TREND, 0, iTime(_Symbol, HTF_Timeframe, 50), currentEquilibrium,
                   TimeCurrent(), currentEquilibrium);
      ObjectSetInteger(0, "SMC_Equilibrium", OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "SMC_Equilibrium", OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, "SMC_Equilibrium", OBJPROP_RAY_RIGHT, true);
      
      ObjectCreate(0, "SMC_Discount", OBJ_TREND, 0, iTime(_Symbol, HTF_Timeframe, 50), currentDiscountLevel,
                   TimeCurrent(), currentDiscountLevel);
      ObjectSetInteger(0, "SMC_Discount", OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, "SMC_Discount", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SMC_Discount", OBJPROP_RAY_RIGHT, true);
   }
}
//+------------------------------------------------------------------+
