#property copyright ""
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 2

#property indicator_label1 "RenkoUp"
#property indicator_label2 "RenkoDn"
#property indicator_type1 DRAW_ARROW
#property indicator_type2 DRAW_ARROW
#property indicator_color1 clrBlue
#property indicator_color2 clrRed
#property indicator_width1 2
#property indicator_width2 2

input int    RenkoBoxSize   = 10;
input int    RenkoBoxOffset = 0;

double BoxPoints;
double UpWick, DnWick;
double PrevLow, PrevHigh, PrevOpen, PrevClose;
double CurVolume;
datetime PrevTime;
bool   Initialized = false;

double BufUp[];
double BufDn[];
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufUp, INDICATOR_DATA);
   SetIndexBuffer(1, BufDn, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   IndicatorSetString(INDICATOR_SHORTNAME, "Renko(" + IntegerToString(RenkoBoxSize) + ")");

   if(MathAbs(RenkoBoxOffset) >= RenkoBoxSize)
     {
      Print("Error: |RenkoBoxOffset| should be less than RenkoBoxSize!");
      return(INIT_FAILED);
     }

   int BoxSize   = RenkoBoxSize;
   int BoxOffset = RenkoBoxOffset;

   if(_Digits == 5 || (_Digits == 3 && StringFind(_Symbol, "JPY") != -1))
     {
      BoxSize   = BoxSize * 10;
      BoxOffset = BoxOffset * 10;
     }
   if(_Digits == 6 || (_Digits == 4 && StringFind(_Symbol, "JPY") != -1))
     {
      BoxSize   = BoxSize * 100;
      BoxOffset = BoxOffset * 100;
     }

   BoxPoints = NormalizeDouble(BoxSize * _Point, _Digits);

   double CloseArr[];
   ArraySetAsSeries(CloseArr, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, CloseArr) <= 0)
     {
      Print("Failed to get close price");
      return(INIT_FAILED);
     }

   PrevLow   = NormalizeDouble(BoxOffset * _Point + MathFloor(CloseArr[0] / BoxPoints) * BoxPoints, _Digits);
   DnWick    = PrevLow;
   PrevHigh  = PrevLow + BoxPoints;
   UpWick    = PrevHigh;
   PrevOpen  = PrevLow;
   PrevClose = PrevHigh;
   CurVolume = 1;

   datetime TimeArr[];
   ArraySetAsSeries(TimeArr, true);
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, TimeArr) <= 0)
     {
      Print("Failed to get time");
      return(INIT_FAILED);
     }
   PrevTime = TimeArr[0];

   Initialized = true;
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2 || !Initialized)
      return(0);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0)
      return(0);

   UpWick = MathMax(UpWick, bid);
   DnWick = MathMin(DnWick, bid);
   CurVolume++;

   // up box
   if(bid >= PrevHigh + BoxPoints)
     {
      PrevHigh  = PrevHigh + BoxPoints;
      PrevLow   = PrevLow + BoxPoints;
      PrevOpen  = PrevLow;
      PrevClose = PrevHigh;

      if(PrevTime < TimeCurrent()) PrevTime = TimeCurrent();
      else PrevTime++;

      CurVolume = 0;
      UpWick    = 0;
      DnWick    = EMPTY_VALUE;
     }
   // down box
   else if(bid <= PrevLow - BoxPoints)
     {
      PrevHigh  = PrevHigh - BoxPoints;
      PrevLow   = PrevLow - BoxPoints;
      PrevOpen  = PrevHigh;
      PrevClose = PrevLow;

      if(PrevTime < TimeCurrent()) PrevTime = TimeCurrent();
      else PrevTime++;

      CurVolume = 0;
      UpWick    = 0;
      DnWick    = EMPTY_VALUE;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
