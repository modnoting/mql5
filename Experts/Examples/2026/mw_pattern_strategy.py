"""
M&W Pattern Strategy Module
Implements pattern detection, momentum confirmations, and trend filters
Based on Devilmod-M-W EA logic
"""

import pandas as pd
import numpy as np
from datetime import datetime, time


class PatternInfo:
    """Structure to hold pattern information"""
    def __init__(self):
        self.found = False
        self.time = None
        self.type = 0  # 1=M pattern (SELL), 2=W pattern (BUY)
        # M pattern (double top) attributes
        self.peak1_price = 0
        self.peak2_price = 0
        self.peak1_index = 0
        self.peak2_index = 0
        self.valley1_price = 0
        self.valley2_price = 0
        self.valley1_index = 0
        self.valley2_index = 0
        # W pattern (double bottom) attributes
        self.trough1_price = 0
        self.trough2_price = 0
        self.trough1_index = 0
        self.trough2_index = 0
        self.peak_price = 0
        self.peak_index = 0
        # Common attributes
        self.neckline_price = 0
        self.neckline_index = 0
        self.pattern_height = 0
        self.neckline_broken = False
        self.waiting_retest = False
        self.break_time = None


def find_swing_highs(highs, strength=5):
    """
    Find swing high points in price data
    
    Args:
        highs: pandas Series of high prices
        strength: Number of bars each side to confirm swing (default 5)
    
    Returns:
        list of indices where swing highs occur
    """
    swing_highs = []
    highs_array = highs.values
    
    for i in range(strength, len(highs_array) - strength):
        is_swing_high = True
        
        # Check left side
        for j in range(1, strength + 1):
            if highs_array[i] <= highs_array[i - j]:
                is_swing_high = False
                break
        
        # Check right side
        if is_swing_high:
            for j in range(1, strength + 1):
                if highs_array[i] <= highs_array[i + j]:
                    is_swing_high = False
                    break
        
        if is_swing_high:
            swing_highs.append(i)
    
    return swing_highs


def find_swing_lows(lows, strength=5):
    """
    Find swing low points in price data
    
    Args:
        lows: pandas Series of low prices
        strength: Number of bars each side to confirm swing (default 5)
    
    Returns:
        list of indices where swing lows occur
    """
    swing_lows = []
    lows_array = lows.values
    
    for i in range(strength, len(lows_array) - strength):
        is_swing_low = True
        
        # Check left side
        for j in range(1, strength + 1):
            if lows_array[i] >= lows_array[i - j]:
                is_swing_low = False
                break
        
        # Check right side
        if is_swing_low:
            for j in range(1, strength + 1):
                if lows_array[i] >= lows_array[i + j]:
                    is_swing_low = False
                    break
        
        if is_swing_low:
            swing_lows.append(i)
    
    return swing_lows


