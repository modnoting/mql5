"""
Engulfing + Multi-Confirmation Backtesting Engine - M15
Tests engulfing patterns with 4-filter confirmation (MA + ADX + ROC + RSI) on M15 timeframe
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime
import matplotlib.pyplot as plt

# Import custom modules
from indicators_updated import add_all_indicators
from engulfing_multiconf_strategy import detect_engulfing_with_confirmation


class TradeRecord:
    """Record of a single trade"""
    def __init__(self):
        self.trade_id = 0
        self.open_time = None
        self.close_time = None
        self.type = ''  # 'BUY' or 'SELL'
        self.signal_type = ''  # 'BULLISH_ENGULFING' or 'BEARISH_ENGULFING'
        self.entry_price = 0.0
        self.exit_price = 0.0
        self.sl_price = 0.0
        self.tp_price = 0.0
        self.lot_size = 0.0
        self.profit_amount = 0.0
        self.profit_pips = 0.0
        self.status = 'OPEN'  # 'OPEN', 'TP', 'SL', 'CLOSED_EOD'
        self.signal_strength = 0.0
        self.filter_count = ''
        self.ma_trend = ''
        self.adx_value = 0.0
        self.roc_value = 0.0
        self.rsi_value = 0.0


class BacktestEngine:
    """Main backtesting engine for Engulfing + Multi-Confirmation M15"""
    
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
    
    def resample_to_m15(self, df_m1):
        """Resample M1 to M15"""
        print("Resampling M1 data to M15...")
        
        df_m15 = df_m1.resample('15min').agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        # Reset index to have datetime as column
        df_m15 = df_m15.reset_index()
        
        print(f"  Resampled to {len(df_m15)} M15 bars")
        return df_m15
    
    def calculate_lot_size(self, entry_price, sl_price):
        """Calculate lot size based on risk percentage"""
        risk_amount = self.balance * self.config['risk_percent']
        
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
    
    def open_trade(self, df, i, pattern_info, confirmation):
        """Open a new trade based on pattern and confirmation"""
        self.trade_counter += 1
        
        entry_price = df.loc[i, 'close']
        trade_type = confirmation.signal_type  # 'BUY' or 'SELL'
        
        # Calculate ATR-based SL
        sl_price = self.calculate_atr_based_sl(df, i, entry_price, trade_type)
        
        # Calculate TP based on RR ratio
        tp_price = self.calculate_tp_from_rr(entry_price, sl_price, trade_type)
        
        # Calculate lot size
        lot_size = self.calculate_lot_size(entry_price, sl_price)
        
        # Create trade record
        trade = TradeRecord()
        trade.trade_id = self.trade_counter
        trade.open_time = pattern_info.signal_time
        trade.type = trade_type
        trade.signal_type = pattern_info.pattern_type
        trade.entry_price = entry_price
        trade.sl_price = sl_price
        trade.tp_price = tp_price
        trade.lot_size = lot_size
        trade.signal_strength = confirmation.signal_strength
        trade.filter_count = confirmation.filter_count
        trade.ma_trend = confirmation.ma_trend
        trade.adx_value = confirmation.adx_value
        trade.roc_value = confirmation.roc_value
        trade.rsi_value = confirmation.rsi_value
        trade.status = 'OPEN'
        
        self.trades.append(trade)
        
        # Deduct spread from balance
        spread_cost = self.config['spread'] * self.config['point_value'] * lot_size
        self.balance -= spread_cost
        
        risk_pips = abs(entry_price - sl_price) / self.config['pip_size']
        reward_pips = abs(tp_price - entry_price) / self.config['pip_size']
        
        print(f"\n{'='*70}")
        print(f"[TRADE OPENED] #{trade.trade_id}")
        print(f"Time: {pattern_info.signal_time}")
        print(f"Type: {trade_type} ({pattern_info.pattern_type})")
        print(f"Entry: {entry_price:.2f}")
        print(f"SL: {sl_price:.2f} ({risk_pips:.1f} pips)")
        print(f"TP: {tp_price:.2f} ({reward_pips:.1f} pips)")
        print(f"Lot: {lot_size:.2f}")
        print(f"Filters Passed: {confirmation.filter_count}")
        for filter_desc in confirmation.filters_passed:
            print(f"  [PASS] {filter_desc}")
        print(f"{'='*70}")
        
        return trade
    
    def update_open_positions(self, df, i):
        """Update all open positions - check TP/SL hits"""
        current_time = df.loc[i, 'datetime']
        current_high = df.loc[i, 'high']
        current_low = df.loc[i, 'low']
        current_close = df.loc[i, 'close']
        
        for trade in self.trades:
            if trade.status != 'OPEN':
                continue
            
            # Check if TP or SL hit
            if trade.type == 'BUY':
                # Check TP hit
                if current_high >= trade.tp_price:
                    self.close_trade(trade, trade.tp_price, current_time, 'TP')
                # Check SL hit
                elif current_low <= trade.sl_price:
                    self.close_trade(trade, trade.sl_price, current_time, 'SL')
            
            else:  # SELL
                # Check TP hit
                if current_low <= trade.tp_price:
                    self.close_trade(trade, trade.tp_price, current_time, 'TP')
                # Check SL hit
                elif current_high >= trade.sl_price:
                    self.close_trade(trade, trade.sl_price, current_time, 'SL')
    
    def close_trade(self, trade, exit_price, exit_time, status):
        """Close a trade"""
        trade.close_time = exit_time
        trade.exit_price = exit_price
        trade.status = status
        
        # Calculate profit
        if trade.type == 'BUY':
            price_diff = exit_price - trade.entry_price
        else:  # SELL
            price_diff = trade.entry_price - exit_price
        
        # Subtract spread and execution penalty
        price_diff -= (self.config['spread'] + self.config['execution_penalty'])
        
        # Calculate profit in pips and dollars
        trade.profit_pips = price_diff / self.config['pip_size']
        trade.profit_amount = price_diff * self.config['point_value'] * trade.lot_size
        
        # Update balance
        self.balance += trade.profit_amount
        
        # Print trade result
        result_symbol = '+' if trade.profit_amount > 0 else ''
        print(f"\n[TRADE CLOSED] #{trade.trade_id} - {status}")
        print(f"  Exit: {exit_price:.2f} | Profit: {result_symbol}${trade.profit_amount:.2f} ({result_symbol}{trade.profit_pips:.1f} pips)")
        print(f"  Balance: ${self.balance:.2f}")
    
    def run_backtest(self, df_m15, period_name):
        """Main backtest loop"""
        print(f"\n{'='*70}")
        print(f"BACKTEST STARTED: {period_name}")
        print(f"Initial Balance: ${self.balance:.2f}")
        print(f"{'='*70}")
        
        # Add indicators
        print("\nAdding technical indicators...")
        df_m15 = add_all_indicators(df_m15)
        
        # Set datetime as column (not index) for iloc access
        if 'datetime' not in df_m15.columns:
            df_m15 = df_m15.reset_index()
        
        # Main backtest loop
        for i in range(200, len(df_m15)):  # Start after indicator warmup
            # Update open positions first
            self.update_open_positions(df_m15, i)
            
            # Check for new signals only if no open trades
            open_trades = [t for t in self.trades if t.status == 'OPEN']
            if len(open_trades) > 0:
                continue
            
            # Detect engulfing pattern with multi-confirmation
            pattern_info, confirmation = detect_engulfing_with_confirmation(df_m15, i, self.config)
            
            if pattern_info is not None and confirmation is not None:
                if confirmation.signal_valid:
                    # Open trade
                    self.open_trade(df_m15, i, pattern_info, confirmation)
            
            # Track equity
            open_profit = sum([
                self.calculate_floating_profit(df_m15, i, t) 
                for t in self.trades if t.status == 'OPEN'
            ])
            self.equity = self.balance + open_profit
            self.equity_history.append({
                'datetime': df_m15.loc[i, 'datetime'],
                'equity': self.equity,
                'balance': self.balance
            })
        
        # Close any remaining open trades at EOD
        last_idx = len(df_m15) - 1
        for trade in self.trades:
            if trade.status == 'OPEN':
                exit_price = df_m15.loc[last_idx, 'close']
                exit_time = df_m15.loc[last_idx, 'datetime']
                self.close_trade(trade, exit_price, exit_time, 'CLOSED_EOD')
        
        print(f"\n{'='*70}")
        print(f"BACKTEST COMPLETED")
        print(f"Total Trades: {len(self.trades)}")
        print(f"Final Balance: ${self.balance:.2f}")
        print(f"{'='*70}\n")
    
    def calculate_floating_profit(self, df, i, trade):
        """Calculate floating profit for open trade"""
        if trade.status != 'OPEN':
            return 0
        
        current_price = df.loc[i, 'close']
        
        if trade.type == 'BUY':
            price_diff = current_price - trade.entry_price
        else:
            price_diff = trade.entry_price - current_price
        
        floating_profit = price_diff * self.config['point_value'] * trade.lot_size
        return floating_profit
    
    def export_results(self, period_name):
        """Export results to CSV and generate reports"""
        if not os.path.exists('reports'):
            os.makedirs('reports')
        
        # Export trade log
        trade_data = []
        for trade in self.trades:
            trade_data.append({
                'trade_id': trade.trade_id,
                'open_time': trade.open_time,
                'close_time': trade.close_time,
                'type': trade.type,
                'signal_type': trade.signal_type,
                'entry_price': trade.entry_price,
                'exit_price': trade.exit_price,
                'sl_price': trade.sl_price,
                'tp_price': trade.tp_price,
                'lot_size': trade.lot_size,
                'profit_pips': trade.profit_pips,
                'profit_amount': trade.profit_amount,
                'status': trade.status,
                'filter_count': trade.filter_count,
                'adx': trade.adx_value,
                'roc': trade.roc_value,
                'rsi': trade.rsi_value
            })
        
        df_trades = pd.DataFrame(trade_data)
        csv_path = f'reports/trade_log_engulf_{period_name}.csv'
        df_trades.to_csv(csv_path, index=False)
        print(f"Trade log exported to: {csv_path}")
        
        # Generate equity curve
        if len(self.equity_history) > 0:
            df_equity = pd.DataFrame(self.equity_history)
            
            plt.figure(figsize=(12, 6))
            plt.plot(df_equity['datetime'], df_equity['equity'], label='Equity', linewidth=2)
            plt.plot(df_equity['datetime'], df_equity['balance'], label='Balance', linewidth=1, alpha=0.7)
            plt.title(f'Equity Curve - Engulfing Multi-Conf {period_name}')
            plt.xlabel('Date')
            plt.ylabel('Account Value ($)')
            plt.legend()
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            
            img_path = f'reports/equity_curve_engulf_{period_name}.png'
            plt.savefig(img_path, dpi=100)
            plt.close()
            print(f"Equity curve saved to: {img_path}")
    
    def print_summary(self, period_name):
        """Print performance summary"""
        if len(self.trades) == 0:
            print("No trades executed")
            return
        
        winning_trades = [t for t in self.trades if t.profit_amount > 0]
        losing_trades = [t for t in self.trades if t.profit_amount <= 0]
        
        total_profit = sum([t.profit_amount for t in winning_trades])
        total_loss = abs(sum([t.profit_amount for t in losing_trades]))
        net_profit = self.balance - self.config['initial_balance']
        
        win_rate = len(winning_trades) / len(self.trades) * 100 if len(self.trades) > 0 else 0
        profit_factor = total_profit / total_loss if total_loss > 0 else 0
        
        # Calculate max drawdown
        peak = self.config['initial_balance']
        max_dd = 0
        for equity_point in self.equity_history:
            if equity_point['equity'] > peak:
                peak = equity_point['equity']
            dd = peak - equity_point['equity']
            if dd > max_dd:
                max_dd = dd
        
        max_dd_pct = (max_dd / self.config['initial_balance']) * 100
        
        print(f"\n{'='*70}")
        print(f"SUMMARY FOR {period_name}")
        print(f"Net Profit: ${net_profit:.2f} ({net_profit/self.config['initial_balance']*100:.2f}%)")
        print(f"Total Trades: {len(self.trades)} (W:{len(winning_trades)} L:{len(losing_trades)})")
        print(f"Win Rate: {win_rate:.2f}%")
        print(f"Profit Factor: {profit_factor:.2f}")
        print(f"Max Drawdown: ${max_dd:.2f} ({max_dd_pct:.2f}%)")
        
        # Count by signal type
        buy_trades = [t for t in self.trades if t.type == 'BUY']
        sell_trades = [t for t in self.trades if t.type == 'SELL']
        print(f"  BUY signals: {len(buy_trades)} trades")
        print(f"  SELL signals: {len(sell_trades)} trades")
        print(f"{'='*70}\n")


def create_m15_config():
    """Create configuration for M15 Engulfing Multi-Confirmation strategy"""
    return {
        # Account settings
        'initial_balance': 10000,
        'risk_percent': 0.01,  # 1% per trade
        'min_lot': 0.01,
        'max_lot': 1.0,
        'lot_step': 0.01,
        
        # Symbol (XAUUSD)
        'symbol': 'XAUUSD',
        'pip_size': 0.1,  # Gold: 0.1 = 1 pip
        'point_value': 1.0,  # $1 per pip per 0.01 lot
        'spread': 2.0,  # 2 pips spread
        'execution_penalty': 0.5,  # 0.5 pips slippage
        
        # Timeframe
        'timeframe': 'M15',
        
        # Engulfing pattern settings
        'engulfing_min_body_ratio': 0.7,  # Current body >= 70% of previous
        'engulfing_min_prev_body_pips': 10,  # Previous candle >10 pips
        
        # Filter 1: MA Trend
        'ma_fast': 50,
        'ma_slow': 200,
        
        # Filter 2: ADX
        'adx_min': 20,  # ADX > 20 = trending
        'adx_max': 40,  # ADX < 40 = not overextended
        
        # Filter 3: ROC Momentum
        'roc_bullish': 0.2,  # >0.2% for bullish
        'roc_bearish': -0.2,  # <-0.2% for bearish
        
        # Filter 4: RSI Zone
        'rsi_min': 30,  # Entry zone 30-70
        'rsi_max': 70,
        
        # Exit management
        'atr_multiplier': 1.5,  # SL = Entry ± (1.5 × ATR)
        'rr_ratio': 2.0,  # Risk:Reward 1:2
    }


def main():
    """Main execution"""
    print("=" * 70)
    print("ENGULFING + MULTI-CONFIRMATION BACKTEST (M15)")
    print("=" * 70)
    
    # Configuration
    config = create_m15_config()
    
    # Data files
    data_files = [
        ('2026_02', 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv'),
        ('2026_03', 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv'),
        ('2026_04', 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv'),
    ]
    
    all_results = []
    
    for period_name, csv_path in data_files:
        print(f"\n{'#'*70}")
        print(f"Processing: {period_name}")
        print(f"{'#'*70}")
        
        # Create backtest engine
        engine = BacktestEngine(config)
        
        # Load and resample data
        df_m1 = engine.load_csv_data(csv_path)
        df_m15 = engine.resample_to_m15(df_m1)
        
        # Run backtest
        engine.run_backtest(df_m15, period_name)
        
        # Export results
        engine.export_results(period_name)
        engine.print_summary(period_name)
        
        # Save results for comparison
        all_results.append({
            'period': period_name,
            'trades': len(engine.trades),
            'net_profit': engine.balance - config['initial_balance'],
            'win_rate': len([t for t in engine.trades if t.profit_amount > 0]) / len(engine.trades) * 100 if len(engine.trades) > 0 else 0
        })
    
    # Print overall summary
    print(f"\n{'='*70}")
    print("OVERALL PERFORMANCE SUMMARY")
    print(f"{'='*70}")
    print(f"{'Period':<15} {'Net P/L':<15} {'Trades':<10} {'Win Rate':<15}")
    print('-' * 70)
    
    for result in all_results:
        print(f"{result['period']:<15} ${result['net_profit']:>10.2f}     {result['trades']:<10} {result['win_rate']:>10.2f}%")


if __name__ == '__main__':
    main()
