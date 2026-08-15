"""
Hybrid Strategy Module - MA H1 Aggressive + M&W Pattern
Combines two profitable strategies:
1. MA Crossover H1 (6% risk, high frequency)
2. M&W Pattern (1% risk, high quality)
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from typing import Optional
from ma_crossover_strategy import detect_signal as detect_ma_signal
from mw_pattern_strategy import (
    detect_double_top, 
    detect_double_bottom,
    check_momentum_confirmation,
    check_trend_filter,
    is_valid_trading_time
)


@dataclass
class HybridSignal:
    """Combined signal from both strategies"""
    signal_type: str  # 'BUY' or 'SELL'
    strategy: str  # 'MA_H1' or 'MW_PATTERN'
    bar_index: int
    signal_time: pd.Timestamp
    confidence: float  # 0-1
    risk_percent: float  # 6% for MA, 1% for M&W
    rr_ratio: float  # 3.0 for MA, 1.5 for M&W
    entry_price: float
    stop_loss: float
    take_profit: float
    atr: float
    details: dict  # Additional strategy-specific details


class HybridStrategyEngine:
    """Engine to combine MA H1 Aggressive + M&W Pattern signals"""
    
    def __init__(self, config):
        self.config = config
        
        # Track last signal bars to prevent duplicates
        self.last_ma_signal_bar = -1
        self.last_mw_signal_bar = -1
        self.last_mw_neckline_price = 0.0  # Track last neckline to avoid similar patterns
        self.mw_cooldown_bars = config.get('mw_cooldown_bars', 100)  # 100 bars minimum (M&W is rare pattern)
        
        # MA H1 config
        self.ma_config = {
            'timeframe': 'H1',
            'risk_percent': config.get('ma_risk_percent', 6.0),
            'rr_ratio': config.get('ma_rr_ratio', 3.0),
            'atr_multiplier': config.get('ma_atr_multiplier', 1.5),
            'use_compound': config.get('use_compound', True),
            'min_adx': config.get('ma_min_adx', 15),
            'use_trend_filter': True,
            'use_adx_filter': True,
            'macd_fast': 12,
            'macd_slow': 26,
            'macd_signal': 9,
            'pip_size': 0.1,
            'point_value': 1.0,
            'min_lot': 0.01,
            'max_lot': 100.0,
            'lot_step': 0.01
        }
        
        # M&W Pattern config
        self.mw_config = {
            'risk_percent': config.get('mw_risk_percent', 1.0),
            'rr_ratio': config.get('mw_rr_ratio', 1.5),
            'tolerance_pct': config.get('mw_tolerance', 2.0),  # Increased from 1.5%
            'min_retracement': config.get('mw_min_retracement', 0.3),  # Decreased from 0.4%
            'neckline_break_pct': config.get('mw_neckline_break', 0.2),  # Decreased from 0.25%
            'swing_strength': config.get('mw_swing_strength', 2),
            'lookback_bars': config.get('mw_lookback', 120),
            'use_trend_filter': False,  # Disabled for more signals
            'use_momentum_confirmation': False,  # Simplified
            'use_time_filter': False,  # 24/7 trading
            'pip_size': 0.1,
            'point_value': 1.0
        }
    
    def detect_ma_signal(self, df, i):
        """Detect MA Crossover H1 signal"""
        try:
            signal = detect_ma_signal(df, i, self.ma_config)
            
            if signal is None:
                return None
            
            # Calculate SL/TP based on ATR
            entry_price = df.loc[i, 'close']
            atr = df.loc[i, 'ATR'] if 'ATR' in df.columns else df.loc[i, 'atr']
            atr_mult = self.ma_config['atr_multiplier']
            rr_ratio = self.ma_config['rr_ratio']
            
            if signal.signal_type == 'BUY':
                stop_loss = entry_price - (atr * atr_mult)
                take_profit = entry_price + (atr * atr_mult * rr_ratio)
            else:
                stop_loss = entry_price + (atr * atr_mult)
                take_profit = entry_price - (atr * atr_mult * rr_ratio)
            
            return HybridSignal(
                signal_type=signal.signal_type,
                strategy='MA_H1',
                bar_index=i,
                signal_time=signal.signal_time,
                confidence=signal.signal_strength,
                risk_percent=self.ma_config['risk_percent'],
                rr_ratio=self.ma_config['rr_ratio'],
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit=take_profit,
                atr=atr,
                details={
                    'macd_value': signal.macd_value,
                    'histogram_value': signal.histogram_value,
                    'adx_value': signal.adx_value,
                    'trend_direction': signal.trend_direction
                }
            )
        except Exception as e:
            print(f"WARNING: detect_ma_signal exception at bar {i}: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def detect_mw_signal(self, df, i):
        """Detect M&W Pattern signal"""
        try:
            # Check for Double Top
            dt_pattern = detect_double_top(
                df, i,
                tolerance_pct=self.mw_config['tolerance_pct'],
                min_retracement=self.mw_config['min_retracement'],
                neckline_break_pct=self.mw_config['neckline_break_pct'],
                swing_strength=self.mw_config['swing_strength'],
                lookback_bars=self.mw_config['lookback_bars']
            )
            
            if dt_pattern:
                # Check trend filter
                if self.mw_config['use_trend_filter']:
                    if not check_trend_filter(df, i, 'SELL', use_filter=True):
                        dt_pattern = None
            
            # Check for Double Bottom
            db_pattern = detect_double_bottom(
                df, i,
                tolerance_pct=self.mw_config['tolerance_pct'],
                min_retracement=self.mw_config['min_retracement'],
                neckline_break_pct=self.mw_config['neckline_break_pct'],
                swing_strength=self.mw_config['swing_strength'],
                lookback_bars=self.mw_config['lookback_bars']
            )
            
            if db_pattern:
                # Check trend filter
                if self.mw_config['use_trend_filter']:
                    if not check_trend_filter(df, i, 'BUY', use_filter=True):
                        db_pattern = None
            
            # Choose which pattern to use
            pattern = None
            signal_type = None
            
            if dt_pattern:
                pattern = dt_pattern
                signal_type = 'SELL'
            elif db_pattern:
                pattern = db_pattern
                signal_type = 'BUY'
            
            if pattern is None:
                return None
            
            # Check neckline similarity to avoid detecting same pattern
            neckline_tolerance_pct = 0.5  # 0.5% tolerance
            if self.last_mw_neckline_price > 0:
                price_diff_pct = abs(pattern.neckline_price - self.last_mw_neckline_price) / self.last_mw_neckline_price * 100
                if price_diff_pct < neckline_tolerance_pct:
                    # Same neckline area, skip
                    return None
            
            # Check cooldown to prevent signals too close together
            if self.last_mw_signal_bar >= 0:
                bars_since_last = i - self.last_mw_signal_bar
                if bars_since_last < self.mw_cooldown_bars:
                    return None  # Too soon, skip this signal
            
            # Update last signal bar and neckline
            self.last_mw_signal_bar = i
            self.last_mw_neckline_price = pattern.neckline_price
            
            # Get entry details
            entry_price = df.loc[i, 'close']
            atr = df.loc[i, 'ATR'] if 'ATR' in df.columns else df.loc[i, 'atr']
            
            # Calculate SL/TP based on pattern
            if signal_type == 'SELL':
                stop_loss = pattern.peak2_price + (atr * 0.5)  # Above peak
                distance = entry_price - stop_loss
                take_profit = entry_price - (abs(distance) * self.mw_config['rr_ratio'])
            else:  # BUY
                stop_loss = pattern.trough2_price - (atr * 0.5)  # Below trough
                distance = stop_loss - entry_price
                take_profit = entry_price + (abs(distance) * self.mw_config['rr_ratio'])
            
            return HybridSignal(
                signal_type=signal_type,
                strategy='MW_PATTERN',
                bar_index=i,
                signal_time=df.loc[i, 'datetime'] if 'datetime' in df.columns else pd.Timestamp.now(),
                confidence=0.9,  # High confidence for pattern
                risk_percent=self.mw_config['risk_percent'],
                rr_ratio=self.mw_config['rr_ratio'],
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit=take_profit,
                atr=atr,
                details={
                    'pattern_type': pattern.type,
                    'peak1_price': getattr(pattern, 'peak1_price', None) or getattr(pattern, 'trough1_price', None),
                    'peak2_price': getattr(pattern, 'peak2_price', None) or getattr(pattern, 'trough2_price', None),
                    'neckline': pattern.neckline_price
                }
            )
        except Exception as e:
            print(f"WARNING: detect_mw_signal exception at bar {i}: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def detect_hybrid_signal(self, df, i):
        """
        Detect signals from both strategies
        Priority: M&W Pattern > MA H1 (due to higher quality)
        
        Returns:
            HybridSignal or None
        """
        # Check M&W Pattern first (higher quality, lower frequency)
        mw_signal = self.detect_mw_signal(df, i)
        if mw_signal:
            return mw_signal
        
        # Check MA H1 (higher frequency, lower quality)
        ma_signal = self.detect_ma_signal(df, i)
        if ma_signal:
            return ma_signal
        
        return None
    
    def get_strategy_stats(self):
        """Get statistics about which strategy is being used"""
        return {
            'ma_h1': {
                'risk': self.ma_config['risk_percent'],
                'rr': self.ma_config['rr_ratio'],
                'frequency': 'High (0.5-1 trade/day)'
            },
            'mw_pattern': {
                'risk': self.mw_config['risk_percent'],
                'rr': self.mw_config['rr_ratio'],
                'frequency': 'Low (0.1 trade/day)'
            }
        }


def create_hybrid_config(initial_balance=100.0, use_compound=True):
    """Create configuration for hybrid strategy"""
    return {
        'initial_balance': initial_balance,
        'use_compound': use_compound,
        
        # MA H1 settings (AGGRESSIVE)
        'ma_risk_percent': 6.0,
        'ma_rr_ratio': 3.0,
        'ma_atr_multiplier': 1.5,
        'ma_min_adx': 15,
        
        # M&W Pattern settings (CONSERVATIVE)
        'mw_risk_percent': 1.0,
        'mw_rr_ratio': 1.5,
        'mw_tolerance': 1.5,
        'mw_min_retracement': 0.4,
        'mw_neckline_break': 0.25,
        'mw_swing_strength': 2,
        'mw_lookback': 120,
        
        # Common settings
        'pip_size': 0.1,
        'point_value': 1.0,
        'spread_pips': 20,
        'execution_penalty_pips': 5
    }
