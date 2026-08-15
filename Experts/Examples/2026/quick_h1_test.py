"""
Quick H1 Backtest - MA Aggressive Strategy
"""
import pandas as pd
import numpy as np
from ma_crossover_strategy import detect_signal as detect_ma_signal
from indicators_updated import add_all_indicators

# Config
config = {
    'timeframe': 'H1',
    'risk_percent': 6.0,
    'rr_ratio': 3.0,
    'atr_multiplier': 1.5,
    'use_compound': True,
    'min_adx': 15,
    'use_trend_filter': True,
    'use_adx_filter': True,
    'macd_fast': 12,
    'macd_slow': 26,
    'macd_signal': 9,
    'pip_size': 0.1,
    'point_value': 1.0,
    'spread': 20,
    'execution_penalty': 5
}

# Load data
print("Loading data...")
files = [
    "DataHistory/DAT_MT_XAUUSD_M1_202602.csv",
    "DataHistory/DAT_MT_XAUUSD_M1_202603.csv",
    "DataHistory/DAT_MT_XAUUSD_M1_202604.csv"
]

df_list = []
for f in files:
    df_temp = pd.read_csv(f, sep=',', header=None, 
                          names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
    df_temp['datetime'] = pd.to_datetime(df_temp['date'] + ' ' + df_temp['time'], format='%Y.%m.%d %H:%M')
    df_list.append(df_temp[['datetime', 'open', 'high', 'low', 'close', 'volume']])

df = pd.concat(df_list, ignore_index=True).sort_values('datetime').reset_index(drop=True)
df['tick_volume'] = df['volume']

# Resample to H1
df.set_index('datetime', inplace=True)
df_h1 = df.resample('1h').agg({
    'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last',
    'tick_volume': 'sum', 'volume': 'sum'
}).dropna().reset_index()

print(f"H1 bars: {len(df_h1)}")
add_all_indicators(df_h1)

# Backtest
balance = 100.0
trades = []
position = None

for i in range(200, len(df_h1)):
    # Check exit
    if position:
        current_high = df_h1.loc[i, 'high']
        current_low = df_h1.loc[i, 'low']
        
        if position['type'] == 'BUY':
            if current_high >= position['tp']:
                profit = abs(position['tp'] - position['entry']) / 0.1 * 1.0 * position['lot']
                profit -= 25  # Spread
                balance += profit
                trades.append({'result': 'WIN', 'profit': profit, 'balance': balance})
                position = None
            elif current_low <= position['sl']:
                loss = -abs(position['entry'] - position['sl']) / 0.1 * 1.0 * position['lot']
                loss -= 25
                balance += loss
                trades.append({'result': 'LOSS', 'profit': loss, 'balance': balance})
                position = None
        else:  # SELL
            if current_low <= position['tp']:
                profit = abs(position['entry'] - position['tp']) / 0.1 * 1.0 * position['lot']
                profit -= 25
                balance += profit
                trades.append({'result': 'WIN', 'profit': profit, 'balance': balance})
                position = None
            elif current_high >= position['sl']:
                loss = -abs(position['sl'] - position['entry']) / 0.1 * 1.0 * position['lot']
                loss -= 25
                balance += loss
                trades.append({'result': 'LOSS', 'profit': loss, 'balance': balance})
                position = None
    
    # Check entry
    if position is None:
        sig = detect_ma_signal(df_h1, i, config)
        if sig and sig.signal_type in ['BUY', 'SELL']:
            entry = df_h1.loc[i, 'close']
            atr = df_h1.loc[i, 'ATR']
            
            if sig.signal_type == 'BUY':
                sl = entry - (atr * 1.5)
                distance = entry - sl
                tp = entry + (distance * 3.0)
            else:
                sl = entry + (atr * 1.5)
                distance = sl - entry
                tp = entry - (distance * 3.0)
            
            # Calculate lot
            risk_amt = balance * 0.06
            pip_dist = abs(distance) / 0.1
            lot = risk_amt / (pip_dist * 1.0)
            lot = max(0.01, min(100.0, round(lot / 0.01) * 0.01))
            
            position = {
                'type': sig.signal_type,
                'entry': entry,
                'sl': sl,
                'tp': tp,
                'lot': lot
            }

# Stats
wins = sum(1 for t in trades if t['result'] == 'WIN')
losses = len(trades) - wins
wr = wins / len(trades) * 100 if trades else 0
ret = (balance - 100) / 100 * 100

print(f"\n{'='*50}")
print(f"MA H1 AGGRESSIVE - BACKTEST RESULTS")
print(f"{'='*50}")
print(f"Initial: $100 | Final: ${balance:.2f}")
print(f"Return: {ret:+.2f}%")
print(f"Trades: {len(trades)} | Wins: {wins} | Losses: {losses}")
print(f"Win Rate: {wr:.2f}%")
print(f"Daily Return: ~{ret/68:.2f}%")
print(f"{'='*50}\n")
