"""
Price Action Backtesting Engine (Pin Bar + Engulfing)
Tests Price Action patterns on M5 timeframe with H1 trend confirmation
"""

import pandas as pd
import numpy as np
import os
from datetime import datetime
import matplotlib.pyplot as plt

# Import custom modules
from indicators import add_all_indicators
from price_action_patterns import (
    PatternInfo, detect_bullish_pin_bar, detect_bearish_pin_bar,
    detect_bullish_engulfing, detect_bearish_engulfing,
    check_support_resistance, check_trend_alignment
)


class TradeRecord:
    """Record of a single trade"""
    def __init__(self):
        self.trade_id = 0
        self.open_time = None
        self.close_time = None
        self.type = ''  # 'BUY' or 'SELL'
        self.pattern_type = ''  # 'BULLISH_PIN', 'BEARISH_PIN', etc.
        self.entry_price = 0.0
        self.exit_price = 0.0
        self.sl_price = 0.0
        self.tp_price = 0.0
        self.lot_size = 0.0
        self.profit_amount = 0.0
        self.profit_pips = 0.0
        self.status = 'OPEN'  # 'OPEN', 'TP', 'SL', 'CLOSED_EOD'
        self.pattern_strength = 0.0
        self.near_sr_level = False


class BacktestEngine:
    """Main backtesting engine for Price Action"""
    
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
    
    def open_trade(self, current_time, pattern, trade_type):
        """Open a new trade based on pattern"""
        self.trade_counter += 1
        
        entry_price = pattern.entry_price
        
        # Calculate SL and TP based on pattern
        if trade_type == 'BUY':
            # SL below pattern low with buffer
            sl_price = entry_price - (pattern.total_range * self.config['pip_size'] * self.config['sl_multiplier'])
            # TP based on RR ratio
            risk_pips = (entry_price - sl_price) / self.config['pip_size']
            tp_price = entry_price + (risk_pips * self.config['rr_ratio'] * self.config['pip_size'])
        else:  # SELL
            # SL above pattern high with buffer
            sl_price = entry_price + (pattern.total_range * self.config['pip_size'] * self.config['sl_multiplier'])
            # TP based on RR ratio
            risk_pips = (sl_price - entry_price) / self.config['pip_size']
            tp_price = entry_price - (risk_pips * self.config['rr_ratio'] * self.config['pip_size'])
        
        # Calculate lot size
        lot_size = self.calculate_lot_size(entry_price, sl_price)
        
        # Create trade record
        trade = TradeRecord()
        trade.trade_id = self.trade_counter
        trade.open_time = current_time
        trade.type = trade_type
        trade.pattern_type = pattern.pattern_type
        trade.entry_price = entry_price
        trade.sl_price = sl_price
        trade.tp_price = tp_price
        trade.lot_size = lot_size
        trade.pattern_strength = pattern.signal_strength
        trade.status = 'OPEN'
        
        self.trades.append(trade)
        
        # Deduct spread from balance
        spread_cost = self.config['spread_pips'] * self.config['point_value'] * lot_size
        self.balance -= spread_cost
        
        risk_pips_calc = abs(entry_price - sl_price) / self.config['pip_size']
        reward_pips = abs(tp_price - entry_price) / self.config['pip_size']
        
        print(f"\n{'='*60}")
        print(f"[TRADE OPENED] #{trade.trade_id}")
        print(f"Time: {current_time}")
        print(f"Type: {trade_type} ({pattern.pattern_type})")
        print(f"Entry: {entry_price:.2f}")
        print(f"SL: {sl_price:.2f} ({risk_pips_calc:.1f} pips)")
        print(f"TP: {tp_price:.2f} ({reward_pips:.1f} pips)")
        print(f"Lot: {lot_size:.2f}")
        print(f"Pattern Strength: {pattern.signal_strength:.2f}")
        print(f"Pattern Size: {pattern.pattern_size:.1f} pips")
        print(f"{'='*60}\n")
    
    def update_open_positions(self, current_time, current_bar):
        """Update open positions and check for TP/SL"""
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        
        for trade in open_trades:
            current_high = current_bar['high']
            current_low = current_bar['low']
            
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
                    print(f"Entry: {trade.entry_price:.2f} → Exit: {trade.exit_price:.2f}")
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
                    print(f"Entry: {trade.entry_price:.2f} → Exit: {trade.exit_price:.2f}")
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
                    print(f"Entry: {trade.entry_price:.2f} → Exit: {trade.exit_price:.2f}")
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
                    print(f"Entry: {trade.entry_price:.2f} → Exit: {trade.exit_price:.2f}")
                    print(f"Profit: {pips:.1f} pips = ${trade.profit_amount:.2f}")
                    print(f"New Balance: ${self.balance:.2f}")
                    print(f"{'='*60}\n")
    
    def has_open_position(self):
        """Check if there are any open positions"""
        return any(t.status == 'OPEN' for t in self.trades)
    
    def run_backtest(self, df_m5, df_h1=None):
        """Main backtesting loop"""
        print("\n" + "="*60)
        print("STARTING BACKTEST - PRICE ACTION PATTERNS")
        print("="*60)
        print(f"Timeframe: M5, HTF Confirmation: {self.config['use_htf_confirmation'] and df_h1 is not None}")
        print(f"Patterns: Pin Bar + Engulfing")
        print(f"Risk: {self.config['risk_percent']}%, RR: 1:{self.config['rr_ratio']}")
        print(f"Initial Balance: ${self.config['initial_balance']:.2f}")
        print("="*60 + "\n")
        
        # Add indicators
        df_m5 = add_all_indicators(df_m5)
        if df_h1 is not None:
            df_h1 = add_all_indicators(df_h1)
        
        # Main loop
        for i in range(len(df_m5)):
            current_time = df_m5.index[i]
            current_bar = df_m5.iloc[i]
            
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
            
            # Detect patterns
            patterns = []
            
            # Pin Bars
            bullish_pin = detect_bullish_pin_bar(
                df_m5, i,
                min_wick_ratio=self.config['pin_min_wick_ratio'],
                max_body_ratio=self.config['pin_max_body_ratio'],
                min_total_range_pips=self.config['pin_min_range_pips'],
                pip_size=self.config['pip_size']
            )
            if bullish_pin:
                patterns.append((bullish_pin, 'BUY'))
            
            bearish_pin = detect_bearish_pin_bar(
                df_m5, i,
                min_wick_ratio=self.config['pin_min_wick_ratio'],
                max_body_ratio=self.config['pin_max_body_ratio'],
                min_total_range_pips=self.config['pin_min_range_pips'],
                pip_size=self.config['pip_size']
            )
            if bearish_pin:
                patterns.append((bearish_pin, 'SELL'))
            
            # Engulfing Patterns
            bullish_engulf = detect_bullish_engulfing(
                df_m5, i,
                min_body_ratio=self.config['engulf_min_body_ratio'],
                min_prev_body_pips=self.config['engulf_min_prev_body_pips'],
                pip_size=self.config['pip_size']
            )
            if bullish_engulf:
                patterns.append((bullish_engulf, 'BUY'))
            
            bearish_engulf = detect_bearish_engulfing(
                df_m5, i,
                min_body_ratio=self.config['engulf_min_body_ratio'],
                min_prev_body_pips=self.config['engulf_min_prev_body_pips'],
                pip_size=self.config['pip_size']
            )
            if bearish_engulf:
                patterns.append((bearish_engulf, 'SELL'))
            
            # Process patterns
            for pattern, trade_type in patterns:
                print(f"[{pattern.pattern_type}] Detected at {current_time}!")
                print(f"  Pattern Size: {pattern.pattern_size:.1f} pips, Strength: {pattern.signal_strength:.2f}")
                
                # HTF Trend Confirmation
                if self.config['use_htf_confirmation'] and df_h1 is not None:
                    htf_time = current_time.floor('1h')
                    if htf_time in df_h1.index:
                        htf_bar = df_h1.loc[htf_time]
                        if 'ma_50' in htf_bar and 'ma_200' in htf_bar and pd.notna(htf_bar['ma_50']) and pd.notna(htf_bar['ma_200']):
                            # BUY needs uptrend or sideways
                            if trade_type == 'BUY' and htf_bar['ma_50'] < htf_bar['ma_200'] * 0.995:
                                print(f"  [FAILED] HTF downtrend - skipping")
                                continue
                            # SELL needs downtrend or sideways
                            if trade_type == 'SELL' and htf_bar['ma_50'] > htf_bar['ma_200'] * 1.005:
                                print(f"  [FAILED] HTF uptrend - skipping")
                                continue
                            print(f"  [OK] HTF trend confirmation")
                
                # Trend Alignment (M5 trend)
                if self.config['use_trend_filter']:
                    if not check_trend_alignment(df_m5, i, pattern.pattern_type, use_ma=True, ma_period=50):
                        print(f"  [FAILED] Trend not aligned")
                        continue
                    print(f"  [OK] Trend aligned")
                
                # Support/Resistance Confirmation (optional)
                if self.config['use_sr_confirmation']:
                    is_support, is_resistance, level = check_support_resistance(
                        df_m5, i, pattern.entry_price,
                        lookback=self.config['sr_lookback'],
                        tolerance_pct=self.config['sr_tolerance_pct']
                    )
                    if trade_type == 'BUY' and not is_support:
                        print(f"  [FAILED] Not near support level")
                        continue
                    if trade_type == 'SELL' and not is_resistance:
                        print(f"  [FAILED] Not near resistance level")
                        continue
                    print(f"  [OK] Near S/R level: {level:.2f}")
                
                # All confirmations passed - open trade
                print(f"  [ENTRY] Opening {trade_type} trade...")
                self.open_trade(current_time, pattern, trade_type)
                break  # Only one trade at a time
        
        # Close any remaining open positions at market close
        open_trades = [t for t in self.trades if t.status == 'OPEN']
        if len(open_trades) > 0:
            last_bar = df_m5.iloc[-1]
            last_time = df_m5.index[-1]
            last_close = last_bar['close']
            
            for trade in open_trades:
                trade.close_time = last_time
                trade.exit_price = last_close
                trade.status = 'CLOSED_EOD'
                
                if trade.type == 'BUY':
                    pips = (trade.exit_price - trade.entry_price) / self.config['pip_size']
                elif trade.type == 'SELL':
                    pips = (trade.entry_price - trade.exit_price) / self.config['pip_size']
                
                pips -= self.config['execution_penalty_pips']
                trade.profit_pips = pips
                trade.profit_amount = pips * self.config['point_value'] * trade.lot_size
                
                self.balance += trade.profit_amount
                self.equity = self.balance
                
                print(f"[CLOSED EOD] Trade #{trade.trade_id}: {pips:.1f} pips = ${trade.profit_amount:.2f}")
        
        return self.generate_report()
    
    def generate_report(self):
        """Generate performance report"""
        if len(self.trades) == 0:
            print("\nNo trades executed")
            return {}
        
        closed_trades = [t for t in self.trades if t.status != 'OPEN']
        
        if len(closed_trades) == 0:
            print("\nNo closed trades")
            return {}
        
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
        
        # Pattern statistics
        pin_bars = [t for t in closed_trades if 'PIN' in t.pattern_type]
        engulfing = [t for t in closed_trades if 'ENGULFING' in t.pattern_type]
        
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
            'pin_bars': len(pin_bars),
            'engulfing': len(engulfing)
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
                'pattern': trade.pattern_type,
                'entry': trade.entry_price,
                'exit': trade.exit_price,
                'sl': trade.sl_price,
                'tp': trade.tp_price,
                'lot_size': trade.lot_size,
                'profit_pips': trade.profit_pips,
                'profit_amount': trade.profit_amount,
                'status': trade.status,
                'pattern_strength': trade.pattern_strength
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
        
        plt.xlabel('Time', fontsize=12)
        plt.ylabel('Equity ($)', fontsize=12)
        plt.title('Equity Curve - Price Action Strategy', fontsize=14, fontweight='bold')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        plt.savefig(output_path, dpi=150)
        print(f"Equity curve saved to: {output_path}")
        plt.close()


