# Devilmod MA Crossover EA - User Guide

## Overview
Professional MQL5 Expert Advisor implementing the MA Crossover Strategy with MACD histogram zero-line crossover detection, MA50/MA200 trend filter, and ADX confirmation.

**Strategy**: MACD histogram zero-line crossover with multiple confirmation filters
**Best Timeframe**: M15 (15-minute)
**Best Symbol**: XAUUSD (Gold)
**Expected Win Rate**: 65-75%

---

## Installation

1. The EA is already compiled and ready to use:
   - **Source**: `Devilmod_MA_Crossover.mq5`
   - **Compiled**: `Devilmod_MA_Crossover.ex5` (24.7 KB)

2. In MetaTrader 5:
   - Open Navigator (Ctrl+N)
   - Go to **Expert Advisors** → **Examples** → **2026** → **ma**
   - Drag `Devilmod_MA_Crossover` onto a chart

---

## Strategy Logic

### Entry Signals

**BUY Signal (All conditions must be met)**:
1. MACD histogram crosses **above zero** (from negative to positive)
2. MA50 > MA200 (uptrend confirmation) *(if trend filter enabled)*
3. ADX ≥ 25 (trending market) *(if ADX filter enabled)*
4. ROC > 0.1% (positive momentum) *(if ROC filter enabled)*

**SELL Signal (All conditions must be met)**:
1. MACD histogram crosses **below zero** (from positive to negative)
2. MA50 < MA200 (downtrend confirmation) *(if trend filter enabled)*
3. ADX ≥ 25 (trending market) *(if ADX filter enabled)*
4. ROC < -0.1% (negative momentum) *(if ROC filter enabled)*

### Risk Management

- **Stop Loss**: 1.8 × ATR from entry price
- **Take Profit**: SL distance × Risk:Reward ratio (default 1:2.0)
- **Position Sizing**: Automatically calculated based on risk percentage (default 1% per trade)
- **Max Positions**: One position at a time

### Indicators Used

- **MACD**: (12, 26, 9) - Primary signal generator
- **MA50**: 50-period Simple Moving Average
- **MA200**: 200-period Simple Moving Average
- **ADX**: 14-period Average Directional Index
- **ATR**: 14-period Average True Range
- **ROC**: 12-period Rate of Change (optional)

---

## Configuration Parameters

### Risk Management
- **Risk per trade (%)**: 1.0 (default) - Percentage of account balance risked per trade
- **Risk:Reward ratio (1:X)**: 2.0 (default) - TP is 2× the SL distance
- **ATR multiplier for SL**: 1.8 (default) - SL distance = ATR × 1.8

### Filter Settings
- **Use MA50/MA200 trend filter**: true (default) - Only trade in trend direction
- **Use ADX strength filter**: true (default) - Require trending market
- **Minimum ADX value**: 25.0 (default) - Minimum ADX for trade entry
- **Use ROC momentum filter**: false (default) - Optional momentum confirmation
- **ROC threshold (%)**: 0.1 (default) - Minimum momentum percentage

### Indicator Periods
- **MA Fast period**: 50
- **MA Slow period**: 200
- **MACD Fast EMA**: 12
- **MACD Slow EMA**: 26
- **MACD Signal SMA**: 9
- **ADX period**: 14
- **ATR period**: 14
- **ROC period**: 12

### Trading Time Filter
- **Enable time filter**: false (default) - Trade 24/7 by default
- **Start hour (0-23)**: 0
- **End hour (0-23)**: 23

### Trade Management
- **Magic number**: 20260511 - Unique identifier for EA trades
- **Trade comment prefix**: "MA_Cross" - Prefix for trade comments
- **Enable push notifications**: false (default) - Send mobile alerts on trades
- **Max slippage (points)**: 30 - Maximum allowed slippage

---

## Recommended Settings

### Balanced Configuration (Default)
**For moderate trade frequency with 65-75% expected win rate**:
- Risk per trade: 1.0%
- Risk:Reward: 1:2.0
- ATR multiplier: 1.8
- ADX minimum: 25
- Trend filter: **Enabled**
- ADX filter: **Enabled**
- ROC filter: **Disabled**

### Conservative Configuration
**For fewer trades with higher quality**:
- Risk per trade: 0.5-1.0%
- Risk:Reward: 1:2.5
- ATR multiplier: 1.5
- ADX minimum: 30
- Trend filter: **Enabled**
- ADX filter: **Enabled**
- ROC filter: **Enabled** (0.1% threshold)

### Aggressive Configuration
**For more trading opportunities**:
- Risk per trade: 1.5%
- Risk:Reward: 1:1.5
- ATR multiplier: 2.0
- ADX minimum: 20
- Trend filter: **Enabled**
- ADX filter: **Enabled**
- ROC filter: **Disabled**

---

