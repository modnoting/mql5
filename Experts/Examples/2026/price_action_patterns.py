"""
Price Action Pattern Detection
Detects Pin Bars and Engulfing patterns for M5 scalping
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass

@dataclass
class PatternInfo:
    """Information about detected pattern"""
    pattern_type: str  # 'BULLISH_PIN', 'BEARISH_PIN', 'BULLISH_ENGULFING', 'BEARISH_ENGULFING'
    bar_index: int
    signal_time: pd.Timestamp
    entry_price: float
    signal_strength: float  # 0-1 score
    pattern_size: float  # Pattern size in pips
    
    # Pattern specific info
    body_size: float = 0
    wick_size: float = 0
    total_range: float = 0


def detect_bullish_pin_bar(df, i, min_wick_ratio=0.6, max_body_ratio=0.35, min_total_range_pips=20, pip_size=0.1):
    """
    Detect Bullish Pin Bar (Hammer)
    - Long lower wick (rejection at support)
    - Small body at top
    - Short upper wick
    
    Args:
        df: DataFrame with OHLC data
        i: Current bar index
        min_wick_ratio: Minimum lower wick / total range (default 0.6 = 60%)
        max_body_ratio: Maximum body / total range (default 0.35 = 35%)
        min_total_range_pips: Minimum total range in pips
        pip_size: Pip size for symbol
    
    Returns:
        PatternInfo if pattern detected, None otherwise
    """
    if i < 1:
        return None
    
    bar = df.iloc[i]
    open_price = bar['open']
    high = bar['high']
    low = bar['low']
    close = bar['close']
    
    # Calculate components
    total_range = high - low
    body = abs(close - open_price)
    upper_wick = high - max(close, open_price)
    lower_wick = min(close, open_price) - low
    
    # Check minimum range
    if total_range / pip_size < min_total_range_pips:
        return None
    
    # Avoid zero division
    if total_range == 0:
        return None
    
    # Calculate ratios
    body_ratio = body / total_range
    lower_wick_ratio = lower_wick / total_range
    upper_wick_ratio = upper_wick / total_range
    
    # Pin Bar conditions:
    # 1. Long lower wick (rejection)
    # 2. Small body
    # 3. Short upper wick
    # 4. Close near high (bullish)
    if (lower_wick_ratio >= min_wick_ratio and
        body_ratio <= max_body_ratio and
        upper_wick_ratio < 0.2 and
        close > open_price):  # Bullish close
        
        # Calculate signal strength (0-1)
        strength = min(1.0, lower_wick_ratio + (1 - body_ratio))
        
        return PatternInfo(
            pattern_type='BULLISH_PIN',
            bar_index=i,
            signal_time=df.index[i],
            entry_price=close,
            signal_strength=strength,
            pattern_size=total_range / pip_size,
            body_size=body / pip_size,
            wick_size=lower_wick / pip_size,
            total_range=total_range / pip_size
        )
    
    return None


def detect_bearish_pin_bar(df, i, min_wick_ratio=0.6, max_body_ratio=0.35, min_total_range_pips=20, pip_size=0.1):
    """
    Detect Bearish Pin Bar (Shooting Star)
    - Long upper wick (rejection at resistance)
    - Small body at bottom
    - Short lower wick
    
    Args:
        df: DataFrame with OHLC data
        i: Current bar index
        min_wick_ratio: Minimum upper wick / total range (default 0.6 = 60%)
        max_body_ratio: Maximum body / total range (default 0.35 = 35%)
        min_total_range_pips: Minimum total range in pips
        pip_size: Pip size for symbol
    
    Returns:
        PatternInfo if pattern detected, None otherwise
    """
    if i < 1:
        return None
    
    bar = df.iloc[i]
    open_price = bar['open']
    high = bar['high']
    low = bar['low']
    close = bar['close']
    
    # Calculate components
    total_range = high - low
    body = abs(close - open_price)
    upper_wick = high - max(close, open_price)
    lower_wick = min(close, open_price) - low
    
    # Check minimum range
    if total_range / pip_size < min_total_range_pips:
        return None
    
    # Avoid zero division
    if total_range == 0:
        return None
    
    # Calculate ratios
    body_ratio = body / total_range
    upper_wick_ratio = upper_wick / total_range
    lower_wick_ratio = lower_wick / total_range
    
    # Pin Bar conditions:
    # 1. Long upper wick (rejection)
    # 2. Small body
    # 3. Short lower wick
    # 4. Close near low (bearish)
    if (upper_wick_ratio >= min_wick_ratio and
        body_ratio <= max_body_ratio and
        lower_wick_ratio < 0.2 and
        close < open_price):  # Bearish close
        
        # Calculate signal strength (0-1)
        strength = min(1.0, upper_wick_ratio + (1 - body_ratio))
        
        return PatternInfo(
            pattern_type='BEARISH_PIN',
            bar_index=i,
            signal_time=df.index[i],
            entry_price=close,
            signal_strength=strength,
            pattern_size=total_range / pip_size,
            body_size=body / pip_size,
            wick_size=upper_wick / pip_size,
            total_range=total_range / pip_size
        )
    
    return None


def detect_bullish_engulfing(df, i, min_body_ratio=0.7, min_prev_body_pips=10, pip_size=0.1):
    """
    Detect Bullish Engulfing Pattern
    - Previous candle is bearish (red)
    - Current candle is bullish (green)
    - Current body completely engulfs previous body
    
    Args:
        df: DataFrame with OHLC data
        i: Current bar index
        min_body_ratio: Minimum current body / previous body (default 0.7)
        min_prev_body_pips: Minimum previous candle body size in pips
        pip_size: Pip size for symbol
    
    Returns:
        PatternInfo if pattern detected, None otherwise
    """
    if i < 1:
        return None
    
    prev_bar = df.iloc[i-1]
    curr_bar = df.iloc[i]
    
    # Previous candle
    prev_open = prev_bar['open']
    prev_close = prev_bar['close']
    prev_body = abs(prev_close - prev_open)
    
    # Current candle
    curr_open = curr_bar['open']
    curr_high = curr_bar['high']
    curr_low = curr_bar['low']
    curr_close = curr_bar['close']
    curr_body = abs(curr_close - curr_open)
    
    # Check minimum previous body size
    if prev_body / pip_size < min_prev_body_pips:
        return None
    
    # Conditions:
    # 1. Previous candle is bearish
    # 2. Current candle is bullish
    # 3. Current open < previous close
    # 4. Current close > previous open
    # 5. Current body is significant
    if (prev_close < prev_open and  # Previous bearish
        curr_close > curr_open and  # Current bullish
        curr_open <= prev_close and  # Engulfs below
        curr_close >= prev_open and  # Engulfs above
        curr_body >= prev_body * min_body_ratio):  # Strong engulf
        
        # Calculate signal strength
        engulf_ratio = curr_body / prev_body
        strength = min(1.0, engulf_ratio)
        
        pattern_size = (curr_high - curr_low) / pip_size
        
        return PatternInfo(
            pattern_type='BULLISH_ENGULFING',
            bar_index=i,
            signal_time=df.index[i],
            entry_price=curr_close,
            signal_strength=strength,
            pattern_size=pattern_size,
            body_size=curr_body / pip_size,
            wick_size=0,  # N/A for engulfing
            total_range=pattern_size
        )
    
    return None


def detect_bearish_engulfing(df, i, min_body_ratio=0.7, min_prev_body_pips=10, pip_size=0.1):
    """
    Detect Bearish Engulfing Pattern
    - Previous candle is bullish (green)
    - Current candle is bearish (red)
    - Current body completely engulfs previous body
    
    Args:
        df: DataFrame with OHLC data
        i: Current bar index
        min_body_ratio: Minimum current body / previous body (default 0.7)
        min_prev_body_pips: Minimum previous candle body size in pips
        pip_size: Pip size for symbol
    
    Returns:
        PatternInfo if pattern detected, None otherwise
    """
    if i < 1:
        return None
    
    prev_bar = df.iloc[i-1]
    curr_bar = df.iloc[i]
    
    # Previous candle
    prev_open = prev_bar['open']
    prev_close = prev_bar['close']
    prev_body = abs(prev_close - prev_open)
    
    # Current candle
    curr_open = curr_bar['open']
    curr_high = curr_bar['high']
    curr_low = curr_bar['low']
    curr_close = curr_bar['close']
    curr_body = abs(curr_close - curr_open)
    
    # Check minimum previous body size
    if prev_body / pip_size < min_prev_body_pips:
        return None
    
    # Conditions:
    # 1. Previous candle is bullish
    # 2. Current candle is bearish
    # 3. Current open > previous close
    # 4. Current close < previous open
    # 5. Current body is significant
    if (prev_close > prev_open and  # Previous bullish
        curr_close < curr_open and  # Current bearish
        curr_open >= prev_close and  # Engulfs above
        curr_close <= prev_open and  # Engulfs below
        curr_body >= prev_body * min_body_ratio):  # Strong engulf
        
        # Calculate signal strength
        engulf_ratio = curr_body / prev_body
        strength = min(1.0, engulf_ratio)
        
        pattern_size = (curr_high - curr_low) / pip_size
        
        return PatternInfo(
            pattern_type='BEARISH_ENGULFING',
            bar_index=i,
            signal_time=df.index[i],
            entry_price=curr_close,
            signal_strength=strength,
            pattern_size=pattern_size,
            body_size=curr_body / pip_size,
            wick_size=0,  # N/A for engulfing
            total_range=pattern_size
        )
    
    return None


def check_support_resistance(df, i, price, lookback=100, tolerance_pct=0.15):
    """
    Check if price is near significant support or resistance level
    
    Args:
        df: DataFrame with OHLC data
        i: Current bar index
        price: Price to check
        lookback: Number of bars to look back
        tolerance_pct: Tolerance in percentage
    
    Returns:
        (is_near_support, is_near_resistance, level_price)
    """
    if i < lookback:
        lookback = i
    
    if lookback < 20:
        return (False, False, None)
    
    # Get historical data
    hist_data = df.iloc[max(0, i-lookback):i]
    
    # Find swing highs and lows
    highs = hist_data['high'].values
    lows = hist_data['low'].values
    
    # Calculate support and resistance levels
    resistance_levels = []
    support_levels = []
    
    # Simple approach: use recent swing points
    for j in range(5, len(highs)-5):
        # Swing high
        if highs[j] == max(highs[j-5:j+6]):
            resistance_levels.append(highs[j])
        # Swing low
        if lows[j] == min(lows[j-5:j+6]):
            support_levels.append(lows[j])
    
    # Check if price is near any level
    tolerance = price * (tolerance_pct / 100)
    
    is_near_support = False
    is_near_resistance = False
    level_price = None
    
    for support in support_levels:
        if abs(price - support) <= tolerance:
            is_near_support = True
            level_price = support
            break
    
    for resistance in resistance_levels:
        if abs(price - resistance) <= tolerance:
            is_near_resistance = True
            level_price = resistance
            break
    
    return (is_near_support, is_near_resistance, level_price)


def check_trend_alignment(df, i, pattern_type, use_ma=True, ma_period=50):
    """
    Check if pattern aligns with trend
    
    Args:
        df: DataFrame with indicators
        i: Current bar index
        pattern_type: Pattern type (BULLISH_* or BEARISH_*)
        use_ma: Use moving average for trend filter
        ma_period: MA period
    
    Returns:
        True if aligned with trend, False otherwise
    """
    if not use_ma:
        return True
    
    ma_col = f'ma_{ma_period}'
    if ma_col not in df.columns or i < ma_period:
        return True  # No filter if MA not available
    
    bar = df.iloc[i]
    current_price = bar['close']
    ma_value = bar[ma_col]
    
    if pd.isna(ma_value):
        return True
    
    # Bullish patterns should be in uptrend (price > MA)
    if 'BULLISH' in pattern_type:
        return current_price > ma_value
    
    # Bearish patterns should be in downtrend (price < MA)
    if 'BEARISH' in pattern_type:
        return current_price < ma_value
    
    return True
