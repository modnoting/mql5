"""
MA Crossover Backtesting Engine (MACD + Trend Filter)
Tests MACD crossover signals on M5 timeframe with MA50/200 filter and ADX confirmation
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime
import matplotlib.pyplot as plt

# Import custom modules
from indicators_updated import add_all_indicators
from ma_crossover_strategy import SignalInfo, detect_signal


class TradeRecord:
    """Record of a single trade"""
    def __init__(self):
        self.trade_id = 0
        self.open_time = None
        self.close_time = None
        self.type = ''  # 'BUY' or 'SELL'
        self.signal_type = ''  # 'MACD_CROSSOVER'
        self.entry_price = 0.0
        self.exit_price = 0.0
        self.sl_price = 0.0
        self.tp_price = 0.0
        self.lot_size = 0.0
        self.profit_amount = 0.0
        self.profit_pips = 0.0
        self.status = 'OPEN'  # 'OPEN', 'TP', 'SL', 'CLOSED_EOD'
        self.signal_strength = 0.0
        self.adx_value = 0.0
        self.trend_direction = ''


class BacktestEngine:
    """Main backtesting engine for MA Crossover"""
    
    def __init__(self, config):
        self.config = config
        self.balance = config['initial_balance']
        self.equity = config['initial_balance']
        self.trades = []
        self.equity_history = []
        self.trade_counter = 0
        
    def load_csv_data(self, csv_path):
        """Load M1 CSV data"""
        print(f"Loading CSV data from: {csv_path}")
        
        # Read CSV with 7 columns (no header)
        df = pd.read_csv(csv_path, header=None, 
                         names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
        
        # Combine date and time
        df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])
        df = df.set_index('datetime')
        df = df[['open', 'high', 'low', 'close', 'volume']]
        
        print(f"  Loaded {len(df)} M1 bars")
        print(f"  Date range: {df.index[0]} to {df.index[-1]}")
        
        return df
    
    def resample_to_m5(self, df_m1):
        """Resample M1 to M5"""
        print("Resampling M1 data to M5...")
        
        df_m5 = df_m1.resample('5min').agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        # Reset index to have datetime as column
        df_m5 = df_m5.reset_index()
        
        print(f"  Resampled to {len(df_m5)} M5 bars")
        return df_m5
    
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
        
        # Reset index to have datetime as column
        df_h1 = df_h1.reset_index()
        
        print(f"  Resampled to {len(df_h1)} H1 bars")
        return df_h1
    
    def calculate_lot_size(self, entry_price, sl_price):
        """Calculate lot size based on risk percentage"""
        risk_amount = self.balance * (self.config['risk_percent'] / 100)
        
        # Calculate pip distance
        pip_distance = abs(entry_price - sl_price) / self.config['pip_size']
        
        if pip_distance == 0:
            return self.config['min_lot']
        
        # Lot size = Risk Amount / (Pip Distance * Point Value)
        lot_size = risk_amount / (pip_distance * self.config['point_value'])
        
        # Round to lot step
        lot_size = round(lot_size / self.config['lot_step']) * self.config['lot_step']
        
        # Apply limits
        lot_size = max(self.config['min_lot'], min(lot_size, self.config['max_lot']))
        
        return lot_size
    
    def calculate_atr_based_sl(self, df, i, entry_price, trade_type):
        """Calculate SL based on ATR"""
        atr = df.loc[i, 'ATR']
        if pd.isna(atr) or atr == 0:
            atr = 3.0  # Default ATR for XAUUSD
        
        atr_multiplier = self.config['atr_multiplier']
        
        if trade_type == 'BUY':
            sl_price = entry_price - (atr * atr_multiplier)
        else:  # SELL
            sl_price = entry_price + (atr * atr_multiplier)
        
        return sl_price
    
    def calculate_tp_from_rr(self, entry_price, sl_price, trade_type):
        """Calculate TP based on R:R ratio"""
        risk_distance = abs(entry_price - sl_price)
        reward_distance = risk_distance * self.config['rr_ratio']
        
        if trade_type == 'BUY':
            tp_price = entry_price + reward_distance
        else:  # SELL
            tp_price = entry_price - reward_distance
        
        return tp_price
    
    def open_trade(self, df, i, signal):
        """Open a new trade based on signal"""
        self.trade_counter += 1
        
        entry_price = df.loc[i, 'close']
        trade_type = signal.signal_type
        
        # Calculate ATR-based SL
        sl_price = self.calculate_atr_based_sl(df, i, entry_price, trade_type)
        
        # Calculate TP based on RR ratio
        tp_price = self.calculate_tp_from_rr(entry_price, sl_price, trade_type)
        
        # Calculate lot size
        lot_size = self.calculate_lot_size(entry_price, sl_price)
        
        # Create trade record
        trade = TradeRecord()
        trade.trade_id = self.trade_counter
        trade.open_time = signal.signal_time
        trade.type = trade_type
        trade.signal_type = 'MACD_CROSSOVER'
        trade.entry_price = entry_price
        trade.sl_price = sl_price
        trade.tp_price = tp_price
        trade.lot_size = lot_size
        trade.signal_strength = signal.signal_strength
        trade.adx_value = signal.adx_value
        trade.trend_direction = signal.trend_direction
        trade.status = 'OPEN'
        
        self.trades.append(trade)
        
        # Deduct spread from balance
        spread_cost = self.config['spread_pips'] * self.config['point_value'] * lot_size
        self.balance -= spread_cost
        
        risk_pips = abs(entry_price - sl_price) / self.config['pip_size']
        reward_pips = abs(tp_price - entry_price) / self.config['pip_size']
        
        print(f"\n{'='*60}")
        print(f"[TRADE OPENED] #{trade.trade_id}")
        print(f"Time: {signal.signal_time}")
        print(f"Type: {trade_type} (MACD_CROSSOVER)")
        print(f"Entry: {entry_price:.2f}")
        print(f"SL: {sl_price:.2f} ({risk_pips:.1f} pips)")
        print(f"TP: {tp_price:.2f} ({reward_pips:.1f} pips)")
        print(f"Lot: {lot_size:.2f}")
        print(f"Signal Strength: {signal.signal_strength:.2f}")
        print(f"ADX: {signal.adx_value:.1f}")
        print(f"Trend: {signal.trend_direction}")
        print(f"MACD Histogram: {signal.histogram_value:.2f}")
        print(f"{'='*60}\n")
    
    def update_open_positions(self, df, i):
        """Update open positions and check for TP/SL"""
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        
        current_time = df.loc[i, 'datetime']
        current_high = df.loc[i, 'high']
        current_low = df.loc[i, 'low']
        
        for trade in open_trades:
            if trade.type == 'BUY':
                # Check TP hit
                if current_high >= trade.tp_price:
                    trade.close_time = current_time
                    trade.exit_price = trade.tp_price
                    trade.status = 'TP'
                    
                    pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
                    pips -= self.config['execution_penalty_pips']
                    trade.profit_pips = pips
                    trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                    
                    self.balance += trade.profit_amount
                    self.equity = self.balance
                    
                    print(f"\n{'='*60}")
                    print(f"[TRADE CLOSED] #{trade.trade_id}")
                    print(f"Time: {current_time}")
                    print(f"Status: TP")
                    print(f"Entry: {trade.entry_price:.2f} -> Exit: {trade.exit_price:.2f}")
                    print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                    print(f"New Balance: ${self.balance:.2f}")
                    print(f"{'='*60}\n")
                
                # Check SL hit
                elif current_low <= trade.sl_price:
                    trade.close_time = current_time
                    trade.exit_price = trade.sl_price
                    trade.status = 'SL'
                    
                    pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
                    pips -= self.config['execution_penalty_pips']
                    trade.profit_pips = pips
                    trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                    
                    self.balance += trade.profit_amount
                    self.equity = self.balance
                    
                    print(f"\n{'='*60}")
                    print(f"[TRADE CLOSED] #{trade.trade_id}")
                    print(f"Time: {current_time}")
                    print(f"Status: SL")
                    print(f"Entry: {trade.entry_price:.2f} -> Exit: {trade.exit_price:.2f}")
                    print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                    print(f"New Balance: ${self.balance:.2f}")
                    print(f"{'='*60}\n")
            
            else:  # SELL
                # Check TP hit
                if current_low <= trade.tp_price:
                    trade.close_time = current_time
                    trade.exit_price = trade.tp_price
                    trade.status = 'TP'
                    
                    pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
                    pips -= self.config['execution_penalty_pips']
                    trade.profit_pips = pips
                    trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                    
                    self.balance += trade.profit_amount
                    self.equity = self.balance
                    
                    print(f"\n{'='*60}")
                    print(f"[TRADE CLOSED] #{trade.trade_id}")
                    print(f"Time: {current_time}")
                    print(f"Status: TP")
                    print(f"Entry: {trade.entry_price:.2f} -> Exit: {trade.exit_price:.2f}")
                    print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                    print(f"New Balance: ${self.balance:.2f}")
                    print(f"{'='*60}\n")
                
                # Check SL hit
                elif current_high >= trade.sl_price:
                    trade.close_time = current_time
                    trade.exit_price = trade.sl_price
                    trade.status = 'SL'
                    
                    pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
                    pips -= self.config['execution_penalty_pips']
                    trade.profit_pips = pips
                    trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                    
                    self.balance += trade.profit_amount
                    self.equity = self.balance
                    
                    print(f"\n{'='*60}")
                    print(f"[TRADE CLOSED] #{trade.trade_id}")
                    print(f"Time: {current_time}")
                    print(f"Status: SL")
                    print(f"Entry: {trade.entry_price:.2f} -> Exit: {trade.exit_price:.2f}")
                    print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                    print(f"New Balance: ${self.balance:.2f}")
                    print(f"{'='*60}\n")
    
    def run_backtest(self, df_m5, df_h1=None):
        """Run the backtest"""
        print("\n" + "="*60)
        print("STARTING BACKTEST")
        print("="*60 + "\n")
        
        print("Adding indicators to M5 data...")
        df_m5 = add_all_indicators(df_m5)
        
        if df_h1 is not None and self.config['use_htf_confirmation']:
            print("Adding indicators to H1 data...")
            df_h1 = add_all_indicators(df_h1)
        
        print(f"Processing {len(df_m5)} M5 bars...")
        
        # Start from bar 250 (warm-up period for indicators)
        start_bar = 250
        
        for i in range(start_bar, len(df_m5)):
            current_time = df_m5.loc[i, 'datetime']
            
            # Update open positions first
            self.update_open_positions(df_m5, i)
            
            # Track equity
            self.equity_history.append({
                'time': current_time,
                'balance': self.balance,
                'equity': self.equity
            })
            
            # Detect signal
            signal = detect_signal(df_m5, i, self.config)
            
            if signal is not None:
                # Open trade
                self.open_trade(df_m5, i, signal)
        
        # Close any remaining open trades at end of data
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        for trade in open_trades:
            last_time = df_m5.loc[len(df_m5)-1, 'datetime']
            last_close = df_m5.loc[len(df_m5)-1, 'close']
            
            trade.close_time = last_time
            trade.exit_price = last_close
            trade.status = 'CLOSED_EOD'
            
            if trade.type == 'BUY':
                pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
            else:
                pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
            
            pips -= self.config['execution_penalty_pips']
            trade.profit_pips = pips
            trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
            
            self.balance += trade.profit_amount
            self.equity = self.balance
        
        # Calculate final metrics
        closed_trades = [t for t in self.trades if t.status in ['TP', 'SL', 'CLOSED_EOD']]
        
        if len(closed_trades) == 0:
            print("\nNo trades were executed.")
            return None
        
        # Calculate metrics
        total_trades = len(closed_trades)
        winning_trades = [t for t in closed_trades if t.profit_amount > 0]
        losing_trades = [t for t in closed_trades if t.profit_amount <= 0]
        
        wins = len(winning_trades)
        losses = len(losing_trades)
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
        
        total_profit = sum(t.profit_amount for t in winning_trades)
        total_loss = abs(sum(t.profit_amount for t in losing_trades))
        net_profit = sum(t.profit_amount for t in closed_trades)
        
        profit_factor = (total_profit / total_loss) if total_loss > 0 else 0
        
        # Drawdown
        equity_values = [e['balance'] for e in self.equity_history]
        peak = self.config['initial_balance']
        max_dd = 0
        for eq in equity_values:
            if eq > peak:
                peak = eq
            dd = peak - eq
            if dd > max_dd:
                max_dd = dd
        
        max_dd_pct = (max_dd / self.config['initial_balance'] * 100)
        
        # Signal statistics
        buy_signals = [t for t in closed_trades if t.type == 'BUY']
        sell_signals = [t for t in closed_trades if t.type == 'SELL']
        
        print("\n" + "="*60)
        print("BACKTEST COMPLETED")
        print("="*60)
        print(f"Final Balance: ${self.balance:.2f}")
        print(f"Total Trades: {total_trades}")
        print("="*60 + "\n")
        
        results = {
            'total_trades': total_trades,
            'wins': wins,
            'losses': losses,
            'win_rate': win_rate,
            'net_profit': net_profit,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'profit_factor': profit_factor,
            'max_drawdown': max_dd,
            'max_drawdown_pct': max_dd_pct,
            'final_balance': self.balance,
            'buy_signals': len(buy_signals),
            'sell_signals': len(sell_signals)
        }
        
        return results
    
    def export_trade_log(self, output_path):
        """Export trade log to CSV"""
        if len(self.trades) == 0:
            return
        
        trade_data = []
        for trade in self.trades:
            trade_data.append({
                'trade_id': trade.trade_id,
                'open_time': trade.open_time,
                'close_time': trade.close_time,
                'type': trade.type,
                'signal': trade.signal_type,
                'entry': trade.entry_price,
                'exit': trade.exit_price,
                'sl': trade.sl_price,
                'tp': trade.tp_price,
                'lot_size': trade.lot_size,
                'profit_pips': trade.profit_pips,
                'profit_amount': trade.profit_amount,
                'status': trade.status,
                'signal_strength': trade.signal_strength,
                'adx': trade.adx_value,
                'trend': trade.trend_direction
            })
        
        df = pd.DataFrame(trade_data)
        df.to_csv(output_path, index=False)
        print(f"Trade log exported to: {output_path}")
    
    def plot_equity_curve(self, output_path):
        """Generate equity curve chart"""
        if len(self.equity_history) == 0:
            print("No equity data to plot")
            return
        
        df_equity = pd.DataFrame(self.equity_history)
        
        plt.figure(figsize=(14, 7))
        plt.plot(df_equity['time'], df_equity['equity'], label='Equity', linewidth=2, color='blue')
        plt.axhline(y=self.config['initial_balance'], color='gray', linestyle='--', label='Initial Balance')
        
        plt.xlabel('Time', fontsize=12)
        plt.ylabel('Equity ($)', fontsize=12)
        plt.title('Equity Curve - MA Crossover Strategy', fontsize=14, fontweight='bold')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        plt.savefig(output_path, dpi=150)
        print(f"Equity curve saved to: {output_path}")
        plt.close()


def create_default_config():
    """Create default configuration for MA Crossover"""
    return {
        # Account settings
        'initial_balance': 10000.0,
        'risk_percent': 1.0,
        'min_lot': 0.01,
        'max_lot': 100.0,
        'lot_step': 0.01,
        
        # Timeframe settings
        'timeframe': 'M5',
        'use_htf_confirmation': False,  # MACD already includes trend info
        'htf_multiplier': 12,  # H1 = 12x M5
        
        # Symbol settings (XAUUSD)
        'pip_size': 0.1,
        'point_value': 1.0,
        'spread_pips': 20,
        'execution_penalty_pips': 5,
        
        # Risk/Reward
        'rr_ratio': 2.0,  # 1:2 Risk:Reward
        'atr_multiplier': 2.0,  # SL = ATR * 2.0
        
        # MACD settings (standard)
        'macd_fast': 12,
        'macd_slow': 26,
        'macd_signal': 9,
        
        # Filters
        'use_trend_filter': True,  # MA50/MA200 trend filter
        'use_adx_filter': True,  # ADX strength filter
        'min_adx': 20,  # Minimum ADX for trending market
    }


def main():
    """Main function to run backtest"""
    
    # Create reports directory
    reports_dir = "reports"
    if not os.path.exists(reports_dir):
        os.makedirs(reports_dir)
    
    # CSV files
    csv_files = {
        '2026_02': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
        '2026_03': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
        '2026_04': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv',
    }
    
    all_results = {}
    
    for period, csv_path in csv_files.items():
        print("\n" + "="*80)
        print(f"BACKTESTING PERIOD: {period}")
        print("="*80 + "\n")
        
        # Create config
        config = create_default_config()
        
        # Create engine
        engine = BacktestEngine(config)
        
        # Load and resample data
        df_m1 = engine.load_csv_data(csv_path)
        df_m5 = engine.resample_to_m5(df_m1)
        df_h1 = None  # Not using HTF confirmation for MACD
        
        # Run backtest
        results = engine.run_backtest(df_m5, df_h1)
        all_results[period] = results
        
        # Export results
        engine.export_trade_log(f"{reports_dir}/trade_log_ma_{period}.csv")
        engine.plot_equity_curve(f"{reports_dir}/equity_curve_ma_{period}.png")
        
        # Print summary
        if results:
            print("\n" + "="*60)
            print(f"SUMMARY FOR {period}")
            print("="*60)
            print(f"Net Profit: ${results['net_profit']:.2f} ({results['net_profit']/config['initial_balance']*100:.2f}%)")
            print(f"Total Trades: {results['total_trades']} (W:{results['wins']} L:{results['losses']})")
            print(f"Win Rate: {results['win_rate']:.2f}%")
            print(f"Profit Factor: {results['profit_factor']:.2f}")
            print(f"Max Drawdown: ${results['max_drawdown']:.2f} ({results['max_drawdown_pct']:.2f}%)")
            print(f"  BUY signals: {results['buy_signals']} trades")
            print(f"  SELL signals: {results['sell_signals']} trades")
            print("="*60)
    
    # Print overall summary
    print("\n" + "="*80)
    print("OVERALL PERFORMANCE SUMMARY")
    print("="*80)
    print(f"{'Period':<15} {'Net P/L':<15} {'Trades':<10} {'Win Rate':<12} {'Profit Factor':<15} {'Max DD%':<10}")
    print("-"*80)
    
    for period, results in all_results.items():
        if results:
            print(f"{period:<15} ${results['net_profit']:>10.2f}     "
                  f"{results['total_trades']:<10} {results['win_rate']:>6.2f}%      "
                  f"{results['profit_factor']:>6.2f}          {results['max_drawdown_pct']:>6.2f}%")
    
    print("="*80 + "\n")


if __name__ == '__main__':
    main()