def detect_double_top(df, current_idx, tolerance_pct=0.2, min_retracement=10.0,
                      neckline_break_pct=0.3, swing_strength=5, lookback_bars=100):
    """
    Detect M Pattern (Double Top)
    
    Args:
        df: DataFrame with OHLC and indicators
        current_idx: Current bar index
        tolerance_pct: Pattern tolerance percentage (default 0.2%)
        min_retracement: Minimum retracement percentage (default 10%)
        neckline_break_pct: Neckline break threshold percentage (default 0.3%)
        swing_strength: Swing strength for detection (default 5)
        lookback_bars: Bars to look back (default 100)
    
    Returns:
        PatternInfo object or None
    """
    start_idx = max(0, current_idx - lookback_bars)
    df_slice = df.iloc[start_idx:current_idx + 1].copy()
    
    if len(df_slice) < lookback_bars // 2:
        return None
    
    # Find swing highs
    swing_highs = find_swing_highs(df_slice['high'], strength=swing_strength)
    
    if len(swing_highs) < 2:
        return None
    
    # Check pairs of swing highs (from most recent backwards)
    for i in range(len(swing_highs) - 2, -1, -1):
        idx1 = swing_highs[i]
        idx2 = swing_highs[i + 1]
        
        p1_high = df_slice.iloc[idx1]['high']
        p2_high = df_slice.iloc[idx2]['high']
        
        # Check distance between peaks
        bars_between = idx2 - idx1
        if bars_between < 15 or bars_between > 80:
            continue
        
        # Check peak similarity (tolerance)
        price_diff = abs(p1_high - p2_high)
        tolerance = p1_high * (tolerance_pct / 100.0)
        if price_diff > tolerance:
            continue
        
        # Find valley between peaks
        valley_idx = idx1
        valley_price = df_slice.iloc[idx1]['low']
        for j in range(idx1, idx2 + 1):
            if df_slice.iloc[j]['low'] < valley_price:
                valley_price = df_slice.iloc[j]['low']
                valley_idx = j
        
        # Check retracement depth
        avg_peak = (p1_high + p2_high) / 2.0
        retracement = ((avg_peak - valley_price) / avg_peak) * 100.0
        if retracement < min_retracement:
            continue
        
        # Check neckline break
        neckline = valley_price
        break_threshold = neckline * (1.0 - neckline_break_pct / 100.0)
        
        current_close = df.iloc[current_idx]['close']
        prev_close = df.iloc[current_idx - 1]['close'] if current_idx > 0 else current_close
        
        if current_close < break_threshold and prev_close >= neckline:
            # Pattern found and neckline broken!
            pattern = PatternInfo()
            pattern.found = True
            pattern.type = 1  # M pattern
            pattern.peak1_price = p1_high
            pattern.peak2_price = p2_high
            pattern.peak1_index = start_idx + idx1
            pattern.peak2_index = start_idx + idx2
            pattern.valley1_price = valley_price
            pattern.valley2_price = valley_price  # Single valley between peaks
            pattern.valley1_index = start_idx + valley_idx
            pattern.valley2_index = start_idx + valley_idx
            pattern.neckline_price = neckline
            pattern.neckline_index = start_idx + valley_idx
            pattern.pattern_height = avg_peak - neckline
            pattern.neckline_broken = True
            pattern.time = df.index[current_idx]
            
            return pattern
    
    return None


def detect_double_bottom(df, current_idx, tolerance_pct=0.2, min_retracement=10.0,
                         neckline_break_pct=0.3, swing_strength=5, lookback_bars=100):
    """
    Detect W Pattern (Double Bottom)
    
    Args:
        df: DataFrame with OHLC and indicators
        current_idx: Current bar index
        tolerance_pct: Pattern tolerance percentage (default 0.2%)
        min_retracement: Minimum retracement percentage (default 10%)
        neckline_break_pct: Neckline break threshold percentage (default 0.3%)
        swing_strength: Swing strength for detection (default 5)
        lookback_bars: Bars to look back (default 100)
    
    Returns:
        PatternInfo object or None
    """
    start_idx = max(0, current_idx - lookback_bars)
    df_slice = df.iloc[start_idx:current_idx + 1].copy()
    
    if len(df_slice) < lookback_bars // 2:
        return None
    
    # Find swing lows
    swing_lows = find_swing_lows(df_slice['low'], strength=swing_strength)
    
    if len(swing_lows) < 2:
        return None
    
    # Check pairs of swing lows (from most recent backwards)
    for i in range(len(swing_lows) - 2, -1, -1):
        idx1 = swing_lows[i]
        idx2 = swing_lows[i + 1]
        
        t1_low = df_slice.iloc[idx1]['low']
        t2_low = df_slice.iloc[idx2]['low']
        
        # Check distance between troughs
        bars_between = idx2 - idx1
        if bars_between < 15 or bars_between > 80:
            continue
        
        # Check trough similarity (tolerance)
        price_diff = abs(t1_low - t2_low)
        tolerance = t1_low * (tolerance_pct / 100.0)
        if price_diff > tolerance:
            continue
        
        # Find peak between troughs
        peak_idx = idx1
        peak_price = df_slice.iloc[idx1]['high']
        for j in range(idx1, idx2 + 1):
            if df_slice.iloc[j]['high'] > peak_price:
                peak_price = df_slice.iloc[j]['high']
                peak_idx = j
        
        # Check rally height
        avg_trough = (t1_low + t2_low) / 2.0
        rally = ((peak_price - avg_trough) / avg_trough) * 100.0
        
        if rally < min_retracement:
            continue
        
        # Check neckline break (relaxed condition)
        neckline = peak_price
        break_threshold = neckline * (1.0 + neckline_break_pct / 100.0)
        
        current_close = df.iloc[current_idx]['close']
        
        # Relaxed: just check if price is above break threshold (don't require exact timing)
        if current_close > break_threshold:
            # Pattern found and neckline broken!
            pattern = PatternInfo()
            pattern.found = True
            pattern.type = 2  # W pattern
            pattern.trough1_price = t1_low
            pattern.trough2_price = t2_low
            pattern.trough1_index = start_idx + idx1
            pattern.trough2_index = start_idx + idx2
            pattern.peak_price = peak_price
            pattern.peak_index = start_idx + peak_idx
            pattern.neckline_price = neckline
            pattern.neckline_index = start_idx + peak_idx
            pattern.pattern_height = neckline - avg_trough
            pattern.neckline_broken = True
            pattern.time = df.index[current_idx]
            
            return pattern
    
    return None


