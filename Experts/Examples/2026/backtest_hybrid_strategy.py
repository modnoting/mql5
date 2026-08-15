"""
Hybrid Strategy Backtest - MA H1 Aggressive + M&W Pattern
Test combined strategy on H1 timeframe XAUUSD data
Expected: ~2.5-3.5% daily return (combined from both strategies)
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime
import matplotlib.pyplot as plt

# Import modules
from indicators_updated import add_all_indicators
from hybrid_strategy import HybridStrategyEngine, create_hybrid_config


class HybridBacktestEngine:
    """Backtest engine for hybrid strategy"""
    
    def __init__(self, config):
        self.config = config
        self.balance = config['initial_balance']
        self.equity = config['initial_balance']
        self.trades = []
        self.open_positions = []  # Changed from open_position to open_positions list
        self.pip_size = config.get('pip_size', 0.1)
        self.point_value = config.get('point_value', 1.0)
        
        # Strategy engine
        self.strategy = HybridStrategyEngine(config)
    
    def load_csv_data(self, csv_path):
        """Load M1 CSV data"""
        print(f"Loading CSV data from: {csv_path}")
        
        df = pd.read_csv(csv_path, header=None,
                         names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
        df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])
        df = df.set_index('datetime')
        df = df[['open', 'high', 'low', 'close', 'volume']]
        
        print(f"  Loaded {len(df)} M1 bars")
        print(f"  Date range: {df.index[0]} to {df.index[-1]}")
        
        return df
    
    def resample_to_h1(self, df_m1):
        """Resample M1 to H1"""
        print("Resampling M1 data to H1...")
        
        df_h1 = df_m1.resample('1h').agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        # Reset index to have datetime as column (same as backtest_timeframe_comparison)
        df_h1 = df_h1.reset_index()
        
        print(f"  Resampled to {len(df_h1)} H1 bars")
        return df_h1
    
    def calculate_lot_size(self, entry_price, stop_loss, risk_percent, signal_strength=1.0):
        """Calculate lot size based on risk"""
        # Use current equity for compound mode
        if self.config.get('use_compound', False):
            capital_base = max(self.equity, self.config['initial_balance'] * 0.1)
        else:
            capital_base = self.config['initial_balance']
        
        # Calculate risk amount
        risk_amount = capital_base * (risk_percent / 100.0)
        
        # Calculate pip distance
        pip_distance = abs(entry_price - stop_loss) / self.pip_size
        if pip_distance == 0:
            return 0.01
        
        # Calculate lot size
        lot_size = risk_amount / (pip_distance * self.point_value * self.pip_size)
        lot_size = max(0.01, round(lot_size, 2))
        
        return lot_size
    
    def enter_trade(self, row, signal):
        """Enter new trade based on hybrid signal"""
        entry_price = signal.entry_price
        stop_loss = signal.stop_loss
        take_profit = signal.take_profit
        
        # Calculate lot size
        lot_size = self.calculate_lot_size(
            entry_price, 
            stop_loss, 
            signal.risk_percent,
            signal.confidence
        )
        
        if lot_size <= 0:
            return
        
        # Store position in list
        position = {
            'type': signal.signal_type,
            'strategy': signal.strategy,
            'entry_price': entry_price,
            'entry_time': signal.signal_time,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'lot_size': lot_size,
            'risk_percent': signal.risk_percent,
            'rr_ratio': signal.rr_ratio,
            'atr': signal.atr,
            'confidence': signal.confidence,
            'details': signal.details
        }
        
        self.open_positions.append(position)
    
    def check_exit(self, row):
        """Check for exit conditions on all open positions"""
        if not self.open_positions:
            return
        
        current_price = row['close']
        high = row['high']
        low = row['low']
        
        # Apply spread and slippage
        spread = 20 * self.pip_size
        slippage = 5 * self.pip_size
        
        # Check each open position
        positions_to_close = []
        
        for idx, pos in enumerate(self.open_positions):
            exit_price = None
            exit_reason = None
            
            if pos['type'] == 'BUY':
                # Check stop loss
                if low <= pos['stop_loss']:
                    exit_price = pos['stop_loss'] - spread - slippage
                    exit_reason = 'STOP_LOSS'
                # Check take profit
                elif high >= pos['take_profit']:
                    exit_price = pos['take_profit'] - spread
                    exit_reason = 'TAKE_PROFIT'
            else:  # SELL
                # Check stop loss
                if high >= pos['stop_loss']:
                    exit_price = pos['stop_loss'] + spread + slippage
                    exit_reason = 'STOP_LOSS'
                # Check take profit
                elif low <= pos['take_profit']:
                    exit_price = pos['take_profit'] + spread
                    exit_reason = 'TAKE_PROFIT'
            
            if exit_price:
                self.close_trade(row, pos, exit_price, exit_reason)
                positions_to_close.append(idx)
        
        # Remove closed positions (reverse order to maintain indices)
        for idx in reversed(positions_to_close):
            self.open_positions.pop(idx)
    
    def close_trade(self, row, pos, exit_price, exit_reason):
        """Close trade"""
        # Calculate P/L
        if pos['type'] == 'BUY':
            pips = (exit_price - pos['entry_price']) / self.pip_size
        else:
            pips = (pos['entry_price'] - exit_price) / self.pip_size
        
        profit = pips * pos['lot_size'] * self.point_value * self.pip_size
        
        # Update balance
        self.balance += profit
        self.equity = self.balance
        
        # Record trade
        trade = {
            'strategy': pos['strategy'],
            'entry_time': pos['entry_time'],
            'exit_time': row.name if isinstance(row.name, pd.Timestamp) else row['datetime'],
            'type': pos['type'],
            'entry_price': pos['entry_price'],
            'exit_price': exit_price,
            'stop_loss': pos['stop_loss'],
            'take_profit': pos['take_profit'],
            'lot_size': pos['lot_size'],
            'risk_percent': pos['risk_percent'],
            'rr_ratio': pos['rr_ratio'],
            'pips': pips,
            'profit': profit,
            'balance': self.balance,
            'exit_reason': exit_reason,
            'confidence': pos['confidence']
        }
        
        self.trades.append(trade)
    
    def run_backtest(self, df):
        """Run backtest on H1 data"""
        print(f"\nProcessing {len(df)} H1 bars...")
        
        # Add indicators
        print("Adding indicators...")
        df = add_all_indicators(df)
        
        # Start from bar 250 (warm-up period)
        start_bar = min(250, len(df) - 1)
        
        # Track signal counts
        ma_signals = 0
        mw_signals = 0
        
        for i in range(start_bar, len(df)):
            row = df.iloc[i]
            
            # Check exit first (for all open positions)
            self.check_exit(row)
            
            # Look for new entry signals (always check, not just when no position)
            signal = self.strategy.detect_hybrid_signal(df, i)
            if signal:
                if signal.strategy == 'MA_H1':
                    ma_signals += 1
                else:
                    mw_signals += 1
                self.enter_trade(row, signal)
        
        print(f"\nSignal Detection Summary:")
        print(f"  MA H1 Signals Detected: {ma_signals}")
        print(f"  M&W Signals Detected: {mw_signals}")
        print(f"  Total Signals: {ma_signals + mw_signals}")
        print(f"  Total Trades Entered: {len(self.trades)}")
        
        # Close any open positions at end
        if self.open_positions:
            last_row = df.iloc[-1]
            for pos in list(self.open_positions):  # Copy list to avoid modification during iteration
                self.close_trade(last_row, pos, last_row['close'], 'END_OF_DATA')
            self.open_positions.clear()
        
        return self.calculate_results(df)
    
    def calculate_results(self, df):
        """Calculate backtest results"""
        if not self.trades:
            return {
                'total_trades': 0,
                'win_rate': 0,
                'net_profit': 0,
                'avg_daily_return_pct': 0
            }
        
        trades_df = pd.DataFrame(self.trades)
        
        # Basic stats
        total_trades = len(trades_df)
        wins = len(trades_df[trades_df['profit'] > 0])
        losses = len(trades_df[trades_df['profit'] <= 0])
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
        
        # Profit stats
        net_profit = trades_df['profit'].sum()
        total_return_pct = (net_profit / self.config['initial_balance']) * 100
        
        total_profit = trades_df[trades_df['profit'] > 0]['profit'].sum()
        total_loss = abs(trades_df[trades_df['profit'] <= 0]['profit'].sum())
        profit_factor = (total_profit / total_loss) if total_loss > 0 else 0
        
        # Time-based stats
        first_trade = trades_df['entry_time'].min()
        last_trade = trades_df['exit_time'].max()
        trading_days = max(1, (last_trade - first_trade).days)
        avg_daily_return_pct = total_return_pct / trading_days if trading_days > 0 else 0
        
        # Drawdown
        balance_history = trades_df['balance'].values
        peak = balance_history[0]
        max_dd = 0
        for balance in balance_history:
            if balance > peak:
                peak = balance
            dd = peak - balance
            if dd > max_dd:
                max_dd = dd
        
        max_dd_pct = (max_dd / self.config['initial_balance']) * 100
        
        # Average win/loss
        avg_win = trades_df[trades_df['profit'] > 0]['profit'].mean() if wins > 0 else 0
        avg_loss = trades_df[trades_df['profit'] <= 0]['profit'].mean() if losses > 0 else 0
        
        # Largest win/loss
        largest_win = trades_df['profit'].max()
        largest_loss = trades_df['profit'].min()
        
        # Strategy breakdown
        ma_trades = len(trades_df[trades_df['strategy'] == 'MA_H1'])
        mw_trades = len(trades_df[trades_df['strategy'] == 'MW_PATTERN'])
        
        ma_profit = trades_df[trades_df['strategy'] == 'MA_H1']['profit'].sum() if ma_trades > 0 else 0
        mw_profit = trades_df[trades_df['strategy'] == 'MW_PATTERN']['profit'].sum() if mw_trades > 0 else 0
        
        return {
            'total_trades': total_trades,
            'wins': wins,
            'losses': losses,
            'win_rate': win_rate,
            'net_profit': net_profit,
            'total_return_pct': total_return_pct,
            'avg_daily_return_pct': avg_daily_return_pct,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'profit_factor': profit_factor,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'largest_win': largest_win,
            'largest_loss': largest_loss,
            'max_drawdown': max_dd,
            'max_drawdown_pct': max_dd_pct,
            'final_balance': self.balance,
            'trading_days': trading_days,
            'trades_per_day': total_trades / trading_days if trading_days > 0 else 0,
            'first_trade': first_trade,
            'last_trade': last_trade,
            # Strategy breakdown
            'ma_trades': ma_trades,
            'mw_trades': mw_trades,
            'ma_profit': ma_profit,
            'mw_profit': mw_profit,
            'ma_percent': (ma_trades / total_trades * 100) if total_trades > 0 else 0,
            'mw_percent': (mw_trades / total_trades * 100) if total_trades > 0 else 0
        }


def run_hybrid_backtest(csv_files, initial_balance=100.0):
    """Run hybrid strategy backtest"""
    print("\n" + "="*80)
    print("HYBRID STRATEGY BACKTEST - MA H1 + M&W Pattern")
    print(f"Initial Balance: ${initial_balance:.2f}")
    print("Strategy 1: MA H1 Aggressive (6% risk, RR 1:3)")
    print("Strategy 2: M&W Pattern (1% risk, RR 1:1.5)")
    print("Priority: M&W Pattern > MA H1")
    print("="*80 + "\n")
    
    # Create config
    config = create_hybrid_config(initial_balance=initial_balance)
    
    # Create engine
    engine = HybridBacktestEngine(config)
    
    # Load and combine all M1 data
    all_m1_data = []
    for period, csv_path in csv_files.items():
        df = engine.load_csv_data(csv_path)
        all_m1_data.append(df)
    
    # Combine
    df_m1 = pd.concat(all_m1_data, axis=0)
    print(f"\nCombined data: {len(df_m1)} M1 bars")
    
    # Resample to H1
    df_h1 = engine.resample_to_h1(df_m1)
    
    # Run backtest
    results = engine.run_backtest(df_h1)
    
    # Print results
    print("\n" + "="*80)
    print("HYBRID STRATEGY RESULTS")
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
    print("\n" + "-"*80)
    print("STRATEGY BREAKDOWN:")
    print("-"*80)
    print(f"MA H1 Trades: {results['ma_trades']} ({results['ma_percent']:.1f}%)")
    print(f"MA H1 Profit: ${results['ma_profit']:.2f}")
    print(f"M&W Trades: {results['mw_trades']} ({results['mw_percent']:.1f}%)")
    print(f"M&W Profit: ${results['mw_profit']:.2f}")
    print("="*80 + "\n")
    
    # Generate report
    generate_report(engine.trades, results)
    
    return results, engine.trades


def generate_report(trades, results):
    """Generate detailed report"""
    os.makedirs('reports', exist_ok=True)
    
    # Save trades to CSV
    if trades:
        trades_df = pd.DataFrame(trades)
        trades_df.to_csv('reports/hybrid_trades.csv', index=False)
        print("Trade log saved: reports/hybrid_trades.csv")
        
        # Generate equity curve
        fig, ax = plt.subplots(figsize=(14, 7))
        
        # Plot equity curve
        ax.plot(range(len(trades_df)), trades_df['balance'].values, 
                label='Equity', color='blue', linewidth=2)
        ax.axhline(y=results['final_balance'] - results['max_drawdown'], 
                   color='red', linestyle='--', alpha=0.5, label='Max Drawdown')
        ax.axhline(y=100, color='gray', linestyle='--', alpha=0.3, label='Initial Balance')
        
        # Mark MA vs M&W trades
        ma_trades = trades_df[trades_df['strategy'] == 'MA_H1']
        mw_trades = trades_df[trades_df['strategy'] == 'MW_PATTERN']
        
        if len(ma_trades) > 0:
            ma_indices = ma_trades.index.tolist()
            ax.scatter(ma_indices, ma_trades['balance'].values, 
                      color='green', marker='o', s=30, alpha=0.6, label='MA H1 Trades')
        
        if len(mw_trades) > 0:
            mw_indices = mw_trades.index.tolist()
            ax.scatter(mw_indices, mw_trades['balance'].values,
                      color='purple', marker='^', s=50, alpha=0.8, label='M&W Trades')
        
        ax.set_xlabel('Trade Number', fontsize=12)
        ax.set_ylabel('Balance ($)', fontsize=12)
        ax.set_title('Hybrid Strategy Equity Curve - MA H1 + M&W Pattern', 
                     fontsize=14, fontweight='bold')
        ax.legend(loc='best')
        ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('reports/hybrid_equity_curve.png', dpi=150)
        print("Equity curve saved: reports/hybrid_equity_curve.png")
        plt.close()
    
    # Save text report
    report_path = 'reports/hybrid_backtest_report.txt'
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write("="*80 + "\n")
        f.write("HYBRID STRATEGY BACKTEST REPORT\n")
        f.write("MA H1 Aggressive + M&W Pattern\n")
        f.write("="*80 + "\n\n")
        
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Initial Balance: $100.00\n")
        f.write(f"Strategy Combination:\n")
        f.write(f"  1. MA H1 Aggressive: 6% risk, RR 1:3, Compound ON\n")
        f.write(f"  2. M&W Pattern: 1% risk, RR 1:1.5\n")
        f.write(f"  Priority: M&W Pattern > MA H1\n\n")
        
        f.write("="*80 + "\n")
        f.write("OVERALL RESULTS\n")
        f.write("="*80 + "\n\n")
        
        f.write(f"Total Trades: {results['total_trades']} ({results['wins']}W / {results['losses']}L)\n")
        f.write(f"Win Rate: {results['win_rate']:.2f}%\n")
        f.write(f"Net Profit: ${results['net_profit']:.2f} ({results['total_return_pct']:.2f}%)\n")
        f.write(f"Average Daily Return: {results['avg_daily_return_pct']:.2f}%\n")
        f.write(f"Profit Factor: {results['profit_factor']:.2f}\n")
        f.write(f"Max Drawdown: ${results['max_drawdown']:.2f} ({results['max_drawdown_pct']:.2f}%)\n")
        f.write(f"Final Balance: ${results['final_balance']:.2f}\n\n")
        
        f.write(f"Average Win: ${results['avg_win']:.2f}\n")
        f.write(f"Average Loss: ${results['avg_loss']:.2f}\n")
        f.write(f"Largest Win: ${results['largest_win']:.2f}\n")
        f.write(f"Largest Loss: ${results['largest_loss']:.2f}\n\n")
        
        f.write(f"Trading Period: {results['trading_days']} days\n")
        f.write(f"Trades per Day: {results['trades_per_day']:.2f}\n")
        f.write(f"First Trade: {results['first_trade']}\n")
        f.write(f"Last Trade: {results['last_trade']}\n\n")
        
        f.write("="*80 + "\n")
        f.write("STRATEGY BREAKDOWN\n")
        f.write("="*80 + "\n\n")
        
        f.write(f"MA H1 Aggressive:\n")
        f.write(f"  Trades: {results['ma_trades']} ({results['ma_percent']:.1f}% of total)\n")
        f.write(f"  Profit: ${results['ma_profit']:.2f}\n")
        f.write(f"  Avg per Trade: ${results['ma_profit']/results['ma_trades']:.2f}\n\n" if results['ma_trades'] > 0 else "  N/A\n\n")
        
        f.write(f"M&W Pattern:\n")
        f.write(f"  Trades: {results['mw_trades']} ({results['mw_percent']:.1f}% of total)\n")
        f.write(f"  Profit: ${results['mw_profit']:.2f}\n")
        f.write(f"  Avg per Trade: ${results['mw_profit']/results['mw_trades']:.2f}\n\n" if results['mw_trades'] > 0 else "  N/A\n\n")
        
        f.write("="*80 + "\n")
        f.write("CONCLUSION\n")
        f.write("="*80 + "\n\n")
        
        if results['avg_daily_return_pct'] >= 2.5:
            f.write(f"✅ EXCELLENT: {results['avg_daily_return_pct']:.2f}% daily return meets hybrid target (2.5-3.5%)\n")
        elif results['avg_daily_return_pct'] >= 2.0:
            f.write(f"✅ GOOD: {results['avg_daily_return_pct']:.2f}% daily return close to target\n")
        elif results['avg_daily_return_pct'] >= 1.0:
            f.write(f"⚠️ MODERATE: {results['avg_daily_return_pct']:.2f}% daily return below target\n")
        else:
            f.write(f"❌ POOR: {results['avg_daily_return_pct']:.2f}% daily return significantly below target\n")
        
        f.write("\n")
    
    print(f"Report saved: {report_path}\n")


if __name__ == '__main__':
    # CSV files (M1 data)
    csv_files = {
        '202602': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
        '202603': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
        '202604': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv'
    }
    
    # Run hybrid backtest
    results, trades = run_hybrid_backtest(csv_files, initial_balance=100.0)
