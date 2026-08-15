"""
Quick Multi-Timeframe Comparison (Skips M1 for Speed)
Tests: M5, M15, M30, H1, H4
"""

import subprocess
import sys

# Modify the main script to use only faster timeframes
quick_script = """
# Import everything from the original script
import sys
sys.path.insert(0, '.')
from backtest_timeframe_comparison import *

if __name__ == '__main__':
    # CSV files
    csv_files = {
        '2026_02': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
        '2026_03': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
        '2026_04': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv',
    }
    
    # Test only practical timeframes (skip M1 for speed)
    timeframes = ['M5', 'M15', 'M30', 'H1', 'H4']
    
    print("\\n" + "="*80)
    print("QUICK MULTI-TIMEFRAME COMPARISON (M1 skipped for speed)")
    print("="*80 + "\\n")
    
    # Run comparison
    all_results = run_timeframe_comparison(
        csv_files=csv_files,
        timeframes=timeframes,
        initial_balance=100.0,
        risk_percent=2.0
    )
    
    if not all_results:
        print("\\nNo results to process. Exiting.")
        sys.exit(1)
    
    # Generate reports
    print("\\n" + "="*80)
    print("GENERATING COMPARISON REPORTS")
    print("="*80 + "\\n")
    
    generate_comparison_report(all_results, output_dir="reports")
    generate_comparison_charts(all_results, output_dir="reports")
    
    # Print final summary
    print("\\n" + "="*80)
    print("QUICK COMPARISON COMPLETED")
    print("="*80)
    print("\\nBest performing timeframes (by daily return):")
    
    sorted_tf = sorted(all_results.keys(), 
                      key=lambda tf: all_results[tf]['results']['avg_daily_return_pct'], 
                      reverse=True)
    
    for rank, tf in enumerate(sorted_tf, 1):
        r = all_results[tf]['results']
        print(f"  {rank}. {tf}: {r['avg_daily_return_pct']:.2f}% daily return "
              f"(${r['net_profit']:.2f} profit, {r['win_rate']:.1f}% win rate)")
    
    print("\\n[OK] Reports saved in: reports/")
    print("  - timeframe_comparison_report.txt")
    print("  - timeframe_comparison_report.csv")
    print("  - comparison_daily_return.png")
    print("  - comparison_win_rate.png")
    print("  - comparison_total_trades.png")
    print("  - comparison_equity_curves.png")
    print("\\nNote: M1 was skipped for speed. Run backtest_timeframe_comparison.py to include M1.")
    print("=" *80 + "\\n")
"""

# Write and execute
with open('quick_comparison.py', 'w') as f:
    f.write(quick_script)

print("Created quick_comparison.py - Running now...")
subprocess.run([sys.executable, 'quick_comparison.py'])
