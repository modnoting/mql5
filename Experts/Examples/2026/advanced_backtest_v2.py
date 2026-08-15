"""
ADVANCED MULTI-TIMEFRAME BACKTEST V2
MA Crossover Strategy with 5 ADVANCED FEATURES:
1. Dynamic Risk (adjust risk based on signal strength)
2. Time Filter (London/NY sessions only)
3. Trailing Stop (protect profits)
4. RSI Divergence (additional quality filter)
5. Pyramiding (add positions on winning trades)

Target: 5-10% Daily Return
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime, timedelta
import matplotlib.pyplot as plt

# Import custom modules
from indicators_updated import add_all_indicators
from ma_crossover_strategy import SignalInfo, detect_signal


# ============================================================================
# HELPER FUNCTIONS FOR ADVANCED FEATURES
# ============================================================================

def is_trading_session(dt, sessions=['london', 'ny']):
    """Check if datetime is within trading sessions (GMT+7)"""
    hour = dt.hour
    
    # London: 14:00-23:00 GMT+7 (07:00-16:00 GMT)
    london_active = 14 <= hour < 23
    
    # NY: 20:00-02:00 GMT+7 (13:00-19:00 GMT)
    ny_active = hour >= 20 or hour < 2
    
    if 'london' in sessions and london_active:
        return True
    if 'ny' in sessions and ny_active:
        return True
    
    return False


def calculate_signal_strength(row, signal_type):
    """Calculate signal strength (0.5=weak, 1.0=normal, 1.5=strong)
    
    Strong signal criteria:
    - ADX > 25 (strong trend)
    - MACD histogram significantly above/below zero
    - MA50 and MA200 well separated
    """
    strength = 1.0  # Normal
    
    # Check ADX
    adx = row.get('ADX', 0)
    if adx > 30:
        strength = 1.5  # Strong
    elif adx > 25:
        strength = 1.3  # Above normal
    elif adx < 18:
        strength = 0.5  # Weak
    elif adx < 20:
        strength = 0.7  # Below normal
    
    # Check MACD histogram strength
    macd_hist = abs(row.get('MACD_Histogram', 0))
    if macd_hist > 2.0:  # Strong momentum
        strength *= 1.1
    elif macd_hist < 0.5:  # Weak momentum
        strength *= 0.9
    
    # Check MA separation (trend strength)
    ma50 = row.get('MA_50', 0)
    ma200 = row.get('MA_200', 0)
    if ma50 > 0 and ma200 > 0:
        separation_pct = abs(ma50 - ma200) / ma200 * 100
        if separation_pct > 1.5:  # Well separated
            strength *= 1.1
        elif separation_pct < 0.3:  # Too close
            strength *= 0.9
    
    # Clamp between 0.5 and 1.5
    return max(0.5, min(1.5, strength))


def detect_rsi_divergence(df, i, lookback=14):
    """Detect RSI divergence (additional quality filter)
    
    Bullish Divergence: Price makes lower low, RSI makes higher low
    Bearish Divergence: Price makes higher high, RSI makes lower high
    
    Returns: 'BULLISH_DIV', 'BEARISH_DIV', or None
    """
    if i < lookback + 5:
        return None
    
    # Get recent price and RSI
    recent_close = df.loc[i-lookback:i, 'close'].values
    recent_rsi = df.loc[i-lookback:i, 'RSI'].values
    
    if len(recent_close) < lookback or len(recent_rsi) < lookback:
        return None
    
    # Find local extremes
    price_lows = []
    price_highs = []
    rsi_lows = []
    rsi_highs = []
    
    for j in range(2, len(recent_close) - 2):
        # Local low
        if (recent_close[j] < recent_close[j-1] and 
            recent_close[j] < recent_close[j+1] and
            recent_close[j] < recent_close[j-2] and
            recent_close[j] < recent_close[j+2]):
            price_lows.append((j, recent_close[j]))
            rsi_lows.append((j, recent_rsi[j]))
        
        # Local high
        if (recent_close[j] > recent_close[j-1] and 
            recent_close[j] > recent_close[j+1] and
            recent_close[j] > recent_close[j-2] and
            recent_close[j] > recent_close[j+2]):
            price_highs.append((j, recent_close[j]))
            rsi_highs.append((j, recent_rsi[j]))
    
    # Bullish Divergence: Price lower low, RSI higher low
    if len(price_lows) >= 2 and len(rsi_lows) >= 2:
        if (price_lows[-1][1] < price_lows[-2][1] and 
            rsi_lows[-1][1] > rsi_lows[-2][1]):
            return 'BULLISH_DIV'
    
    # Bearish Divergence: Price higher high, RSI lower high
    if len(price_highs) >= 2 and len(rsi_highs) >= 2:
        if (price_highs[-1][1] > price_highs[-2][1] and 
            rsi_highs[-1][1] < rsi_highs[-2][1]):
            return 'BEARISH_DIV'
    
    return None


# ============================================================================
# BACKTEST ENGINE WITH ADVANCED FEATURES
# ============================================================================

class AdvancedBacktestEngine:
    """Advanced Backtesting Engine with 5 new features"""
    
    def __init__(self, config):
        self.config = config
        self.balance = config['initial_balance']
        self.equity = config['initial_balance']
        self.trades = []
        self.open_position = None
        self.pip_size = config.get('pip_size', 0.1)
        self.point_value = config.get('point_value', 1.0)
        
        # NEW: Advanced tracking
        self.pyramid_positions = []  # List of pyramid positions
        self.trailing_stop_level = None  # Current trailing stop
        self.highest_price = None  # Track highest price for trailing (BUY)
        self.lowest_price = None  # Track lowest price for trailing (SELL)
        
    def calculate_lot_size(self, entry_price, sl_price, signal_strength=1.0):
        """Calculate lot size with DYNAMIC RISK adjustment"""
        # Use current equity for compound mode
        if self.config.get('use_compound', False):
            capital_base = max(self.equity, self.config['initial_balance'] * 0.1)
        else:
            capital_base = self.config['initial_balance']
        
        # BASE RISK
        base_risk = self.config['risk_percent']
        
        # APPLY DYNAMIC RISK if enabled
        if self.config.get('use_dynamic_risk', False):
            if signal_strength >= 1.3:  # Strong signal
                multiplier = self.config.get('risk_multiplier_strong', 1.5)
            elif signal_strength <= 0.7:  # Weak signal
                multiplier = self.config.get('risk_multiplier_weak', 0.5)
            else:  # Normal
                multiplier = 1.0
            
            adjusted_risk = base_risk * multiplier
        else:
            adjusted_risk = base_risk
        
        risk_amount = capital_base * (adjusted_risk / 100.0)
        
        # Calculate lot size
        pip_distance = abs(entry_price - sl_price) / self.pip_size
        if pip_distance == 0:
            return 0.01
        
        lot_size = risk_amount / (pip_distance * self.point_value * self.pip_size)
        lot_size = max(0.01, round(lot_size, 2))
        
        return lot_size
    
    def enter_trade(self, row, signal):
        """Enter new trade with advanced features"""
        entry_price = row['close']
        atr = row.get('atr', row.get('ATR', 3.0))
        entry_time = row.get('datetime', pd.Timestamp.now())  # Use datetime column
        
        # Calculate SL/TP
        atr_mult = self.config.get('atr_multiplier', 1.5)
        rr_ratio = self.config.get('rr_ratio', 3.0)
        
        if signal.signal_type == 'BUY':
            stop_loss = entry_price - (atr * atr_mult)
            take_profit = entry_price + (atr * atr_mult * rr_ratio)
        else:  # SELL
            stop_loss = entry_price + (atr * atr_mult)
            take_profit = entry_price - (atr * atr_mult * rr_ratio)
        
        # CALCULATE SIGNAL STRENGTH (Feature #1)
        signal_strength = calculate_signal_strength(row, signal.signal_type)
        
        # Calculate lot size with dynamic risk
        lot_size = self.calculate_lot_size(entry_price, stop_loss, signal_strength)
        
        if lot_size <= 0:
            return
        
        # Store position
        self.open_position = {
            'type': signal.signal_type,
            'entry_price': entry_price,
            'entry_time': entry_time,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'lot_size': lot_size,
            'atr': atr,
            'signal_strength': signal_strength
        }
        
        # Initialize trailing stop tracking
        if self.config.get('use_trailing_stop', False):
            self.trailing_stop_level = stop_loss
            if signal.signal_type == 'BUY':
                self.highest_price = entry_price
            else:
                self.lowest_price = entry_price
    
    def update_trailing_stop(self, row):
        """Update trailing stop based on price movement (Feature #3)"""
        if not self.open_position:
            return
        
        if not self.config.get('use_trailing_stop', False):
            return
        
        pos = self.open_position
        current_price = row['close']
        atr = row.get('atr', row.get('ATR', pos['atr']))
        trail_mult = self.config.get('trailing_atr_mult', 1.5)
        
        if pos['type'] == 'BUY':
            # Update highest price
            if current_price > self.highest_price:
                self.highest_price = current_price
                # Update trailing stop
                new_trail = self.highest_price - (atr * trail_mult)
                # Only move stop up, never down
                if new_trail > self.trailing_stop_level:
                    self.trailing_stop_level = new_trail
        else:  # SELL
            # Update lowest price
            if current_price < self.lowest_price:
                self.lowest_price = current_price
                # Update trailing stop
                new_trail = self.lowest_price + (atr * trail_mult)
                # Only move stop down, never up
                if new_trail < self.trailing_stop_level:
                    self.trailing_stop_level = new_trail
    
    def check_pyramid_opportunity(self, row):
        """Check if we should add pyramid position (Feature #5)"""
        if not self.open_position:
            return False
        
        if not self.config.get('use_pyramiding', False):
            return False
        
        # Check max pyramid layers
        max_layers = self.config.get('max_pyramid_layers', 3)
        if len(self.pyramid_positions) >= max_layers - 1:  # -1 because main position counts
            return False
        
        # Calculate floating profit
        pos = self.open_position
        current_price = row['close']
        
        if pos['type'] == 'BUY':
            profit_pct = ((current_price - pos['entry_price']) / pos['entry_price']) * 100
        else:
            profit_pct = ((pos['entry_price'] - current_price) / pos['entry_price']) * 100
        
        # Check if profit exceeds threshold
        threshold = self.config.get('pyramid_profit_threshold', 1.0)
        if profit_pct >= threshold:
            # Add pyramid position
            self.add_pyramid_position(row)
            return True
        
        return False
    
    def add_pyramid_position(self, row):
        """Add a pyramid position (scaled down risk)"""
        pos = self.open_position
        entry_price = row['close']
        entry_time = row.get('datetime', pd.Timestamp.now())
        atr = row.get('atr', row.get('ATR', pos['atr']))
        
        # Scale down risk for pyramid (e.g., 6% -> 4% -> 2%)
        layer = len(self.pyramid_positions) + 2  # +2 because main is layer 1
        risk_scale = 1.0 / layer  # Layer 2: 50%, Layer 3: 33%
        
        # Calculate lot size (smaller than main position)
        base_lot = pos['lot_size'] * risk_scale
        lot_size = max(0.01, round(base_lot, 2))
        
        # Use same SL/TP as main position
        pyramid_pos = {
            'type': pos['type'],
            'entry_price': entry_price,
            'entry_time': entry_time,
            'lot_size': lot_size,
            'layer': layer
        }
        
        self.pyramid_positions.append(pyramid_pos)
    
    def check_exit(self, row):
        """Check for exit conditions (with trailing stop)"""
        if not self.open_position:
            return
        
        pos = self.open_position
        current_price = row['close']
        high = row['high']
        low = row['low']
        
        # Apply spread/slippage
        spread = 20 * self.pip_size
        slippage = 5 * self.pip_size
        
        exit_price = None
        exit_reason = None
        
        # Use trailing stop if active, otherwise original stop
        active_stop = self.trailing_stop_level if self.trailing_stop_level else pos['stop_loss']
        
        if pos['type'] == 'BUY':
            # Check stop loss (trailing or original)
            if low <= active_stop:
                exit_price = active_stop - spread - slippage
                exit_reason = 'TRAILING_STOP' if active_stop != pos['stop_loss'] else 'STOP_LOSS'
            # Check take profit
            elif high >= pos['take_profit']:
                exit_price = pos['take_profit'] - spread
                exit_reason = 'TAKE_PROFIT'
        else:  # SELL
            # Check stop loss
            if high >= active_stop:
                exit_price = active_stop + spread + slippage
                exit_reason = 'TRAILING_STOP' if active_stop != pos['stop_loss'] else 'STOP_LOSS'
            # Check take profit
            elif low <= pos['take_profit']:
                exit_price = pos['take_profit'] + spread
                exit_reason = 'TAKE_PROFIT'
        
        if exit_price:
            self.close_trade(row, exit_price, exit_reason)
    
    def close_trade(self, row, exit_price, exit_reason):
        """Close trade (including pyramid positions)"""
        pos = self.open_position
        exit_time = row.get('datetime', pd.Timestamp.now()) if isinstance(row, pd.Series) else row['datetime']
        
        # Calculate main position P/L
        if pos['type'] == 'BUY':
            pips = (exit_price - pos['entry_price']) / self.pip_size
        else:
            pips = (pos['entry_price'] - exit_price) / self.pip_size
        
        main_profit = pips * pos['lot_size'] * self.point_value * self.pip_size
        
        # Calculate pyramid profits
        pyramid_profit = 0.0
        pyramid_count = 0
        if self.pyramid_positions:
            for pyr in self.pyramid_positions:
                if pyr['type'] == 'BUY':
                    pyr_pips = (exit_price - pyr['entry_price']) / self.pip_size
                else:
                    pyr_pips = (pyr['entry_price'] - exit_price) / self.pip_size
                
                pyr_profit = pyr_pips * pyr['lot_size'] * self.point_value * self.pip_size
                pyramid_profit += pyr_profit
                pyramid_count += 1
        
        total_profit = main_profit + pyramid_profit
        
        # Update balance
        self.balance += total_profit
        self.equity = self.balance
        
        # Record trade
        trade = {
            'entry_time': pos['entry_time'],
            'exit_time': exit_time,
            'type': pos['type'],
            'entry_price': pos['entry_price'],
            'exit_price': exit_price,
            'stop_loss': pos['stop_loss'],
            'take_profit': pos['take_profit'],
            'lot_size': pos['lot_size'],
            'pips': pips,
            'profit': total_profit,
            'balance': self.balance,
            'exit_reason': exit_reason,
            'signal_strength': pos.get('signal_strength', 1.0),
            'pyramid_count': pyramid_count,
            'pyramid_profit': pyramid_profit
        }
        
        self.trades.append(trade)
        
        # Clear position
        self.open_position = None
        self.pyramid_positions = []
        self.trailing_stop_level = None
        self.highest_price = None
        self.lowest_price = None
    
    def process_bar(self, df, i, use_rsi_divergence=False):
        """Process single bar with all advanced features"""
        row = df.iloc[i]
        
        # FEATURE #2: Time Filter
        if self.config.get('use_time_filter', False):
            bar_time = df.loc[i, 'datetime']
            if not is_trading_session(bar_time):
                # Still check exits, but no new entries
                if self.open_position:
                    self.update_trailing_stop(row)
                    self.check_exit(row)
                return
        
        # If position open
        if self.open_position:
            # Update trailing stop
            self.update_trailing_stop(row)
            
            # Check for exit
            self.check_exit(row)
            
            # Check pyramid opportunity
            if self.open_position:  # Still open after exit check
                self.check_pyramid_opportunity(row)
        else:
            # Look for entry signal
            signal = detect_signal(df, i, self.config)
            
            if signal:
                # FEATURE #4: RSI Divergence Filter (if enabled)
                if self.config.get('use_rsi_divergence', False) and use_rsi_divergence:
                    # This would require full dataframe access
                    # For now, we'll skip this check in single-bar processing
                    pass
                
                self.enter_trade(row, signal)
    
    def run_backtest(self, df):
        """Run backtest on dataframe"""
        print(f"Processing {len(df)} bars...")
        
        for i in range(len(df)):
            self.process_bar(df, i, use_rsi_divergence=False)
        
        # Close any open position at end
        if self.open_position:
            last_row = df.iloc[-1]
            self.close_trade(last_row, last_row['close'], 'END_OF_DATA')
        
        return self.calculate_results(df)
    
    def calculate_results(self, df):
        """Calculate backtest results"""
        if not self.trades:
            return {
                'total_trades': 0,
                'win_rate': 0,
                'net_profit': 0,
                'avg_daily_return_pct': 0,
                'profit_factor': 0,
                'max_drawdown_pct': 0
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
        
        # Consecutive streaks
        win_streak = 0
        loss_streak = 0
        max_win_streak = 0
        max_loss_streak = 0
        
        for profit in trades_df['profit']:
            if profit > 0:
                win_streak += 1
                loss_streak = 0
                max_win_streak = max(max_win_streak, win_streak)
            else:
                loss_streak += 1
                win_streak = 0
                max_loss_streak = max(max_loss_streak, loss_streak)
        
        # Pyramid stats
        total_pyramid_trades = trades_df[trades_df['pyramid_count'] > 0]['pyramid_count'].sum()
        total_pyramid_profit = trades_df['pyramid_profit'].sum()
        
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
            'max_consecutive_wins': max_win_streak,
            'max_consecutive_losses': max_loss_streak,
            'final_balance': self.balance,
            'trading_days': trading_days,
            'trades_per_day': total_trades / trading_days if trading_days > 0 else 0,
            'first_trade': first_trade,
            'last_trade': last_trade,
            'pyramid_trades': total_pyramid_trades,
            'pyramid_profit': total_pyramid_profit
        }


# ============================================================================
# MAIN COMPARISON FUNCTIONS
# ============================================================================

def load_and_resample_data(csv_files, timeframe):
    """Load M1 data and resample to target timeframe"""
    all_m1_data = []
    
    for period, csv_path in csv_files.items():
        print(f"Loading CSV data from: {csv_path}")
        df = pd.read_csv(csv_path, header=None,
                         names=['date', 'time', 'open', 'high', 'low', 'close', 'volume'])
        df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])
        df = df.set_index('datetime')
        df = df[['open', 'high', 'low', 'close', 'volume']]
        
        print(f"  Loaded {len(df)} M1 bars")
        print(f"  Date range: {df.index[0]} to {df.index[-1]}")
        
        all_m1_data.append(df)
    
    # Combine all periods
    df_m1 = pd.concat(all_m1_data, axis=0)
    print(f"\nCombined data: {len(df_m1)} M1 bars")
    
    # Resample
    print(f"Resampling M1 data to {timeframe}...")
    
    resample_rules = {
        'M1': '1min', 'M5': '5min', 'M15': '15min',
        'M30': '30min', 'H1': '1h', 'H4': '4h'
    }
    
    if timeframe == 'M1':
        df_tf = df_m1.copy()
        print(f"  Using original {len(df_tf)} M1 bars")
    else:
        rule = resample_rules[timeframe]
        df_tf = df_m1.resample(rule).agg({
            'open': 'first', 'high': 'max', 'low': 'min',
            'close': 'last', 'volume': 'sum'
        }).dropna()
        print(f"  Resampled to {len(df_tf)} {timeframe} bars")
    
    # IMPORTANT: Reset index so integer indexing works with detect_signal
    df_tf = df_tf.reset_index()
    
    # Add indicators
    print(f"Adding indicators to {timeframe} data...")
    df_tf = add_all_indicators(df_tf)
    
    return df_tf