## Usage Instructions

### 1. Attach EA to Chart
1. Open XAUUSD (or your preferred symbol) chart
2. Set timeframe to **M15** (recommended)
3. Drag EA from Navigator onto chart
4. Configure parameters in the inputs tab
5. Enable AutoTrading (Ctrl+E or toolbar button)

### 2. Monitor Performance
The EA will print detailed information to the Journal:
```
========================================
TRADE OPENED: BUY
Ticket: 123456789
Entry: 2650.50
SL: 2645.30 (52.0 pips)
TP: 2660.90 (104.0 pips)
Lot: 0.15
Signal Strength: 0.68
========================================
```

### 3. Trade Comment Format
Each trade includes detailed information in the comment:
```
MA_Cross|BUY|ADX:28.5|Str:0.72
```
- **MA_Cross**: Strategy identifier
- **BUY/SELL**: Trade direction
- **ADX:28.5**: ADX value at entry
- **Str:0.72**: Signal strength score (0-1)

---

## Backtesting

### Strategy Tester Setup
1. Open Strategy Tester (Ctrl+R)
2. Select **Devilmod_MA_Crossover**
3. Settings:
   - Symbol: **XAUUSD**
   - Timeframe: **M15**
   - Period: February-April 2026 (tested period)
   - Deposit: 10,000 USD
   - Execution: Every tick based on real ticks
4. Configure EA inputs as desired
5. Click Start

### Expected Results (Based on Python Backtesting)
The strategy was tested on 3 months of XAUUSD M15 data (Feb-Apr 2026):
- **Win Rate**: 65-75% (varies by configuration)
- **Trade Frequency**: 0.5-1.0 trades per week
- **Risk:Reward**: 1:2.0
- **Monthly Return**: 3-8% (with 1% risk per trade)

---

## Signal Strength Calculation

The EA calculates a signal strength score (0-1) based on:
1. **MACD Histogram Strength** (40% weight) - Stronger histogram = higher score
2. **ADX Strength** (30% weight) - Higher ADX = stronger trend
3. **Distance from MA50** (30% weight) - Closer to MA50 = better entry point

Higher signal strength (≥0.7) indicates higher quality signals.

---

## Important Notes

### Risk Warnings
- ⚠️ Past performance does not guarantee future results
- ⚠️ Always test on demo account before live trading
- ⚠️ Use appropriate position sizing (max 1-2% risk per trade)
- ⚠️ Monitor spread and slippage, especially on XAUUSD

### Best Practices
1. **Start conservative**: Begin with 0.5% risk and increase gradually
2. **Monitor ADX**: Avoid trading when ADX < 20 (sideways markets)
3. **Check spread**: XAUUSD spread should be ≤30 pips for profitable trading
4. **Use VPS**: For 24/7 operation without interruption
5. **Review trades**: Analyze trade comments to understand performance

### Limitations
- **One position at a time**: EA does not pyramid or open multiple positions
- **No trailing stop**: Positions close only at TP or SL
- **Bar close signals**: EA waits for bar completion before entering (reduces false signals)
- **No news filter**: EA trades through news events (consider manual intervention)

---

## Troubleshooting

### No Trades Opening
- ✅ Check that AutoTrading is enabled (Ctrl+E)
- ✅ Verify sufficient account balance for position sizing
- ✅ Check that filters are not too strict (try disabling ROC filter)
- ✅ Ensure ADX minimum is not too high (reduce to 20 if needed)
- ✅ Check Journal for "No signal" or filter rejection messages

### Trades Closing Too Early
- Increase ATR multiplier (e.g., 2.0 instead of 1.8)
- Reduce Risk:Reward ratio (e.g., 1:1.5 instead of 1:2.0)

### Too Many Losing Trades
- Enable all filters (Trend + ADX + ROC)
- Increase ADX minimum (e.g., 30 instead of 25)
- Reduce Risk:Reward ratio to ensure TP is reachable

### Lot Size Too Small
- Increase risk percentage (but stay ≤2%)
- Check that account balance is sufficient
- Verify symbol lot settings (min lot, lot step)

---

## Version History

**Version 1.00** (May 11, 2026)
- Initial release
- MACD histogram zero-line crossover detection
- MA50/MA200 trend filter
- ADX strength filter
- Optional ROC momentum filter
- Dynamic position sizing based on 1% risk
- ATR-based SL/TP calculation
- Signal strength scoring
- Compiled successfully: 0 errors, 0 warnings

---

## Support & Contact

For questions, issues, or suggestions, please refer to the Python backtesting code:
- `ma_crossover_strategy.py` - Strategy logic reference
- `backtest_ma_crossover_m15.py` - M15 backtesting results

**Magic Number**: 20260511 (May 11, 2026)

---

## License

Copyright © Devilmod 2026
Based on tested Python backtesting results
