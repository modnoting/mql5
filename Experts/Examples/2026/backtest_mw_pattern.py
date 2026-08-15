"""
M&W Pattern Backtesting Engine
Comprehensive backtesting system for Devilmod-M-W EA
Tests on historical CSV data and generates detailed reports
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

# Import custom modules
from indicators import add_all_indicators
from mw_pattern_strategy import (
    PatternInfo, detect_double_top, detect_double_bottom,
    check_momentum_confirmation, check_trend_filter,
    is_valid_trading_time, check_retest
)


class Trade:
    """Trade object to track individual trades"""
    def __init__(self, ticket, open_time, trade_type, entry_price, sl, tp, lot_size, pattern_type):
        self.ticket = ticket
        self.open_time = open_time
        self.close_time = None
        self.type = trade_type  # 'BUY' or 'SELL'
        self.entry_price = entry_price
        self.sl = sl
        self.tp = tp
        self.lot_size = lot_size
        self.exit_price = None
        self.profit_pips = 0
        self.profit_amount = 0
        self.status = 'OPEN'  # 'OPEN', 'TP', 'SL'
        self.pattern_type = pattern_type  # 'M' or 'W'


class BacktestEngine:
    """Main backtesting engine"""
    
    def __init__(self, config):
        self.config = config
        self.trades = []
        self.equity_history = []
        self.balance = config['initial_balance']
        self.equity = config['initial_balance']
        self.ticket_counter = 1
        self.current_pattern = None
        self.retest_wait_start = None
        
    def load_csv_data(self, csv_path):
        """Load and process CSV data"""
        print(f"Loading CSV data from: {csv_path}")
        
        # Read CSV (has 7 columns: date, time, open, high, low, close, volume)
        df = pd.read_csv(csv_path, header=None)
        
        # Rename columns
        df.columns = ['date', 'time', 'open', 'high', 'low', 'close', 'volume']
        
        # Combine date and time into datetime
        df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])
        
        # Drop original date/time columns and set datetime as index
        df = df.drop(['date', 'time'], axis=1)
        df.set_index('datetime', inplace=True)
        
        print(f"  Loaded {len(df)} M1 bars")
        print(f"  Date range: {df.index[0]} to {df.index[-1]}")
        
        return df
    
    def resample_to_h1(self, df_m1):
        """Resample M1 data to H1"""
        print("Resampling M1 data to H1...")
        
        df_h1 = df_m1.resample('1h').agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        print(f"  Resampled to {len(df_h1)} H1 bars")
        
        return df_h1
    
    def resample_to_m5(self, df_m1):
        """Resample M1 data to M5"""
        print("Resampling M1 data to M5...")
        
        df_m5 = df_m1.resample('5min').agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        print(f"  Resampled to {len(df_m5)} M5 bars")
        
        return df_m5
    
    def calculate_position_size(self, entry_price, sl_price):
        """Calculate position size based on risk percentage"""
        risk_pct = self.config['risk_percent']
        
        if risk_pct <= 0:
            return self.config['fixed_lot']
        
        risk_amount = self.balance * (risk_pct / 100.0)
        sl_distance = abs(entry_price - sl_price)
        
        # For XAUUSD: 1 pip = 0.01, point value depends on lot size
        # Simplified: assume $10 per pip per 1.0 lot
        point_value = self.config['point_value']
        sl_pips = sl_distance / self.config['pip_size']
        
        lot_size = risk_amount / (sl_pips * point_value)
        
        # Normalize
        lot_size = max(self.config['min_lot'], min(self.config['max_lot'], lot_size))
        lot_size = round(lot_size / self.config['lot_step']) * self.config['lot_step']
        
        return lot_size
    
    def calculate_sl_tp(self, pattern, entry_price, pattern_type):
        """Calculate Stop Loss and Take Profit"""
        rr_ratio = self.config['rr_ratio']
        sl_buffer_pips = self.config['sl_buffer_pips']
        pip_size = self.config['pip_size']
        
        buffer = sl_buffer_pips * pip_size
        
        if pattern_type == 'SELL':
            # SL above the higher peak + buffer
            sl_level = max(pattern.peak1_price, pattern.peak2_price)
            sl = sl_level + buffer
            
            # TP below neckline by pattern_height * RR_ratio
            tp = pattern.neckline_price - (pattern.pattern_height * rr_ratio)
            
        elif pattern_type == 'BUY':
            # SL below the lower trough - buffer
            sl_level = min(pattern.peak1_price, pattern.peak2_price)
            sl = sl_level - buffer
            
            # TP above neckline by pattern_height * RR_ratio
            tp = pattern.neckline_price + (pattern.pattern_height * rr_ratio)
        
        return sl, tp
    
    def open_trade(self, current_time, pattern, entry_price, trade_type):
        """Open a new trade"""
        pattern_type_label = 'M' if pattern.type == 1 else 'W'
        
        # Calculate SL and TP
        sl, tp = self.calculate_sl_tp(pattern, entry_price, trade_type)
        
        # Calculate position size
        lot_size = self.calculate_position_size(entry_price, sl)
        
        # Apply spread
        if trade_type == 'BUY':
            entry_price += self.config['spread_pips'] * self.config['pip_size']
        elif trade_type == 'SELL':
            entry_price -= self.config['spread_pips'] * self.config['pip_size']
        
        # Create trade
        trade = Trade(
            ticket=self.ticket_counter,
            open_time=current_time,
            trade_type=trade_type,
            entry_price=entry_price,
            sl=sl,
            tp=tp,
            lot_size=lot_size,
            pattern_type=pattern_type_label
        )
        
        self.trades.append(trade)
        self.ticket_counter += 1
        
        print(f"\n{'='*60}")
        print(f"[TRADE OPENED] #{trade.ticket}")
        print(f"Time: {current_time}")
        print(f"Type: {trade_type} ({pattern_type_label} Pattern)")
        print(f"Entry: {entry_price:.2f}")
        print(f"SL: {sl:.2f} ({abs(entry_price - sl) / self.config['pip_size']:.1f} pips)")
        print(f"TP: {tp:.2f} ({abs(tp - entry_price) / self.config['pip_size']:.1f} pips)")
        print(f"Lot: {lot_size:.2f}")
        print(f"Pattern Height: {pattern.pattern_height / self.config['pip_size']:.1f} pips")
        print(f"{'='*60}\n")
        
        return trade
    
    def update_open_positions(self, current_time, current_bar):
        """Update and close open positions if TP/SL hit"""
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        
        for trade in open_trades:
            high = current_bar['high']
            low = current_bar['low']
            close = current_bar['close']
            
            hit_tp = False
            hit_sl = False
            
            if trade.type == 'BUY':
                if high >= trade.tp:
                    hit_tp = True
                    trade.exit_price = trade.tp
                elif low <= trade.sl:
                    hit_sl = True
                    trade.exit_price = trade.sl
            
            elif trade.type == 'SELL':
                if low <= trade.tp:
                    hit_tp = True
                    trade.exit_price = trade.tp
                elif high >= trade.sl:
                    hit_sl = True
                    trade.exit_price = trade.sl
            
            # Close trade if TP or SL hit
            if hit_tp or hit_sl:
                trade.close_time = current_time
                trade.status = 'TP' if hit_tp else 'SL'
                
                # Calculate profit
                if trade.type == 'BUY':
                    pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
                elif trade.type == 'SELL':
                    pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
                
                # Apply penalty for execution
                pips -= self.config['execution_penalty_pips']
                
                trade.profit_pips = pips
                trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                
                # Update balance
                self.balance += trade.profit_amount
                self.equity = self.balance
                
                print(f"\n{'='*60}")
                print(f"[TRADE CLOSED] #{trade.ticket}")
                print(f"Time: {current_time}")
                print(f"Status: {trade.status}")
                print(f"Entry: {trade.entry_price:.2f} → Exit: {trade.exit_price:.2f}")
                print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                print(f"New Balance: ${self.balance:.2f}")
                print(f"{'='*60}\n")
    
    def has_open_position(self):
        """Check if there's an open position"""
        return any(t.status == 'OPEN' for t in self.trades)
    
    def run_backtest(self, df_working, df_htf=None):
        """Main backtesting loop"""
        print("\n" + "="*60)
        print("STARTING BACKTEST")
        print("="*60)
        print(f"Timeframe: {self.config['timeframe']}, HTF Confirmation: {self.config['use_htf_confirmation'] and df_htf is not None}")
        print(f"Config: {self.config['entry_mode']} Entry, Risk {self.config['risk_percent']}%, RR 1:{self.config['rr_ratio']}")
        print(f"Initial Balance: ${self.config['initial_balance']:.2f}")
        print("="*60 + "\n")
        
        # Add indicators
        df_working = add_all_indicators(df_working)
        if df_htf is not None:
            df_htf = add_all_indicators(df_htf)
        
        # Main loop
        for i in range(len(df_working)):
            current_time = df_working.index[i]
            current_bar = df_working.iloc[i]
            
            # Update equity history
            self.equity_history.append({
                'time': current_time,
                'balance': self.balance,
                'equity': self.equity
            })
            
            # Update open positions
            self.update_open_positions(current_time, current_bar)
            
            # Skip if already have open position
            if self.has_open_position():
                continue
            
            # Check if valid trading time
            if not is_valid_trading_time(
                current_time,
                use_filter=self.config['use_hour_filter'],
                time_mode=self.config['time_mode'],
                start_hour=self.config['start_hour'],
                end_hour=self.config['end_hour']
            ):
                continue
            
            # Check for retest if waiting (Conservative mode)
            if self.current_pattern and self.current_pattern.waiting_retest:
                if check_retest(df_working, i, self.current_pattern):
                    # Retest detected, enter trade
                    trade_type = 'SELL' if self.current_pattern.type == 1 else 'BUY'
                    entry_price = current_bar['close']
                    
                    self.open_trade(current_time, self.current_pattern, entry_price, trade_type)
                    self.current_pattern = None
                    self.retest_wait_start = None
                    continue
                
                # Check timeout
                if self.retest_wait_start:
                    bars_waited = i - self.retest_wait_start
                    if bars_waited > self.config['retest_wait_bars']:
                        print(f"Retest timeout at {current_time}, resetting pattern")
                        self.current_pattern = None
                        self.retest_wait_start = None
                
                continue
            
            # Detect M Pattern (Double Top - SELL)
            pattern = detect_double_top(
                df_working, i,
                tolerance_pct=self.config['pattern_tolerance_pct'],
                min_retracement=self.config['min_retracement_pct'],
                neckline_break_pct=self.config['neckline_break_pct'],
                swing_strength=self.config['swing_strength'],
                lookback_bars=self.config['lookback_bars']
            )
            
            if pattern:
                print(f"[M Pattern] Detected at {current_time}!")
                print(f"  Pattern info: peaks at {pattern.peak1_price:.2f}, {pattern.peak2_price:.2f}, neckline {pattern.neckline_price:.2f}")
                
                # HTF Confirmation for SELL (M pattern)
                if self.config['use_htf_confirmation'] and df_htf is not None:
                    htf_time = current_time.floor('1h')  # Round down to nearest hour
                    if htf_time in df_htf.index:
                        htf_bar = df_htf.loc[htf_time]
                        # Check HTF trend - M pattern needs downtrend or sideways
                        # Ensure ma_50 and ma_200 are available (not NaN)
                        if 'ma_50' in htf_bar and 'ma_200' in htf_bar and pd.notna(htf_bar['ma_50']) and pd.notna(htf_bar['ma_200']):
                            if htf_bar['ma_50'] > htf_bar['ma_200'] * 1.005:  # Strong uptrend on HTF
                                print(f"  [FAILED] HTF uptrend - skipping M pattern")
                                continue
                            else:
                                print(f"  [OK] HTF trend confirmation")
                        else:
                            print(f"  [INFO] HTF MAs not available yet, skipping HTF check")
                
                # Check momentum confirmation
                momentum_ok = check_momentum_confirmation(
                    df_working, pattern,
                    use_rsi=self.config['use_rsi_divergence'],
                    use_macd=self.config['use_macd_weakness'],
                    use_rejection=self.config['use_rejection_candle']
                )
                print(f"  Momentum confirmation: {momentum_ok}")
                
                if not momentum_ok:
                    print(f"  [FAILED] Momentum confirmation")
                    continue
                
                # Check trend filter
                trend_ok = check_trend_filter(df_working, i, pattern.type, use_filter=self.config['use_trend_filter'])
                print(f"  Trend filter: {trend_ok}")
                trend_ok = check_trend_filter(df_working, i, pattern.type, use_filter=self.config['use_trend_filter'])
                print(f"  Trend filter: {trend_ok}")
                
                if not trend_ok:
                    print(f"  [FAILED] Failed trend filter")
                    continue
                
                # Pattern confirmed!
                if self.config['entry_mode'] == 'AGGRESSIVE':
                    # Enter immediately
                    entry_price = current_bar['close']
                    self.open_trade(current_time, pattern, entry_price, 'SELL')
                
                elif self.config['entry_mode'] == 'CONSERVATIVE':
                    # Wait for retest
                    self.current_pattern = pattern
                    self.current_pattern.waiting_retest = True
                    self.retest_wait_start = i
                    print(f"M Pattern detected at {current_time}, waiting for retest...")
                
                continue
            
            # Detect W Pattern (Double Bottom - BUY)
            pattern = detect_double_bottom(
                df_working, i,
                tolerance_pct=self.config['pattern_tolerance_pct'],
                min_retracement=self.config['min_retracement_pct'],
                neckline_break_pct=self.config['neckline_break_pct'],
                swing_strength=self.config['swing_strength'],
                lookback_bars=self.config['lookback_bars']
            )
                
            if pattern:
                print(f"[W Pattern] Detected at {current_time}!")
                print(f"  Pattern info: troughs at {pattern.peak1_price:.2f}, {pattern.peak2_price:.2f}, neckline {pattern.neckline_price:.2f}")
                
                # HTF Confirmation for BUY (W pattern)
                if self.config['use_htf_confirmation'] and df_htf is not None:
                    htf_time = current_time.floor('1h')  # Round down to nearest hour
                    if htf_time in df_htf.index:
                        htf_bar = df_htf.loc[htf_time]
                        # Check HTF trend - W pattern needs uptrend or sideways
                        # Ensure ma_50 and ma_200 are available (not NaN)
                        if 'ma_50' in htf_bar and 'ma_200' in htf_bar and pd.notna(htf_bar['ma_50']) and pd.notna(htf_bar['ma_200']):
                            if htf_bar['ma_50'] < htf_bar['ma_200'] * 0.995:  # Strong downtrend on HTF
                                print(f"  [FAILED] HTF downtrend - skipping W pattern")
                                continue
                            else:
                                print(f"  [OK] HTF trend confirmation")
                        else:
                            print(f"  [INFO] HTF MAs not available yet, skipping HTF check")
                
                # Check momentum confirmation
                momentum_ok = check_momentum_confirmation(
                    df_working, pattern,
                    use_rsi=self.config['use_rsi_divergence'],
                    use_macd=self.config['use_macd_weakness'],
                    use_rejection=self.config['use_rejection_candle']
                )
                print(f"  Momentum confirmation: {momentum_ok}")
                
                if not momentum_ok:
                    print(f"  [FAILED] Failed momentum confirmation")
                    continue
                
                # Check trend filter
                trend_ok = check_trend_filter(df_working, i, pattern.type, use_filter=self.config['use_trend_filter'])
                print(f"  Trend filter: {trend_ok}")
                
                if not trend_ok:
                    print(f"  [FAILED] Failed trend filter")
                    continue
                
                # Pattern confirmed - try to enter trade
                print(f"  [ENTRY] Attempting to enter BUY trade...")
                
                # Pattern confirmed!
                if self.config['entry_mode'] == 'AGGRESSIVE':
                    # Enter immediately
                    entry_price = current_bar['close']
                    self.open_trade(current_time, pattern, entry_price, 'BUY')
                
                elif self.config['entry_mode'] == 'CONSERVATIVE':
                    # Wait for retest
                    self.current_pattern = pattern
                    self.current_pattern.waiting_retest = True
                    self.retest_wait_start = i
                    print(f"W Pattern detected at {current_time}, waiting for retest...")
        
        # Close any remaining open positions at market close
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        if len(open_trades) > 0:
            last_bar = df_working.iloc[-1]
            last_time = df_working.index[-1]
            last_close = last_bar['close']
            
            for trade in open_trades:
                trade.close_time = last_time
                trade.exit_price = last_close
                trade.status = 'CLOSED_EOD'  # Closed at end of data
                
                # Calculate profit
                if trade.type == 'BUY':
                    pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
                elif trade.type == 'SELL':
                    pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
                
                pips -= self.config['execution_penalty_pips']
                trade.profit_pips = pips
                trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                
                self.balance += trade.profit_amount
                self.equity = self.balance
                
                print(f"\n{'='*60}")
                print(f"TRADE CLOSED #{{trade.ticket}} (EOD)")
                print(f"Time: {last_time}")
                print(f"Entry: {trade.entry_price:.2f} -> Exit: {trade.exit_price:.2f}")
                print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                print(f"New Balance: ${self.balance:.2f}")
                print(f"{'='*60}\n")
        
        print("\n" + "="*60)
        print("BACKTEST COMPLETED")
        print("="*60)
        print(f"Final Balance: ${self.balance:.2f}")
        print(f"Total Trades: {len(self.trades)}")
        print("="*60 + "\n")
    
    def calculate_metrics(self):
        """Calculate performance metrics"""
        closed_trades = [t for t in self.trades if t.status != 'OPEN']
        
        if len(closed_trades) == 0:
            return None
        
        # Basic metrics
        total_trades = len(closed_trades)
        winning_trades = [t for t in closed_trades if t.profit_amount > 0]
        losing_trades = [t for t in closed_trades if t.profit_amount <= 0]
        
        total_wins = len(winning_trades)
        total_losses = len(losing_trades)
        win_rate = (total_wins / total_trades * 100) if total_trades > 0 else 0
        
        # Profit metrics
        gross_profit = sum(t.profit_amount for t in winning_trades)
        gross_loss = abs(sum(t.profit_amount for t in losing_trades))
        net_profit = gross_profit - gross_loss
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else 0
        
        # Average win/loss
        avg_win = (gross_profit / total_wins) if total_wins > 0 else 0
        avg_loss = (gross_loss / total_losses) if total_losses > 0 else 0
        avg_win_pips = (sum(t.profit_pips for t in winning_trades) / total_wins) if total_wins > 0 else 0
        avg_loss_pips = (sum(t.profit_pips for t in losing_trades) / total_losses) if total_losses > 0 else 0
        
        # Drawdown
        equity_values = [e['equity'] for e in self.equity_history]
        peak = equity_values[0]
        max_dd = 0
        for equity in equity_values:
            if equity > peak:
                peak = equity
            dd = peak - equity
            if dd > max_dd:
                max_dd = dd
        
        max_dd_pct = (max_dd / self.config['initial_balance'] * 100) if self.config['initial_balance'] > 0 else 0
        
        # Largest win/loss
        largest_win = max((t.profit_amount for t in closed_trades), default=0)
        largest_loss = min((t.profit_amount for t in closed_trades), default=0)
        
        # Consecutive wins/losses
        max_consecutive_wins = 0
        max_consecutive_losses = 0
        current_streak = 0
        last_result = None
        
        for trade in closed_trades:
            is_win = trade.profit_amount > 0
            if is_win == last_result:
                current_streak += 1
            else:
                current_streak = 1
                last_result = is_win
            
            if is_win:
                max_consecutive_wins = max(max_consecutive_wins, current_streak)
            else:
                max_consecutive_losses = max(max_consecutive_losses, current_streak)
        
        # Pattern type breakdown
        m_trades = [t for t in closed_trades if t.pattern_type == 'M']
        w_trades = [t for t in closed_trades if t.pattern_type == 'W']
        
        metrics = {
            'total_trades': total_trades,
            'winning_trades': total_wins,
            'losing_trades': total_losses,
            'win_rate': win_rate,
            'gross_profit': gross_profit,
            'gross_loss': gross_loss,
            'net_profit': net_profit,
            'profit_factor': profit_factor,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'avg_win_pips': avg_win_pips,
            'avg_loss_pips': avg_loss_pips,
            'max_drawdown': max_dd,
            'max_drawdown_pct': max_dd_pct,
            'largest_win': largest_win,
            'largest_loss': largest_loss,
            'max_consecutive_wins': max_consecutive_wins,
            'max_consecutive_losses': max_consecutive_losses,
            'm_pattern_trades': len(m_trades),
            'w_pattern_trades': len(w_trades),
            'm_pattern_wins': len([t for t in m_trades if t.profit_amount > 0]),
            'w_pattern_wins': len([t for t in w_trades if t.profit_amount > 0]),
        }
        
        return metrics
    
    def generate_trade_log_csv(self, output_path):
        """Generate trade log CSV file"""
        closed_trades = [t for t in self.trades if t.status != 'OPEN']
        
        if len(closed_trades) == 0:
            print("No trades to export")
            return
        
        trade_data = []
        for trade in closed_trades:
            trade_data.append({
                'Ticket': trade.ticket,
                'Open Time': trade.open_time,
                'Close Time': trade.close_time,
                'Type': trade.type,
                'Pattern': trade.pattern_type,
                'Entry': trade.entry_price,
                'Exit': trade.exit_price,
                'SL': trade.sl,
                'TP': trade.tp,
                'Lot Size': trade.lot_size,
                'Profit (Pips)': round(trade.profit_pips, 1),
                'Profit ($)': round(trade.profit_amount, 2),
                'Status': trade.status,
                'Result': 'WIN' if trade.profit_amount > 0 else 'LOSS'
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
        plt.plot(df_equity['time'], df_equity['equity'], label='Equity', linewidth=2)
        plt.axhline(y=self.config['initial_balance'], color='gray', linestyle='--', label='Initial Balance')
        
        # Mark trade entries
        for trade in self.trades:
            if trade.status != 'OPEN':
                color = 'green' if trade.profit_amount > 0 else 'red'
                marker = '^' if trade.type == 'BUY' else 'v'
                plt.scatter(trade.open_time, self.config['initial_balance'], 
                          color=color, marker=marker, s=100, alpha=0.6, zorder=5)
        
        plt.xlabel('Time', fontsize=12)
        plt.ylabel('Equity ($)', fontsize=12)
        plt.title('Equity Curve', fontsize=14, fontweight='bold')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        plt.savefig(output_path, dpi=150)
        print(f"Equity curve saved to: {output_path}")
        plt.close()


def create_default_config():
    """Create default configuration"""
    return {
        # Account settings
        'initial_balance': 10000.0,
        'risk_percent': 1.0,
        'fixed_lot': 0.01,
        'min_lot': 0.01,
        'max_lot': 100.0,
        'lot_step': 0.01,
        
        # Timeframe settings
        'timeframe': 'M5',  # M5, H1, H4, D1
        'use_htf_confirmation': True,  # Use higher timeframe (H1) for trend confirmation
        'htf_multiplier': 12,  # H1 is 12x M5 (60min / 5min)
        
        # Symbol settings (XAUUSD)
        'pip_size': 0.1,           # For XAUUSD: 1 pip = 0.10
        'point_value': 1.0,        # $1 per pip per 0.01 lot
        'spread_pips': 20,         # 20 pips = 2.0 XAUUSD points (typical spread)
        'execution_penalty_pips': 5,  # 5 pips = 0.5 points
        
        # Entry settings
        'entry_mode': 'AGGRESSIVE',  # Changed to AGGRESSIVE for testing
        'retest_wait_bars': 10,
        'rr_ratio': 1.5,
        'sl_buffer_pips': 50,        # 50 pips = 5.0 XAUUSD points with pip_size=0.1
        
        # Pattern detection (ULTRA-STRICT config for M5 timeframe - maximum quality filtering)
        'pattern_tolerance_pct': 0.5,  # 0.5% - ULTRA-STRICT: reduced from 0.8% to filter even more low-quality patterns
        'min_retracement_pct': 0.8,    # 0.8% - ULTRA-STRICT: increased from 0.6% to require very deep retracements
        'neckline_break_pct': 0.2,     # 0.2% - Keep same for confirmation
        'swing_strength': 10,           # 10 - ULTRA-STRICT: increased from 7 to maximum noise reduction
        'lookback_bars': 720,           # 720 M5 bars = 60 hours (increased from 480 = 40h for strongest patterns)
        
        # Confirmation filters (ALL ENABLED including rejection candle)
        'use_rsi_divergence': True,     # ENABLED - RSI divergence confirmation
        'use_macd_weakness': True,      # ENABLED - MACD weakness confirmation
        'use_rejection_candle': True,   # ENABLED - Rejection candle for reversal confirmation
        'use_trend_filter': True,       # ENABLED - Trend filter for quality
        
        # Time filters (extended trading hours)
        'use_hour_filter': False,       # Disable hour filter for 24/7 trading
        'time_mode': 'OPTIMIZED',       
        'start_hour': 0,                # Full 24 hours
        'end_hour': 23,
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
        
        # Load data
        df_m1 = engine.load_csv_data(csv_path)
        
        # Resample based on timeframe setting
        if config['timeframe'] == 'M5':
            df_working = engine.resample_to_m5(df_m1)
            # Also prepare H1 for higher timeframe confirmation
            if config['use_htf_confirmation']:
                df_htf = engine.resample_to_h1(df_m1)
            else:
                df_htf = None
        elif config['timeframe'] == 'H1':
            df_working = engine.resample_to_h1(df_m1)
            df_htf = None  # No HTF for H1 backtest
        else:
            df_working = engine.resample_to_h1(df_m1)
            df_htf = None
        
        # Run backtest
        engine.run_backtest(df_working, df_htf)
        
        # Calculate metrics
        metrics = engine.calculate_metrics()
        
        if metrics:
            all_results[period] = metrics
            
            # Generate reports
            engine.generate_trade_log_csv(f"{reports_dir}/trade_log_{period}.csv")
            engine.plot_equity_curve(f"{reports_dir}/equity_curve_{period}.png")
            
            # Print summary
            print("\n" + "="*60)
            print(f"SUMMARY FOR {period}")
            print("="*60)
            print(f"Net Profit: ${metrics['net_profit']:.2f} ({(metrics['net_profit']/config['initial_balance']*100):.2f}%)")
            print(f"Total Trades: {metrics['total_trades']} (W:{metrics['winning_trades']} L:{metrics['losing_trades']})")
            print(f"Win Rate: {metrics['win_rate']:.2f}%")
            print(f"Profit Factor: {metrics['profit_factor']:.2f}")
            print(f"Max Drawdown: ${metrics['max_drawdown']:.2f} ({metrics['max_drawdown_pct']:.2f}%)")
            print(f"M Patterns: {metrics['m_pattern_trades']} ({metrics['m_pattern_wins']} wins)")
            print(f"W Patterns: {metrics['w_pattern_trades']} ({metrics['w_pattern_wins']} wins)")
            print("="*60 + "\n")
    
    # Generate comparison report
    if all_results:
        print("\n" + "="*80)
        print("3-MONTH COMPARISON")
        print("="*80)
        print(f"{'Period':<15} {'Net P/L':<15} {'Trades':<10} {'Win Rate':<12} {'Profit Factor':<15} {'Max DD%':<10}")
        print("-"*80)
        
        for period, metrics in all_results.items():
            print(f"{period:<15} ${metrics['net_profit']:>12.2f} {metrics['total_trades']:>8} "
                  f"{metrics['win_rate']:>10.2f}% {metrics['profit_factor']:>13.2f} {metrics['max_drawdown_pct']:>8.2f}%")
        
        print("="*80 + "\n")
    
    print("All backtests completed!")
    print(f"Reports saved in: {reports_dir}/")


if __name__ == "__main__":
    main()