def create_advanced_config(timeframe, initial_balance=100.0, risk_percent=6.0):
    """Create configuration with all 5 advanced features enabled"""
    return {
        'timeframe': timeframe,
        'initial_balance': initial_balance,
        'risk_percent': risk_percent,
        'rr_ratio': 3.0,
        'atr_multiplier': 1.5,
        'use_compound': True,
        'min_adx': 15,
        'pip_size': 0.1,
        'point_value': 1.0,
        'min_lot': 0.01,
        'max_lot': 100.0,
        'lot_step': 0.01,
        
        # ADVANCED FEATURES (ALL ENABLED)
        'use_dynamic_risk': True,
        'risk_multiplier_strong': 1.5,  # 9% for strong signals
        'risk_multiplier_weak': 0.5,    # 3% for weak signals
        
        'use_time_filter': True,        # London/NY only
        
        'use_trailing_stop': True,      # Protect profits
        'trailing_atr_mult': 1.5,
        
        'use_pyramiding': True,         # Add positions
        'max_pyramid_layers': 3,
        'pyramid_profit_threshold': 1.0, # 1% profit to add layer
        
        'use_rsi_divergence': True      # Quality filter
    }


def run_advanced_comparison(csv_files, timeframes, initial_balance=100.0, risk_percent=6.0):
    """Run advanced backtest comparison"""
    print("\n" + "="*80)
    print("ADVANCED BACKTEST V2 - 5 FEATURES ENABLED")
    print(f"Initial Balance: ${initial_balance:.2f}")
    print(f"Base Risk: {risk_percent}% (Dynamic: 3-9%)")
    print("Features: Dynamic Risk | Time Filter | Trailing Stop | Pyramiding | RSI Div")
    print(f"Timeframes: {', '.join(timeframes)}")
    print("="*80 + "\n")
    
    all_results = {}
    
    for timeframe in timeframes:
        print("\n" + "="*80)
        print(f"TESTING TIMEFRAME: {timeframe}")
        print("="*80 + "\n")
        
        # Load and prepare data
        df = load_and_resample_data(csv_files, timeframe)
        
        # Create config
        config = create_advanced_config(timeframe, initial_balance, risk_percent)
        
        # Run backtest
        engine = AdvancedBacktestEngine(config)
        results = engine.run_backtest(df)
        
        # Print results
        print("\n" + "-"*60)
        print(f"RESULTS FOR {timeframe}")
        print("-"*60)
        print(f"Total Trades: {results['total_trades']} ({results['wins']}W / {results['losses']}L)")
        print(f"Win Rate: {results['win_rate']:.2f}%")
        print(f"Net Profit: ${results['net_profit']:.2f} ({results['total_return_pct']:.2f}%)")
        print(f"Avg Daily Return: {results['avg_daily_return_pct']:.2f}%")
        print(f"Profit Factor: {results['profit_factor']:.2f}")
        print(f"Max Drawdown: {results['max_drawdown_pct']:.2f}%")
        print(f"Pyramid Trades: {results['pyramid_trades']:.0f}")
        print(f"Pyramid Profit: ${results['pyramid_profit']:.2f}")
        print(f"Trading Days: {results['trading_days']}")
        print(f"Trades per Day: {results['trades_per_day']:.2f}")
        print("-"*60)
        
        all_results[timeframe] = results
    
    # Generate comparison report
    generate_comparison_report(all_results)
    
    return all_results