def check_rsi_divergence(df, peak1_idx, peak2_idx, pattern_type):
    """
    Check RSI divergence for pattern confirmation
    
    Args:
        df: DataFrame with indicators
        peak1_idx: Index of first peak/trough
        peak2_idx: Index of second peak/trough
        pattern_type: 1=M pattern, 2=W pattern
    
    Returns:
        bool: True if divergence confirmed
    """
    if 'RSI' not in df.columns:
        return True  # Skip if RSI not available
    
    rsi1 = df.iloc[peak1_idx]['RSI']
    rsi2 = df.iloc[peak2_idx]['RSI']
    
    if pd.isna(rsi1) or pd.isna(rsi2):
        return True
    
    if pattern_type == 1:  # M pattern (SELL)
        # RSI at peak2 should be lower than peak1 (Bearish Divergence)
        return rsi2 < rsi1 - 2.0
    elif pattern_type == 2:  # W pattern (BUY)
        # RSI at trough2 should be higher than trough1 (Bullish Divergence)
        return rsi2 > rsi1 + 2.0
    
    return False


def check_macd_weakness(df, peak1_idx, peak2_idx):
    """
    Check MACD weakness for pattern confirmation
    
    Args:
        df: DataFrame with indicators
        peak1_idx: Index of first peak/trough
        peak2_idx: Index of second peak/trough
    
    Returns:
        bool: True if weakness confirmed
    """
    if 'MACD' not in df.columns:
        return True  # Skip if MACD not available
    
    macd1 = df.iloc[peak1_idx]['MACD']
    macd2 = df.iloc[peak2_idx]['MACD']
    
    if pd.isna(macd1) or pd.isna(macd2):
        return True
    
    # MACD at peak2 should be weaker (smaller absolute value)
    return abs(macd2) < abs(macd1)


def check_rejection_candle(df, index, is_top):
    """
    Check for rejection candle pattern
    
    Args:
        df: DataFrame with OHLC data
        index: Bar index to check
        is_top: True for top rejection (shooting star), False for bottom (hammer)
    
    Returns:
        bool: True if rejection candle found
    """
    row = df.iloc[index]
    body = abs(row['close'] - row['open'])
    
    if is_top:
        # Check for shooting star or bearish engulfing
        upper_wick = row['high'] - max(row['close'], row['open'])
        return upper_wick > body * 2.0
    else:
        # Check for hammer or bullish engulfing
        lower_wick = min(row['close'], row['open']) - row['low']
        return lower_wick > body * 2.0


def check_momentum_confirmation(df, pattern, use_rsi=True, use_macd=True, use_rejection=False):
    """
    Check momentum confirmations (need at least 50% to pass)
    
    Args:
        df: DataFrame with indicators
        pattern: PatternInfo object
        use_rsi: Use RSI divergence check
        use_macd: Use MACD weakness check
        use_rejection: Use rejection candle check
    
    Returns:
        bool: True if momentum confirmed
    """
    checks_passed = 0
    checks_total = 0
    
    # RSI Divergence
    if use_rsi:
        checks_total += 1
        if check_rsi_divergence(df, pattern.peak1_index, pattern.peak2_index, pattern.type):
            checks_passed += 1
    
    # MACD Weakness
    if use_macd:
        checks_total += 1
        if check_macd_weakness(df, pattern.peak1_index, pattern.peak2_index):
            checks_passed += 1
    
    # Rejection Candle
    if use_rejection:
        checks_total += 1
        is_top = (pattern.type == 1)
        if check_rejection_candle(df, pattern.peak2_index, is_top):
            checks_passed += 1
    
    if checks_total == 0:
        return True  # No checks enabled
    
    pass_rate = checks_passed / checks_total
    return pass_rate >= 0.5


