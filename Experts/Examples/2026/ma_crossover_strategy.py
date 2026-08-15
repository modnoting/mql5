"""
MA Crossover Strategy Module
Detect MACD crossover signals with trend filter and ADX confirmation
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from typing import Optional


@dataclass
class SignalInfo:
    """Information about a detected trading signal"""
    signal_type: str  # 'BUY' or 'SELL'
    bar_index: int
    signal_time: pd.Timestamp
    macd_value: float
    histogram_value: float
    trend_direction: str  # 'UPTREND', 'DOWNTREND', 'SIDEWAYS'
    adx_value: float
    signal_strength: float  # 0-1 score


def detect_macd_crossover(df, i, config):
    """
    Detect MACD histogram crossing zero line
    
    Args:
        df: DataFrame with MACD indicators
        i: Current bar index
        config: Configuration dict with thresholds
    
    Returns:
        'BUY', 'SELL', or None
    """
    if i < 1:
        return None
    
    # Need valid MACD histogram for current and previous bars
    if pd.isna(df.loc[i, 'MACD_Histogram']) or pd.isna(df.loc[i-1, 'MACD_Histogram']):
        return None
    
    current_hist = df.loc[i, 'MACD_Histogram']
    prev_hist = df.loc[i-1, 'MACD_Histogram']
    
    # Bullish crossover: histogram crosses above zero
    if prev_hist <= 0 and current_hist > 0:
        return 'BUY'
    
    # Bearish crossover: histogram crosses below zero
    if prev_hist >= 0 and current_hist < 0:
        return 'SELL'
    
    return None


def check_trend_filter(df, i, signal_type):
    """
    Validate signal aligns with MA50/MA200 trend
    
    Args:
        df: DataFrame with MA indicators
        i: Current bar index
        signal_type: 'BUY' or 'SELL'
    
    Returns:
        True if trend aligned, False otherwise
    """
    # Need valid MA values
    if pd.isna(df.loc[i, 'MA50']) or pd.isna(df.loc[i, 'MA200']):
        return False
    
    ma50 = df.loc[i, 'MA50']
    ma200 = df.loc[i, 'MA200']
    
    # BUY signal requires uptrend (MA50 > MA200)
    if signal_type == 'BUY':
        return ma50 > ma200
    
    # SELL signal requires downtrend (MA50 < MA200)
    if signal_type == 'SELL':
        return ma50 < ma200
    
    return False


def check_adx_filter(df, i, min_adx=20):
    """
    Verify ADX indicates trending market
    
    Args:
        df: DataFrame with ADX indicator
        i: Current bar index
        min_adx: Minimum ADX threshold (default 20)
    
    Returns:
        True if ADX >= min_adx, False otherwise
    """
    if pd.isna(df.loc[i, 'ADX']):
        return False
    
    adx = df.loc[i, 'ADX']
    return adx >= min_adx


def check_rsi_zone_filter(df, i, rsi_min=30, rsi_max=70):
    """
    Verify RSI is in neutral zone (not oversold/overbought)
    
    Avoids trading in extreme conditions:
    - RSI < 30: Oversold (avoid SELL signals)
    - RSI > 70: Overbought (avoid BUY signals)
    - RSI 30-70: Neutral zone (OK to trade)
    
    Args:
        df: DataFrame with RSI indicator
        i: Current bar index
        rsi_min: Minimum RSI threshold (default 30)
        rsi_max: Maximum RSI threshold (default 70)
    
    Returns:
        True if RSI in neutral zone, False otherwise
    """
    if pd.isna(df.loc[i, 'RSI']):
        return False
    
    rsi = df.loc[i, 'RSI']
    return rsi_min <= rsi <= rsi_max


def check_roc_momentum_filter(df, i, signal_type, roc_threshold=0.1):
    """
    Verify momentum (ROC) aligns with signal direction
    
    Confirms signal has momentum support:
    - BUY signal: ROC > +threshold (positive momentum)
    - SELL signal: ROC < -threshold (negative momentum)
    
    Args:
        df: DataFrame with ROC_12 indicator
        i: Current bar index
        signal_type: 'BUY' or 'SELL'
        roc_threshold: Minimum ROC percentage (default 0.1%)
    
    Returns:
        True if momentum aligns, False otherwise
    """
    if pd.isna(df.loc[i, 'ROC_12']):
        return False
    
    roc = df.loc[i, 'ROC_12']
    
    if signal_type == 'BUY':
        # Bullish signal needs positive momentum
        return roc > roc_threshold
    else:  # SELL
        # Bearish signal needs negative momentum
        return roc < -roc_threshold


def get_trend_direction(df, i):
    """
    Determine current trend direction based on MA50/MA200
    
    Args:
        df: DataFrame with MA indicators
        i: Current bar index
    
    Returns:
        'UPTREND', 'DOWNTREND', or 'SIDEWAYS'
    """
    if pd.isna(df.loc[i, 'MA50']) or pd.isna(df.loc[i, 'MA200']):
        return 'SIDEWAYS'
    
    ma50 = df.loc[i, 'MA50']
    ma200 = df.loc[i, 'MA200']
    
    # Calculate percentage difference
    diff_pct = abs((ma50 - ma200) / ma200) * 100
    
    # If MA50 and MA200 too close, consider sideways
    if diff_pct < 0.1:  # Less than 0.1% difference
        return 'SIDEWAYS'
    
    if ma50 > ma200:
        return 'UPTREND'
    else:
        return 'DOWNTREND'


def calculate_signal_strength(df, i, signal_type):
    """
    Calculate signal strength score (0-1) based on multiple factors
    
    Args:
        df: DataFrame with indicators
        i: Current bar index
        signal_type: 'BUY' or 'SELL'
    
    Returns:
        Float score between 0 and 1
    """
    strength = 0.0
    
    # Factor 1: MACD histogram strength (0-0.4 points)
    if not pd.isna(df.loc[i, 'MACD_Histogram']):
        hist_abs = abs(df.loc[i, 'MACD_Histogram'])
        # Normalize: stronger histogram = higher score (cap at 2.0 for XAUUSD)
        hist_score = min(hist_abs / 2.0, 1.0) * 0.4
        strength += hist_score
    
    # Factor 2: ADX strength (0-0.3 points)
    if not pd.isna(df.loc[i, 'ADX']):
        adx = df.loc[i, 'ADX']
        # Normalize: ADX 20-50 scale to 0-1
        adx_score = min((adx - 20) / 30, 1.0) * 0.3
        strength += max(adx_score, 0)
    
    # Factor 3: Distance from MA50 (0-0.3 points)
    if not pd.isna(df.loc[i, 'close']) and not pd.isna(df.loc[i, 'MA50']):
        close = df.loc[i, 'close']
        ma50 = df.loc[i, 'MA50']
        distance_pct = abs((close - ma50) / ma50) * 100
        
        # Prefer signals close to MA50 (better entry point)
        # 0% distance = 0.3 points, 1%+ distance = 0 points
        ma_score = max(0.3 - (distance_pct * 0.3), 0)
        strength += ma_score
    
    return min(strength, 1.0)  # Cap at 1.0


def detect_signal(df, i, config):
    """
    Main function to detect and validate trading signal
    
    Args:
        df: DataFrame with all indicators
        i: Current bar index
        config: Configuration dict
    
    Returns:
        SignalInfo object if valid signal found, None otherwise
    """
    # Step 1: Detect MACD crossover
    signal_type = detect_macd_crossover(df, i, config)
    if signal_type is None:
        return None
    
    # Step 2: Check trend filter (MA50/MA200)
    if config.get('use_trend_filter', True):
        if not check_trend_filter(df, i, signal_type):
            return None
    
    # Step 3: Check ADX filter
    if config.get('use_adx_filter', True):
        min_adx = config.get('min_adx', 20)
        if not check_adx_filter(df, i, min_adx):
            return None
    
    # Step 4: Check RSI zone filter (optional)
    if config.get('use_rsi_filter', False):
        rsi_min = config.get('rsi_min', 30)
        rsi_max = config.get('rsi_max', 70)
        if not check_rsi_zone_filter(df, i, rsi_min, rsi_max):
            return None
    
    # Step 5: Check ROC momentum filter (optional)
    if config.get('use_roc_filter', False):
        roc_threshold = config.get('roc_threshold', 0.1)
        if not check_roc_momentum_filter(df, i, signal_type, roc_threshold):
            return None
    
    # Signal passed all filters, create SignalInfo
    signal_info = SignalInfo(
        signal_type=signal_type,
        bar_index=i,
        signal_time=df.loc[i, 'datetime'],
        macd_value=df.loc[i, 'MACD'],
        histogram_value=df.loc[i, 'MACD_Histogram'],
        trend_direction=get_trend_direction(df, i),
        adx_value=df.loc[i, 'ADX'] if not pd.isna(df.loc[i, 'ADX']) else 0,
        signal_strength=calculate_signal_strength(df, i, signal_type)
    )
    
    return signal_info