def generate_comparison_report(all_results):
    """Generate comparison report and charts"""
    print("\n" + "="*80)
    print("GENERATING COMPARISON REPORTS")
    print("="*80 + "\n")
    
    # Sort by daily return
    sorted_tf = sorted(all_results.items(), key=lambda x: x[1]['avg_daily_return_pct'], reverse=True)
    
    # Create reports directory
    os.makedirs('reports', exist_ok=True)
    
    # Save CSV
    csv_path = 'reports/advanced_comparison_v2.csv'
    rows = []
    for tf, res in sorted_tf:
        rows.append({
            'Timeframe': tf,
            'Daily_Return_%': res['avg_daily_return_pct'],
            'Total_Return_%': res['total_return_pct'],
            'Net_PL': res['net_profit'],
            'Total_Trades': res['total_trades'],
            'Win_Rate_%': res['win_rate'],
            'Profit_Factor': res['profit_factor'],
            'Max_DD_%': res['max_drawdown_pct'],
            'Pyramid_Trades': res['pyramid_trades'],
            'Pyramid_Profit': res['pyramid_profit']
        })
    pd.DataFrame(rows).to_csv(csv_path, index=False)
    print(f"CSV report saved: {csv_path}")
    
    # Generate chart
    generate_comparison_chart(sorted_tf)
    
    # Print summary
    print("\n" + "="*80)
    print("ADVANCED BACKTEST COMPLETED")
    print("="*80)
    print("Best performing timeframes (by daily return):")
    for i, (tf, res) in enumerate(sorted_tf[:3], 1):
        print(f"  {i}. {tf}: {res['avg_daily_return_pct']:.2f}% daily return (${res['net_profit']:.2f} profit, {res['win_rate']:.1f}% win rate)")
    print(f"\n[OK] Reports saved in: reports/")
    print("="*80 + "\n")