def check_trend_filter(df, current_idx, pattern_type, use_filter=True):
    """
    Check trend filter using MA50 and MA200
    
    Args:
        df: DataFrame with indicators
        current_idx: Current bar index
        pattern_type: 1=M pattern (SELL), 2=W pattern (BUY)
        use_filter: Enable/disable trend filter
    
    Returns:
        bool: True if trend is appropriate for pattern
    """
    if not use_filter:
        return True
    
    if 'MA50' not in df.columns or 'MA200' not in df.columns:
        return True  # Skip if MAs not available
    
    current_close = df.iloc[current_idx]['close']
    ma50 = df.iloc[current_idx]['MA50']
    ma200 = df.iloc[current_idx]['MA200']
    
    if pd.isna(ma50) or pd.isna(ma200):
        return True
    
    if pattern_type == 1:  # M pattern (SELL)
        # Price below MA50 OR MA50 below MA200 (downtrend)
        return (current_close < ma50) or (ma50 < ma200)
    elif pattern_type == 2:  # W pattern (BUY)
        # Price above MA50 OR MA50 above MA200 (uptrend)
        return (current_close > ma50) or (ma50 > ma200)
    
    return False


def is_valid_trading_time(timestamp, use_filter=True, time_mode='OPTIMIZED', 
                          start_hour=15, end_hour=23, day_settings=None):
    """
    Check if current time is valid for trading
    
    Args:
        timestamp: pandas Timestamp
        use_filter: Enable/disable time filter
        time_mode: 'SIMPLE' or 'OPTIMIZED'
        start_hour: Start hour for SIMPLE mode (default 15)
        end_hour: End hour for SIMPLE mode (default 23)
        day_settings: Dict with day-specific settings for OPTIMIZED mode
    
    Returns:
        bool: True if valid trading time
    """
    if not use_filter:
        return True
    
    # Block weekends
    if timestamp.dayofweek >= 5:  # 5=Saturday, 6=Sunday
        return False
    
    hour = timestamp.hour
    
    if time_mode == 'SIMPLE':
        return start_hour <= hour <= end_hour
    
    elif time_mode == 'OPTIMIZED':
        if day_settings is None:
            # Default optimized settings
            day_settings = {
                0: {'enabled': True, 'start': 15, 'end': 23},  # Monday
                1: {'enabled': True, 'start': 14, 'end': 23},  # Tuesday
                2: {'enabled': True, 'start': 14, 'end': 23},  # Wednesday
                3: {'enabled': True, 'start': 14, 'end': 23},  # Thursday
                4: {'enabled': True, 'start': 14, 'end': 20},  # Friday
            }
        
        day_of_week = timestamp.dayofweek  # 0=Monday, 4=Friday
        
        if day_of_week not in day_settings:
            return False
        
        settings = day_settings[day_of_week]
        
        if not settings['enabled']:
            return False
        
        return settings['start'] <= hour <= settings['end']
    
    return True


def check_retest(df, current_idx, pattern, tolerance_pct=0.2):
    """
    Check if price is retesting the neckline (for Conservative entry)
    
    Args:
        df: DataFrame with OHLC data
        current_idx: Current bar index
        pattern: PatternInfo object
        tolerance_pct: Tolerance percentage (default 0.2%)
    
    Returns:
        bool: True if retest detected
    """
    current_close = df.iloc[current_idx]['close']
    neckline = pattern.neckline_price
    tolerance = neckline * (tolerance_pct / 100.0)
    
    if pattern.type == 1:  # M pattern (SELL)
        # Price came back up to test neckline from below
        return neckline - tolerance <= current_close <= neckline + tolerance
    elif pattern.type == 2:  # W pattern (BUY)
        # Price came back down to test neckline from above
        return neckline - tolerance <= current_close <= neckline + tolerance
    
    return False
