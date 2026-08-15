"""
Multi-Timeframe Backtest Comparison - MA Crossover Strategy
Compare performance across M1, M5, M15, M30, H1, H4 timeframes
Target: Find timeframe that can achieve 30% daily profit on $100 capital
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime, timedelta
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
    """Main backtesting engine for MA Crossover - Multi-Timeframe Support"""
    
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
    
    def resample_to_timeframe(self, df_m1, timeframe):
        """Resample M1 to specified timeframe"""
        print(f"Resampling M1 data to {timeframe}...")
        
        # Define resampling rules
        resample_rules = {
            'M1': '1min',
            'M5': '5min',
            'M15': '15min',
            'M30': '30min',
            'H1': '1h',
            'H4': '4h'
        }
        
        if timeframe not in resample_rules:
            raise ValueError(f"Unsupported timeframe: {timeframe}")
        
        # For M1, just reset index and return
        if timeframe == 'M1':
            df_result = df_m1.copy()
            df_result = df_result.reset_index()
            print(f"  Using original {len(df_result)} M1 bars")
            return df_result
        
        # Resample to target timeframe
        rule = resample_rules[timeframe]
        df_resampled = df_m1.resample(rule).agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        # Reset index to have datetime as column
        df_resampled = df_resampled.reset_index()
        
        print(f"  Resampled to {len(df_resampled)} {timeframe} bars")
        return df_resampled
    
    def calculate_lot_size(self, entry_price, sl_price):
        """Calculate lot size based on risk percentage (with compound support)"""
        # Use current equity for compound, or initial balance for simple
        if self.config.get('use_compound', False):
            capital_base = max(self.equity, self.config['initial_balance'] * 0.1)
        else:
            capital_base = self.config['initial_balance']
        
        risk_amount = capital_base * (self.config['risk_percent'] / 100)
        
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
    
    def open_trade(self, df, i, signal, verbose=False):
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
        
        if verbose:
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
            print(f"{'='*60}\n")
    
    def update_open_positions(self, df, i, verbose=False):
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
                    
                    if verbose:
                        print(f"[TRADE CLOSED] #{trade.trade_id} - TP - Profit: ${trade.profit_amount:.2f}")
                
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
                    
                    if verbose:
                        print(f"[TRADE CLOSED] #{trade.trade_id} - SL - Loss: ${trade.profit_amount:.2f}")
            
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
                    
                    if verbose:
                        print(f"[TRADE CLOSED] #{trade.trade_id} - TP - Profit: ${trade.profit_amount:.2f}")
                
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
                    
                    if verbose:
                        print(f"[TRADE CLOSED] #{trade.trade_id} - SL - Loss: ${trade.profit_amount:.2f}")
    
    def run_backtest(self, df_timeframe, verbose=False):
        """Run the backtest on specified timeframe"""
        if verbose:
            print("\n" + "="*60)
            print("STARTING BACKTEST")
            print("="*60 + "\n")
        
        print(f"Adding indicators to {self.config['timeframe']} data...")
        df_timeframe = add_all_indicators(df_timeframe)
        
        print(f"Processing {len(df_timeframe)} {self.config['timeframe']} bars...")
        
        # Start from bar 250 (warm-up period for indicators)
        start_bar = min(250, len(df_timeframe) - 1)
        
        for i in range(start_bar, len(df_timeframe)):
            current_time = df_timeframe.loc[i, 'datetime']
            
            # Update open positions first
            self.update_open_positions(df_timeframe, i, verbose=verbose)
            
            # Track equity
            self.equity_history.append({
                'time': current_time,
                'balance': self.balance,
                'equity': self.equity
            })
            
            # Detect signal
            signal = detect_signal(df_timeframe, i, self.config)
            
            if signal is not None:
                # Open trade
                self.open_trade(df_timeframe, i, signal, verbose=verbose)
        
        # Close any remaining open trades at end of data
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        for trade in open_trades:
            last_time = df_timeframe.loc[len(df_timeframe)-1, 'datetime']
            last_close = df_timeframe.loc[len(df_timeframe)-1, 'close']
            
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
            print(f"  No trades executed on {self.config['timeframe']}")
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
        
        # Average win/loss
        avg_win = (total_profit / wins) if wins > 0 else 0
        avg_loss = (total_loss / losses) if losses > 0 else 0
        
        # Consecutive wins/losses
        consecutive_wins = 0
        consecutive_losses = 0
        max_consecutive_wins = 0
        max_consecutive_losses = 0
        
        for trade in closed_trades:
            if trade.profit_amount > 0:
                consecutive_wins += 1
                consecutive_losses = 0
                max_consecutive_wins = max(max_consecutive_wins, consecutive_wins)
            else:
                consecutive_losses += 1
                consecutive_wins = 0
                max_consecutive_losses = max(max_consecutive_losses, consecutive_losses)
        
        # Largest win/loss
        largest_win = max([t.profit_amount for t in winning_trades]) if winning_trades else 0
        largest_loss = min([t.profit_amount for t in losing_trades]) if losing_trades else 0
        
        # Calculate trading period
        first_trade_time = closed_trades[0].open_time
        last_trade_time = closed_trades[-1].close_time
        trading_days = (last_trade_time - first_trade_time).days + 1
        
        # Calculate daily metrics
        total_return_pct = (net_profit / self.config['initial_balance'] * 100)
        avg_daily_return_pct = (total_return_pct / trading_days) if trading_days > 0 else 0
        trades_per_day = (total_trades / trading_days) if trading_days > 0 else 0
        
        results = {
            'timeframe': self.config['timeframe'],
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
            'max_consecutive_wins': max_consecutive_wins,
            'max_consecutive_losses': max_consecutive_losses,
            'final_balance': self.balance,
            'trading_days': trading_days,
            'trades_per_day': trades_per_day,
            'first_trade': first_trade_time,
            'last_trade': last_trade_time
        }
        
        return results


def create_config_for_timeframe(timeframe, initial_balance=100.0, risk_percent=6.0):
    """Create configuration for specific timeframe (AGGRESSIVE for 5-10% daily target)"""
    return {
        # Account settings - AGGRESSIVE
        'initial_balance': initial_balance,
        'risk_percent': risk_percent,  # 6% risk per trade (was 2%)
        'use_compound': True,  # Enable compounding
        'min_lot': 0.01,
        'max_lot': 100.0,
        'lot_step': 0.01,
        
        # Timeframe settings
        'timeframe': timeframe,
        'use_htf_confirmation': False,
        
        # Symbol settings (XAUUSD)
        'pip_size': 0.1,
        'point_value': 1.0,
        'spread_pips': 20,
        'execution_penalty_pips': 5,
        
        # Risk/Reward - AGGRESSIVE
        'rr_ratio': 3.0,  # 1:3 Risk:Reward (was 2.0)
        'atr_multiplier': 1.5,  # Tighter SL (was 2.0)
        
        # MACD settings (standard)
        'macd_fast': 12,
        'macd_slow': 26,
        'macd_signal': 9,
        
        # Filters - RELAXED for more signals
        'use_trend_filter': True,  # MA50/MA200 trend filter
        'use_adx_filter': True,  # ADX strength filter
        'min_adx': 15,  # Lower threshold (was 20)
    }


def run_timeframe_comparison(csv_files, timeframes, initial_balance=100.0, risk_percent=6.0):
    """
    Run backtest comparison across multiple timeframes
    
    Args:
        csv_files: Dictionary of {period: csv_path}
        timeframes: List of timeframes to test (e.g., ['M1', 'M5', 'M15', 'M30', 'H1', 'H4'])
        initial_balance: Starting capital (default $100)
        risk_percent: Risk per trade (default 6% aggressive)
    
    Returns:
        Dictionary of results by timeframe
    """
    
    print("\n" + "="*80)
    print("AGGRESSIVE BACKTEST - TARGET 5-10% DAILY RETURN")
    print(f"Initial Balance: ${initial_balance:.2f}")
    print(f"Risk per Trade: {risk_percent}% (AGGRESSIVE)")
    print(f"Risk:Reward: 1:3 | Compound: ENABLED | ADX: 15")
    print(f"Timeframes: {', '.join(timeframes)}")
    print("="*80 + "\n")
    
    all_results = {}
    
    for timeframe in timeframes:
        print("\n" + "="*80)
        print(f"TESTING TIMEFRAME: {timeframe}")
        print("="*80 + "\n")
        
        timeframe_results = {}
        
        # Load M1 data once for this timeframe
        all_m1_data = []
        for period, csv_path in csv_files.items():
            temp_engine = BacktestEngine(create_config_for_timeframe(timeframe))
            df_m1 = temp_engine.load_csv_data(csv_path)
            all_m1_data.append(df_m1)
        
        # Combine all M1 data
        df_m1_combined = pd.concat(all_m1_data)
        print(f"\nCombined data: {len(df_m1_combined)} M1 bars")
        
        # Create config for this timeframe
        config = create_config_for_timeframe(timeframe, initial_balance, risk_percent)
        
        # Create engine
        engine = BacktestEngine(config)
        
        # Resample to target timeframe
        df_timeframe = engine.resample_to_timeframe(df_m1_combined, timeframe)
        
        # Run backtest
        results = engine.run_backtest(df_timeframe, verbose=False)
        
        if results:
            all_results[timeframe] = {
                'results': results,
                'trades': engine.trades,
                'equity_history': engine.equity_history
            }
            
            # Print summary
            print("\n" + "-"*60)
            print(f"RESULTS FOR {timeframe}")
            print("-"*60)
            print(f"Total Trades: {results['total_trades']} ({results['wins']}W / {results['losses']}L)")
            print(f"Win Rate: {results['win_rate']:.2f}%")
            print(f"Net Profit: ${results['net_profit']:.2f} ({results['total_return_pct']:.2f}%)")
            print(f"Avg Daily Return: {results['avg_daily_return_pct']:.2f}%")
            print(f"Profit Factor: {results['profit_factor']:.2f}")
            print(f"Max Drawdown: {results['max_drawdown_pct']:.2f}%")
            print(f"Trading Days: {results['trading_days']}")
            print(f"Trades per Day: {results['trades_per_day']:.2f}")
            print("-"*60)
        else:
            print(f"  No trades for {timeframe}")
    
    return all_results


def generate_comparison_report(all_results, output_dir="reports"):
    """Generate comparison report in TXT and CSV formats"""
    
    if not all_results:
        print("No results to generate report")
        return
    
    # Create output directory
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Sort by average daily return (descending)
    sorted_timeframes = sorted(all_results.keys(), 
                               key=lambda tf: all_results[tf]['results']['avg_daily_return_pct'], 
                               reverse=True)
    
    # Generate TXT report
    txt_path = os.path.join(output_dir, "timeframe_comparison_report.txt")
    with open(txt_path, 'w', encoding='utf-8') as f:
        f.write("="*100 + "\n")
        f.write("MULTI-TIMEFRAME BACKTEST COMPARISON REPORT\n")
        f.write("MA Crossover Strategy (MACD + Trend Filter)\n")
        f.write("="*100 + "\n\n")
        
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Initial Balance: $100.00\n")
        f.write(f"Risk per Trade: 6% (AGGRESSIVE)\n")
        f.write(f"Risk:Reward Ratio: 1:3 (HIGH REWARD)\n")
        f.write(f"Mode: COMPOUND (Compounding Interest)\n")
        f.write(f"ADX Threshold: 15 (Relaxed)\n")
        f.write(f"Target: 5-10% Daily Return\n\n")
        
        f.write("="*100 + "\n")
        f.write("RANKING BY AVERAGE DAILY RETURN\n")
        f.write("="*100 + "\n\n")
        
        # Table header
        f.write(f"{'Rank':<6}{'Timeframe':<12}{'Daily Ret%':<13}{'Total Ret%':<13}{'Net P/L':<12}"
                f"{'Trades':<10}{'Win Rate':<12}{'PF':<8}{'Max DD%':<10}{'Days':<8}\n")
        f.write("-"*100 + "\n")
        
        # Table rows
        for rank, tf in enumerate(sorted_timeframes, 1):
            r = all_results[tf]['results']
            f.write(f"{rank:<6}{tf:<12}{r['avg_daily_return_pct']:>10.2f}%  "
                   f"{r['total_return_pct']:>10.2f}%  ${r['net_profit']:>8.2f}  "
                   f"{r['total_trades']:<10}{r['win_rate']:>8.2f}%  "
                   f"{r['profit_factor']:>5.2f}  {r['max_drawdown_pct']:>6.2f}%  {r['trading_days']:<8}\n")
        
        f.write("="*100 + "\n\n")
        
        # Detailed results for each timeframe
        f.write("="*100 + "\n")
        f.write("DETAILED RESULTS BY TIMEFRAME\n")
        f.write("="*100 + "\n\n")
        
        for tf in sorted_timeframes:
            r = all_results[tf]['results']
            f.write(f"\n{'='*60}\n")
            f.write(f"TIMEFRAME: {tf}\n")
            f.write(f"{'='*60}\n\n")
            
            f.write(f"Performance:\n")
            f.write(f"  Net Profit: ${r['net_profit']:.2f}\n")
            f.write(f"  Total Return: {r['total_return_pct']:.2f}%\n")
            f.write(f"  Average Daily Return: {r['avg_daily_return_pct']:.2f}%\n")
            f.write(f"  Final Balance: ${r['final_balance']:.2f}\n\n")
            
            f.write(f"Trade Statistics:\n")
            f.write(f"  Total Trades: {r['total_trades']} ({r['wins']}W / {r['losses']}L)\n")
            f.write(f"  Win Rate: {r['win_rate']:.2f}%\n")
            f.write(f"  Profit Factor: {r['profit_factor']:.2f}\n")
            f.write(f"  Trades per Day: {r['trades_per_day']:.2f}\n\n")
            
            f.write(f"Win/Loss Analysis:\n")
            f.write(f"  Average Win: ${r['avg_win']:.2f}\n")
            f.write(f"  Average Loss: ${r['avg_loss']:.2f}\n")
            f.write(f"  Largest Win: ${r['largest_win']:.2f}\n")
            f.write(f"  Largest Loss: ${r['largest_loss']:.2f}\n")
            f.write(f"  Max Consecutive Wins: {r['max_consecutive_wins']}\n")
            f.write(f"  Max Consecutive Losses: {r['max_consecutive_losses']}\n\n")
            
            f.write(f"Risk Metrics:\n")
            f.write(f"  Max Drawdown: ${r['max_drawdown']:.2f} ({r['max_drawdown_pct']:.2f}%)\n")
            f.write(f"  Trading Period: {r['trading_days']} days\n")
            f.write(f"  First Trade: {r['first_trade']}\n")
            f.write(f"  Last Trade: {r['last_trade']}\n\n")
            
            # Risk warning
            if r['max_drawdown_pct'] > 30:
                f.write(f"  ⚠️ WARNING: High drawdown risk ({r['max_drawdown_pct']:.2f}%)\n\n")
            
            # Target achievement
            if r['avg_daily_return_pct'] >= 10.0:
                f.write(f"  [EXCELLENT] Exceeded target: {r['avg_daily_return_pct']:.2f}% daily (target: 5-10%)\n\n")
            elif r['avg_daily_return_pct'] >= 5.0:
                f.write(f"  [SUCCESS] Target achieved: {r['avg_daily_return_pct']:.2f}% daily (target: 5-10%)\n\n")
            elif r['avg_daily_return_pct'] >= 3.0:
                f.write(f"  [CLOSE] Close to target: {r['avg_daily_return_pct']:.2f}% daily (target: 5-10%)\n\n")
            else:
                f.write(f"  [BELOW] Below target: {r['avg_daily_return_pct']:.2f}% daily (target: 5-10%)\n\n")
        
        # Conclusion
        f.write("\n" + "="*100 + "\n")
        f.write("CONCLUSION\n")
        f.write("="*100 + "\n\n")
        
        best_tf = sorted_timeframes[0]
        best_r = all_results[best_tf]['results']
        
        f.write(f"Best Timeframe: {best_tf}\n")
        f.write(f"  Average Daily Return: {best_r['avg_daily_return_pct']:.2f}%\n")
        f.write(f"  Win Rate: {best_r['win_rate']:.2f}%\n")
        f.write(f"  Profit Factor: {best_r['profit_factor']:.2f}\n\n")
        
        if best_r['avg_daily_return_pct'] >= 5.0:
            f.write(f"[SUCCESS] The {best_tf} timeframe achieved the 5-10% daily return target.\n")
            f.write(f"With aggressive risk (6%) and compound interest, this strategy shows potential.\n")
            f.write(f"Final balance: ${best_r['final_balance']:.2f} from $100 in {best_r['trading_days']} days.\n")
        else:
            f.write(f"[INFO] The best timeframe ({best_tf}) achieved {best_r['avg_daily_return_pct']:.2f}% daily return.\n")
            f.write(f"Consider: Higher risk %, alternative strategies, or longer compound period.\n")
        
        f.write("\n" + "="*100 + "\n")
    
    print(f"\nTXT report saved: {txt_path}")
    
    # Generate CSV report
    csv_path = os.path.join(output_dir, "timeframe_comparison_report.csv")
    rows = []
    for tf in sorted_timeframes:
        r = all_results[tf]['results']
        rows.append({
            'Rank': sorted_timeframes.index(tf) + 1,
            'Timeframe': tf,
            'Avg_Daily_Return_Pct': round(r['avg_daily_return_pct'], 2),
            'Total_Return_Pct': round(r['total_return_pct'], 2),
            'Net_Profit': round(r['net_profit'], 2),
            'Final_Balance': round(r['final_balance'], 2),
            'Total_Trades': r['total_trades'],
            'Wins': r['wins'],
            'Losses': r['losses'],
            'Win_Rate_Pct': round(r['win_rate'], 2),
            'Profit_Factor': round(r['profit_factor'], 2),
            'Avg_Win': round(r['avg_win'], 2),
            'Avg_Loss': round(r['avg_loss'], 2),
            'Largest_Win': round(r['largest_win'], 2),
            'Largest_Loss': round(r['largest_loss'], 2),
            'Max_Drawdown_Pct': round(r['max_drawdown_pct'], 2),
            'Max_Consecutive_Wins': r['max_consecutive_wins'],
            'Max_Consecutive_Losses': r['max_consecutive_losses'],
            'Trading_Days': r['trading_days'],
            'Trades_Per_Day': round(r['trades_per_day'], 2)
        })
    
    df_csv = pd.DataFrame(rows)
    df_csv.to_csv(csv_path, index=False)
    print(f"CSV report saved: {csv_path}")


def generate_comparison_charts(all_results, output_dir="reports"):
    """Generate comparison charts"""
    
    if not all_results:
        print("No results to generate charts")
        return
    
    # Create output directory
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    timeframes = list(all_results.keys())
    
    # Sort by daily return
    sorted_tf = sorted(timeframes, 
                      key=lambda tf: all_results[tf]['results']['avg_daily_return_pct'], 
                      reverse=True)
    
    # Chart 1: Daily Return Comparison
    fig, ax = plt.subplots(figsize=(12, 6))
    daily_returns = [all_results[tf]['results']['avg_daily_return_pct'] for tf in sorted_tf]
    colors = ['green' if dr >= 30 else 'orange' if dr >= 20 else 'red' for dr in daily_returns]
    
    bars = ax.bar(sorted_tf, daily_returns, color=colors, alpha=0.7, edgecolor='black')
    ax.axhline(y=30, color='blue', linestyle='--', linewidth=2, label='Target: 30%')
    ax.set_xlabel('Timeframe', fontsize=12, fontweight='bold')
    ax.set_ylabel('Average Daily Return (%)', fontsize=12, fontweight='bold')
    ax.set_title('Average Daily Return by Timeframe', fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')
    
    # Add value labels on bars
    for bar, val in zip(bars, daily_returns):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{val:.2f}%', ha='center', va='bottom', fontweight='bold')
    
    plt.tight_layout()
    chart1_path = os.path.join(output_dir, "comparison_daily_return.png")
    plt.savefig(chart1_path, dpi=150)
    print(f"Chart saved: {chart1_path}")
    plt.close()
    
    # Chart 2: Win Rate Comparison
    fig, ax = plt.subplots(figsize=(12, 6))
    win_rates = [all_results[tf]['results']['win_rate'] for tf in sorted_tf]
    
    bars = ax.bar(sorted_tf, win_rates, color='steelblue', alpha=0.7, edgecolor='black')
    ax.axhline(y=50, color='red', linestyle='--', linewidth=2, label='50% Win Rate')
    ax.set_xlabel('Timeframe', fontsize=12, fontweight='bold')
    ax.set_ylabel('Win Rate (%)', fontsize=12, fontweight='bold')
    ax.set_title('Win Rate by Timeframe', fontsize=14, fontweight='bold')
    ax.set_ylim(0, 100)
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')
    
    # Add value labels
    for bar, val in zip(bars, win_rates):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{val:.1f}%', ha='center', va='bottom', fontweight='bold')
    
    plt.tight_layout()
    chart2_path = os.path.join(output_dir, "comparison_win_rate.png")
    plt.savefig(chart2_path, dpi=150)
    print(f"Chart saved: {chart2_path}")
    plt.close()
    
    # Chart 3: Total Trades Comparison
    fig, ax = plt.subplots(figsize=(12, 6))
    total_trades = [all_results[tf]['results']['total_trades'] for tf in sorted_tf]
    
    bars = ax.bar(sorted_tf, total_trades, color='coral', alpha=0.7, edgecolor='black')
    ax.set_xlabel('Timeframe', fontsize=12, fontweight='bold')
    ax.set_ylabel('Total Trades', fontsize=12, fontweight='bold')
    ax.set_title('Total Number of Trades by Timeframe', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3, axis='y')
    
    # Add value labels
    for bar, val in zip(bars, total_trades):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{val}', ha='center', va='bottom', fontweight='bold')
    
    plt.tight_layout()
    chart3_path = os.path.join(output_dir, "comparison_total_trades.png")
    plt.savefig(chart3_path, dpi=150)
    print(f"Chart saved: {chart3_path}")
    plt.close()
    
    # Chart 4: Equity Curves - All Timeframes
    fig, ax = plt.subplots(figsize=(16, 8))
    
    for tf in sorted_tf:
        equity_hist = all_results[tf]['equity_history']
        df_equity = pd.DataFrame(equity_hist)
        ax.plot(df_equity['time'], df_equity['balance'], label=tf, linewidth=2)
    
    initial_balance = all_results[sorted_tf[0]]['equity_history'][0]['balance']
    ax.axhline(y=initial_balance, color='gray', linestyle='--', linewidth=1, label='Initial Balance')
    
    ax.set_xlabel('Time', fontsize=12, fontweight='bold')
    ax.set_ylabel('Balance ($)', fontsize=12, fontweight='bold')
    ax.set_title('Equity Curves - All Timeframes Comparison', fontsize=14, fontweight='bold')
    ax.legend(loc='best')
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    
    chart4_path = os.path.join(output_dir, "comparison_equity_curves.png")
    plt.savefig(chart4_path, dpi=150)
    print(f"Chart saved: {chart4_path}")
    plt.close()


def main():
    """Main function to run multi-timeframe comparison"""
    
    # CSV files (Feb, Mar, Apr 2026)
    csv_files = {
        '2026_02': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
        '2026_03': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
        '2026_04': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv',
    }
    
    # Timeframes to test
    timeframes = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4']
    
    # Run comparison with AGGRESSIVE settings
    all_results = run_timeframe_comparison(
        csv_files=csv_files,
        timeframes=timeframes,
        initial_balance=100.0,
        risk_percent=6.0  # 6% aggressive risk for 5-10% daily target
    )
    
    if not all_results:
        print("\nNo results to process. Exiting.")
        return
    
    # Generate reports
    print("\n" + "="*80)
    print("GENERATING COMPARISON REPORTS")
    print("="*80 + "\n")
    
    generate_comparison_report(all_results, output_dir="reports")
    generate_comparison_charts(all_results, output_dir="reports")
    
    # Print final summary
    print("\n" + "="*80)
    print("MULTI-TIMEFRAME COMPARISON COMPLETED")
    print("="*80)
    print("\nBest performing timeframes (by daily return):")
    
    sorted_tf = sorted(all_results.keys(), 
                      key=lambda tf: all_results[tf]['results']['avg_daily_return_pct'], 
                      reverse=True)
    
    for rank, tf in enumerate(sorted_tf[:3], 1):
        r = all_results[tf]['results']
        print(f"  {rank}. {tf}: {r['avg_daily_return_pct']:.2f}% daily return "
              f"(${r['net_profit']:.2f} profit, {r['win_rate']:.1f}% win rate)")
    
    print("\n✓ Reports saved in: reports/")
    print("  - timeframe_comparison_report.txt")
    print("  - timeframe_comparison_report.csv")
    print("  - comparison_daily_return.png")
    print("  - comparison_win_rate.png")
    print("  - comparison_total_trades.png")
    print("  - comparison_equity_curves.png")
    print("\n" + "="*80 + "\n")


if __name__ == '__main__':
    main()
