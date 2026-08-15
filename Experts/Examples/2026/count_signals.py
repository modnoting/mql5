"""
Quick test to count M&W signals
"""
import pandas as pd
import numpy as np
from hybrid_strategy import HybridStrategyEngine
from indicators_updated import add_all_indicators

# Load data
data_files = [
    "DataHistory/DAT_MT_XAUUSD_M1_202602.csv",
    "DataHistory/DAT_MT_XAUUSD_M1_202603.csv",
    "DataHistory/DAT_MT_XAUUSD_M1_202604.csv"
]

print("Loading data...")
df_list = []
for file in data_files:
    df_temp = pd.read_csv(file, sep=',', header=None, 
                          names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
    df_temp['datetime'] = pd.to_datetime(df_temp['date'] + ' ' + df_temp['time'], 
                                          format='%Y.%m.%d %H:%M')
    df_list.append(df_temp[['datetime', 'open', 'high', 'low', 'close', 'volume']])

df = pd.concat(df_list, ignore_index=True)
df = df.sort_values('datetime').reset_index(drop=True)
df['tick_volume'] = df['volume']  # Add tick_volume column

# Resample to H1
df.set_index('datetime', inplace=True)
df_h1 = df.resample('1h').agg({
    'open': 'first',
    'high': 'max',
    'low': 'min',
    'close': 'last',
    'tick_volume': 'sum',
    'volume': 'sum'
})
df_h1 = df_h1.dropna().reset_index()

print(f"Resampled to {len(df_h1)} H1 bars")

# Add indicators
add_all_indicators(df_h1)

# Create strategy engine
config = {
    'ma_risk_percent': 6.0,
    'ma_rr_ratio': 3.0,
    'mw_risk_percent': 1.0,
    'mw_rr_ratio': 1.5,
    'use_compound': True
}
engine = HybridStrategyEngine(config)

# Count signals
ma_count = 0
mw_count = 0

print("Counting signals...")
for i in range(200, len(df_h1)):  # Skip first 200 bars
    ma_sig = engine.detect_ma_signal(df_h1, i)
    mw_sig = engine.detect_mw_signal(df_h1, i)
    
    if ma_sig is not None:
        ma_count += 1
    if mw_sig is not None:
        mw_count += 1
        print(f"  M&W Signal #{mw_count} at bar {i}: {mw_sig.signal_type}, Entry={mw_sig.entry_price:.2f}, SL={mw_sig.stop_loss:.2f}")

print(f"\n=== SIGNAL COUNT ===")
print(f"MA H1 Signals: {ma_count}")
print(f"M&W Pattern Signals: {mw_count}")
print(f"Total: {ma_count + mw_count}")
