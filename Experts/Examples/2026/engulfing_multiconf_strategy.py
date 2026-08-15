"""
Engulfing + Multi-Confirmation Strategy
Detects engulfing patterns with 4-filter confirmation:
1. MA Trend Filter (MA50 vs MA200)
2. ADX Volatility Filter (trending market)
3. ROC Momentum Filter (directional momentum)
4. RSI Zone Filter (optimal entry zones)
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from price_action_patterns import detect_bullish_engulfing, detect_bearish_engulfing


@dataclass
class ConfirmationResult:
    """Result of multi-confirmation check"""
    signal_valid: bool  # True if all filters pass
    signal_type: str  # 'BUY' or 'SELL'
    signal_strength: float  # 0-1 score based on filters
    filters_passed: list  # List of passed filter names
    filters_failed: list  # List of failed filter names
    filter_count: str  # e.g., '4/4' or '3/4'
    
    # Individual filter details
    ma_trend: str = ''
    adx_value: float = 0
    roc_value: float = 0
    rsi_value: float = 0


def check_ma_trend_filter(df, i, signal_type, config):
    """
    Filter 1: MA Trend Confirmation
    
    Bullish signal requires MA50 > MA200 (uptrend)
    Bearish signal requires MA50 < MA200 (downtrend)
    
    Args:
        df: DataFrame with MA50 and MA200 columns
        i: Current bar index
        signal_type: 'BULLISH_ENGULFING' or 'BEARISH_ENGULFING'
        config: Configuration dictionary
    
    Returns:
        tuple: (passed: bool, description: str)
    """
    if i >= len(df):
        return False, 'Index out of range'
    
    ma50 = df.iloc[i]['MA50']
    ma200 = df.iloc[i]['MA200']
    
    if pd.isna(ma50) or pd.isna(ma200):
        return False, f'MA values not available (MA50:{ma50:.2f}, MA200:{ma200:.2f})'
    
    if signal_type == 'BULLISH_ENGULFING':
        if ma50 > ma200:
            return True, f'UPTREND (MA50:{ma50:.2f} > MA200:{ma200:.2f})'
        else:
            return False, f'NO UPTREND (MA50:{ma50:.2f} <= MA200:{ma200:.2f})'
    
    elif signal_type == 'BEARISH_ENGULFING':
        if ma50 < ma200:
            return True, f'DOWNTREND (MA50:{ma50:.2f} < MA200:{ma200:.2f})'
        else:
            return False, f'NO DOWNTREND (MA50:{ma50:.2f} >= MA200:{ma200:.2f})'
    
    return False, 'Invalid signal type'


def check_adx_filter(df, i, config):
    """
    Filter 2: ADX Volatility Confirmation
    
    ADX must be between min and max thresholds
    Min threshold: Market is trending (not sideways)
    Max threshold: Market not overextended
    
    Args:
        df: DataFrame with ADX column
        i: Current bar index
        config: Configuration dictionary with adx_min and adx_max
    
    Returns:
        tuple: (passed: bool, description: str)
    """
    if i >= len(df):
        return False, 'Index out of range'
    
    adx = df.iloc[i]['ADX']
    adx_min = config.get('adx_min', 20)
    adx_max = config.get('adx_max', 40)
    
    if pd.isna(adx):
        return False, f'ADX not available'
    
    if adx_min <= adx <= adx_max:
        return True, f'ADX TRENDING ({adx:.1f} in {adx_min}-{adx_max})'
    else:
        if adx < adx_min:
            return False, f'ADX TOO LOW ({adx:.1f} < {adx_min}, sideways market)'
        else:
            return False, f'ADX TOO HIGH ({adx:.1f} > {adx_max}, overextended)'


def check_roc_momentum_filter(df, i, signal_type, config):
    """
    Filter 3: ROC Momentum Confirmation
    
    Bullish signal requires positive momentum (ROC > threshold)
    Bearish signal requires negative momentum (ROC < threshold)
    
    Args:
        df: DataFrame with ROC_12 column
        i: Current bar index
        signal_type: 'BULLISH_ENGULFING' or 'BEARISH_ENGULFING'
        config: Configuration dictionary with roc_bullish and roc_bearish thresholds
    
    Returns:
        tuple: (passed: bool, description: str)
    """
    if i >= len(df):
        return False, 'Index out of range'
    
    roc = df.iloc[i]['ROC_12']
    roc_bull_thresh = config.get('roc_bullish', 0.2)
    roc_bear_thresh = config.get('roc_bearish', -0.2)
    
    if pd.isna(roc):
        return False, f'ROC not available'
    
    if signal_type == 'BULLISH_ENGULFING':
        if roc > roc_bull_thresh:
            return True, f'BULLISH MOMENTUM (ROC:{roc:.2f}% > {roc_bull_thresh}%)'
        else:
            return False, f'WEAK MOMENTUM (ROC:{roc:.2f}% <= {roc_bull_thresh}%)'
    
    elif signal_type == 'BEARISH_ENGULFING':
        if roc < roc_bear_thresh:
            return True, f'BEARISH MOMENTUM (ROC:{roc:.2f}% < {roc_bear_thresh}%)'
        else:
            return False, f'WEAK MOMENTUM (ROC:{roc:.2f}% >= {roc_bear_thresh}%)'
    
    return False, 'Invalid signal type'


def check_rsi_zone_filter(df, i, config):
    """
    Filter 4: RSI Zone Confirmation
    
    RSI must be in neutral zone (not oversold/overbought)
    Optimal entry: RSI between 30-70
    
    Args:
        df: DataFrame with RSI column
        i: Current bar index
        config: Configuration dictionary with rsi_min and rsi_max
    
    Returns:
        tuple: (passed: bool, description: str)
    """
    if i >= len(df):
        return False, 'Index out of range'
    
    rsi = df.iloc[i]['RSI']
    rsi_min = config.get('rsi_min', 30)
    rsi_max = config.get('rsi_max', 70)
    
    if pd.isna(rsi):
        return False, f'RSI not available'
    
    if rsi_min <= rsi <= rsi_max:
        return True, f'RSI NEUTRAL ZONE ({rsi:.1f} in {rsi_min}-{rsi_max})'
    else:
        if rsi < rsi_min:
            return False, f'RSI OVERSOLD ({rsi:.1f} < {rsi_min})'
        else:
            return False, f'RSI OVERBOUGHT ({rsi:.1f} > {rsi_max})'


def check_multi_confirmations(df, i, pattern_type, config):
    """
    Main multi-confirmation logic
    
    Checks all 4 filters and returns confirmation result.
    Signal is valid only if ALL filters pass (strict AND logic).
    
    Args:
        df: DataFrame with OHLC + indicators
        i: Current bar index
        pattern_type: 'BULLISH_ENGULFING' or 'BEARISH_ENGULFING'
        config: Configuration dictionary
    
    Returns:
        ConfirmationResult with signal validity and filter details
    """
    filters_passed = []
    filters_failed = []
    filter_count = 0
    
    # Determine signal type
    signal_type = 'BUY' if pattern_type == 'BULLISH_ENGULFING' else 'SELL'
    
    # FILTER 1: MA TREND
    passed, desc = check_ma_trend_filter(df, i, pattern_type, config)
    if passed:
        filters_passed.append(desc)
        filter_count += 1
    else:
        filters_failed.append(desc)
    ma_trend_desc = desc
    
    # FILTER 2: ADX VOLATILITY
    passed, desc = check_adx_filter(df, i, config)
    adx_val = df.iloc[i]['ADX'] if i < len(df) and 'ADX' in df.columns else 0
    if passed:
        filters_passed.append(desc)
        filter_count += 1
    else:
        filters_failed.append(desc)
    
    # FILTER 3: ROC MOMENTUM
    passed, desc = check_roc_momentum_filter(df, i, pattern_type, config)
    roc_val = df.iloc[i]['ROC_12'] if i < len(df) and 'ROC_12' in df.columns else 0
    if passed:
        filters_passed.append(desc)
        filter_count += 1
    else:
        filters_failed.append(desc)
    
    # FILTER 4: RSI ZONE
    passed, desc = check_rsi_zone_filter(df, i, config)
    rsi_val = df.iloc[i]['RSI'] if i < len(df) and 'RSI' in df.columns else 0
    if passed:
        filters_passed.append(desc)
        filter_count += 1
    else:
        filters_failed.append(desc)
    
    # Calculate signal strength (0-1)
    signal_strength = filter_count / 4.0
    
    # Signal is valid only if ALL 4 filters pass (strict AND logic)
    signal_valid = (filter_count == 4)
    
    # Alternative: Use majority vote (3/4 filters) - uncomment if needed
    # min_filters = config.get('min_signal_strength', 0.75)
    # signal_valid = (signal_strength >= min_filters)
    
    return ConfirmationResult(
        signal_valid=signal_valid,
        signal_type=signal_type,
        signal_strength=signal_strength,
        filters_passed=filters_passed,
        filters_failed=filters_failed,
        filter_count=f'{filter_count}/4',
        ma_trend=ma_trend_desc,
        adx_value=adx_val,
        roc_value=roc_val,
        rsi_value=rsi_val
    )


def detect_engulfing_with_confirmation(df, i, config):
    """
    Detect engulfing pattern and validate with multi-confirmation
    
    Args:
        df: DataFrame with OHLC + indicators
        i: Current bar index
        config: Configuration dictionary
    
    Returns:
        tuple: (pattern_info, confirmation_result) or (None, None) if no signal
    """
    pip_size = config.get('pip_size', 0.1)
    
    # Detect bullish engulfing
    bullish_pattern = detect_bullish_engulfing(
        df, i,
        min_body_ratio=config.get('engulfing_min_body_ratio', 0.7),
        min_prev_body_pips=config.get('engulfing_min_prev_body_pips', 10),
        pip_size=pip_size
    )
    
    if bullish_pattern is not None:
        # Check confirmations
        confirmation = check_multi_confirmations(df, i, 'BULLISH_ENGULFING', config)
        if confirmation.signal_valid:
            return bullish_pattern, confirmation
    
    # Detect bearish engulfing
    bearish_pattern = detect_bearish_engulfing(
        df, i,
        min_body_ratio=config.get('engulfing_min_body_ratio', 0.7),
        min_prev_body_pips=config.get('engulfing_min_prev_body_pips', 10),
        pip_size=pip_size
    )
    
    if bearish_pattern is not None:
        # Check confirmations
        confirmation = check_multi_confirmations(df, i, 'BEARISH_ENGULFING', config)
        if confirmation.signal_valid:
            return bearish_pattern, confirmation
    
    return None, None