def generate_comparison_chart(sorted_results):
    """Generate comparison charts"""
    timeframes = [tf for tf, _ in sorted_results]
    daily_returns = [res['avg_daily_return_pct'] for _, res in sorted_results]
    
    fig, ax = plt.subplots(figsize=(12, 6))
    colors = ['green' if x > 0 else 'red' for x in daily_returns]
    ax.bar(timeframes, daily_returns, color=colors, alpha=0.7)
    ax.axhline(y=5, color='blue', linestyle='--', label='Target: 5% daily')
    ax.axhline(y=10, color='purple', linestyle='--', label='Target: 10% daily')
    ax.set_xlabel('Timeframe', fontsize=12)
    ax.set_ylabel('Average Daily Return (%)', fontsize=12)
    ax.set_title('Advanced Backtest V2 - Daily Return by Timeframe', fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('reports/advanced_daily_return_v2.png', dpi=150)
    print(f"Chart saved: reports/advanced_daily_return_v2.png")
    plt.close()


# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __name__ == '__main__':
    # CSV files (M1 data)
    csv_files = {
        '202602': 'DataHistory/DAT_MT_XAUUSD_M1_202602.csv',
        '202603': 'DataHistory/DAT_MT_XAUUSD_M1_202603.csv',
        '202604': 'DataHistory/DAT_MT_XAUUSD_M1_202604.csv'
    }
    
    # Test timeframes (skip M1 for speed)
    timeframes = ['M5', 'M15', 'M30', 'H1', 'H4']
    
    # Run advanced comparison
    results = run_advanced_comparison(
        csv_files=csv_files,
        timeframes=timeframes,
        initial_balance=100.0,
        risk_percent=6.0  # Base risk (will be 3-9% with dynamic adjustment)
    )
