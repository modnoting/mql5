"""
Quick test for M&W Pattern detection in hybrid strategy
"""

from hybrid_strategy import HybridStrategyEngine, create_hybrid_config
from indicators_updated import add_all_indicators
import pandas as pd

# Load ALL data (Feb-Apr)
print("Loading all data (Feb-Apr 2026)...")
all_data = []

for month in ['202602', '202603', '202604']:
    df = pd.read_csv(f'DataHistory/DAT_MT_XAUUSD_M1_{month}.csv', header=None,
                     names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
    df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])
    df = df.set_index('datetime')
    df = df[['open', 'high', 'low', 'close', 'volume']]
    all_data.append(df)
    print(f"  Loaded {len(df)} bars from {month}")

df_combined = pd.concat(all_data, axis=0)
print(f"Total: {len(df_combined)} M1 bars")

# Resample to H1
print("\nResampling to H1...")
df_h1 = df_combined.resample('1h').agg({
    'open': 'first',
    'high': 'max',
    'low': 'min',
    'close': 'last',
    'volume': 'sum'
}).dropna()
df_h1 = df_h1.reset_index()
print(f"Resampled to {len(df_h1)} H1 bars")

# Add indicators
print("Adding indicators...")
df_h1 = add_all_indicators(df_h1)

# Create strategy
config = create_hybrid_config(initial_balance=100.0)
strategy = HybridStrategyEngine(config)

# Test signal detection
print("\nTesting signal detection...")
ma_signals = 0
mw_signals = 0

for i in range(250, len(df_h1)):
    signal = strategy.detect_hybrid_signal(df_h1, i)
    if signal:
        if signal.strategy == 'MA_H1':
            ma_signals += 1
        elif signal.strategy == 'MW_PATTERN':
            mw_signals += 1
            print(f"M&W Signal at {signal.signal_time}: {signal.signal_type}")
            print(f"  Entry: {signal.entry_price:.2f} | SL: {signal.stop_loss:.2f} | TP: {signal.take_profit:.2f}")

print(f"\n=== RESULTS ===")
print(f"MA H1 Signals: {ma_signals}")
print(f"M&W Pattern Signals: {mw_signals}")
print(f"Total Signals: {ma_signals + mw_signals}")

if mw_signals == 0:
    print("\nWARNING: No M&W signals detected")
    print("Pattern conditions may be too strict or patterns not present in this period")
else:
    print(f"\nSUCCESS: M&W Pattern detection working! Found {mw_signals} signals")
