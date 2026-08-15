"""
Test MA H1 Aggressive standalone to compare with hybrid results
"""

from backtest_timeframe_comparison import BacktestEngine, create_config_for_timeframe
import pandas as pd

# CSV files
csv_files = {
    '202602': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
    '202603': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
    '202604': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv'
}

# Load M1 data
all_m1_data = []
for period, csv_path in csv_files.items():
    temp_engine = BacktestEngine(create_config_for_timeframe('H1'))
    df_m1 = temp_engine.load_csv_data(csv_path)
    all_m1_data.append(df_m1)

# Combine all M1 data
df_m1_combined = pd.concat(all_m1_data)
print(f"Combined data: {len(df_m1_combined)} M1 bars")

# Create H1 config
config_h1 = create_config_for_timeframe('H1', initial_balance=100.0)

# Create engine
engine = BacktestEngine(config_h1)

# Resample to H1
df_h1 = engine.resample_to_timeframe(df_m1_combined, 'H1')

# Run backtest
print("\n" + "="*80)
print("MA H1 AGGRESSIVE STANDALONE TEST")
print("="*80)
results = engine.run_backtest(df_h1, verbose=False)

# Print results
print("\n" + "="*80)
print("RESULTS")
print("="*80)
print(f"Total Trades: {results['total_trades']} ({results['wins']}W / {results['losses']}L)")
print(f"Win Rate: {results['win_rate']:.2f}%")
print(f"Net Profit: ${results['net_profit']:.2f} ({results['total_return_pct']:.2f}%)")
print(f"Avg Daily Return: {results['avg_daily_return_pct']:.2f}%")
print(f"Profit Factor: {results['profit_factor']:.2f}")
print(f"Max Drawdown: {results['max_drawdown_pct']:.2f}%")
print(f"Final Balance: ${results['final_balance']:.2f}")
print(f"Trading Days: {results['trading_days']}")
print(f"Trades per Day: {results['trades_per_day']:.2f}")
print("="*80 + "\n")

# Save trade log
if engine.trades:
    trades_df = pd.DataFrame(engine.trades)
    trades_df.to_csv('reports/ma_h1_standalone_trades.csv', index=False)
    print("Trade log saved: reports/ma_h1_standalone_trades.csv")