def create_default_config():
    """Create default configuration for Price Action"""
    return {
        # Account settings
        'initial_balance': 10000.0,
        'risk_percent': 1.0,
        'min_lot': 0.01,
        'max_lot': 100.0,
        'lot_step': 0.01,
        
        # Timeframe settings
        'timeframe': 'M5',
        'use_htf_confirmation': True,
        'htf_multiplier': 12,  # H1 = 12x M5
        
        # Symbol settings (XAUUSD)
        'pip_size': 0.1,
        'point_value': 1.0,
        'spread_pips': 20,
        'execution_penalty_pips': 5,
        
        # Risk/Reward
        'rr_ratio': 2.0,  # 1:2 Risk:Reward
        'sl_multiplier': 1.2,  # SL = pattern size * 1.2
        
        # Pin Bar settings
        'pin_min_wick_ratio': 0.6,  # 60% of total range
        'pin_max_body_ratio': 0.35,  # Max 35% body
        'pin_min_range_pips': 30,  # Minimum 30 pips range (STRICT)
        
        # Engulfing settings
        'engulf_min_body_ratio': 0.9,  # Current body >= 90% of previous (STRICT)
        'engulf_min_prev_body_pips': 10,  # Previous body >= 10 pips
        
        # Filters
        'use_trend_filter': True,  # Use MA(50) trend filter
        'use_sr_confirmation': True,  # Support/Resistance confirmation (ENABLED)
        'sr_lookback': 100,  # Lookback for S/R levels
        'sr_tolerance_pct': 0.15,  # 0.15% tolerance for S/R
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
        df_h1 = engine.resample_to_h1(df_m1) if config['use_htf_confirmation'] else None
        
        # Run backtest
        results = engine.run_backtest(df_m5, df_h1)
        all_results[period] = results
        
        # Export results
        engine.export_trade_log(f"{reports_dir}/trade_log_pa_{period}.csv")
        engine.plot_equity_curve(f"{reports_dir}/equity_curve_pa_{period}.png")
        
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
            print(f"  Pin Bars: {results['pin_bars']} trades")
            print(f"  Engulfing: {results['engulfing']} trades")
            print("="*60 + "\n")
    
    # Overall summary
    if all_results:
        print("\n" + "="*80)
        print("OVERALL PERFORMANCE SUMMARY")
        print("="*80)
        print(f"{'Period':<15} {'Net P/L':<15} {'Trades':<10} {'Win Rate':<12} {'Profit Factor':<15} {'Max DD%':<10}")
        print("-"*80)
        for period, results in all_results.items():
            if results:
                print(f"{period:<15} ${results['net_profit']:>10.2f}    {results['total_trades']:>4}    "
                      f"{results['win_rate']:>6.2f}%      {results['profit_factor']:>6.2f}        "
                      f"{results['max_drawdown_pct']:>6.2f}%")
        print("="*80 + "\n")


if __name__ == "__main__":
    main()
