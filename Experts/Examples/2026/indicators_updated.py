"""
Technical Indicators Module
Calculate RSI, MACD, Moving Averages, ATR, and ADX for backtesting
"""

import pandas as pd
import numpy as np


def calculate_rsi(close_prices, period=14):
    """
    Calculate Relative Strength Index (RSI)
    
    Args:
        close_prices: pandas Series of close prices
        period: RSI period (default 14)
    
    Returns:
        pandas Series with RSI values
    """
    delta = close_prices.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    
    return rsi


def calculate_macd(close_prices, fast=12, slow=26, signal=9):
    """
    Calculate MACD (Moving Average Convergence Divergence)
    
    Args:
        close_prices: pandas Series of close prices
        fast: Fast EMA period (default 12)
        slow: Slow EMA period (default 26)
        signal: Signal line period (default 9)
    
    Returns:
        tuple: (macd_line, signal_line, histogram)
    """
    ema_fast = close_prices.ewm(span=fast, adjust=False).mean()
    ema_slow = close_prices.ewm(span=slow, adjust=False).mean()
    
    macd_line = ema_fast - ema_slow
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    histogram = macd_line - signal_line
    
    return macd_line, signal_line, histogram


def calculate_ma(close_prices, period, method='SMA'):
    """
    Calculate Moving Average
    
    Args:
        close_prices: pandas Series of close prices
        period: MA period
        method: 'SMA' or 'EMA' (default SMA)
    
    Returns:
        pandas Series with MA values
    """
    if method == 'SMA':
        return close_prices.rolling(window=period).mean()
    elif method == 'EMA':
        return close_prices.ewm(span=period, adjust=False).mean()
    else:
        raise ValueError(f"Unknown MA method: {method}")


def calculate_atr(high, low, close, period=14):
    """
    Calculate Average True Range (ATR)
    
    Args:
        high: pandas Series of high prices
        low: pandas Series of low prices
        close: pandas Series of close prices
        period: ATR period (default 14)
    
    Returns:
        pandas Series with ATR values
    """
    high_low = high - low
    high_close = np.abs(high - close.shift())
    low_close = np.abs(low - close.shift())
    
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()
    
    return atr


def calculate_adx(high, low, close, period=14):
    """
    Calculate Average Directional Index (ADX)
    Measures trend strength (0-100): >25 = strong trend, <20 = weak/sideways
    
    Args:
        high: pandas Series of high prices
        low: pandas Series of low prices
        close: pandas Series of close prices
        period: ADX period (default 14)
    
    Returns:
        pandas Series with ADX values
    """
    # Calculate +DM and -DM
    high_diff = high.diff()
    low_diff = -low.diff()
    
    plus_dm = high_diff.where((high_diff > low_diff) & (high_diff > 0), 0)
    minus_dm = low_diff.where((low_diff > high_diff) & (low_diff > 0), 0)
    
    # Calculate True Range
    high_low = high - low
    high_close = np.abs(high - close.shift())
    low_close = np.abs(low - close.shift())
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    
    # Smooth with Wilder's smoothing (exponential moving average)
    atr = tr.ewm(alpha=1/period, adjust=False).mean()
    plus_di = 100 * (plus_dm.ewm(alpha=1/period, adjust=False).mean() / atr)
    minus_di = 100 * (minus_dm.ewm(alpha=1/period, adjust=False).mean() / atr)
    
    # Calculate DX and ADX
    dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di)
    adx = dx.ewm(alpha=1/period, adjust=False).mean()
    
    return adx


def calculate_momentum(close_prices, period=12):
    """
    Calculate Rate of Change (ROC) Momentum Indicator
    
    ROC measures the percentage change in price over a specified period.
    Positive ROC indicates bullish momentum, negative indicates bearish.
    
    Args:
        close_prices: pandas Series of close prices
        period: Lookback period for ROC calculation (default 12)
    
    Returns:
        pandas Series with ROC values (percentage scale)
    
    Formula:
        ROC = ((Close[t] - Close[t-period]) / Close[t-period]) * 100
    
    Interpretation:
        ROC > 0: Bullish momentum (price rising)
        ROC < 0: Bearish momentum (price falling)
        Stronger momentum: ROC further from zero
    
    Standard Thresholds:
        Bullish confirm: ROC > 0.2
        Bearish confirm: ROC < -0.2
        Strong bullish: ROC > 1.0
        Strong bearish: ROC < -1.0
    """
    # Calculate price change from n periods ago
    price_change = close_prices.diff(period)
    
    # Calculate ROC as percentage
    roc = (price_change / close_prices.shift(period)) * 100
    
    return roc


def add_all_indicators(df, rsi_period=14, macd_fast=12, macd_slow=26, macd_signal=9,
                       ma50_period=50, ma200_period=200, atr_period=14, adx_period=14):
    """
    Add all indicators to the dataframe
    
    Args:
        df: DataFrame with OHLC data
        rsi_period: RSI period
        macd_fast: MACD fast period
        macd_slow: MACD slow period
        macd_signal: MACD signal period
        ma50_period: MA50 period
        ma200_period: MA200 period
        atr_period: ATR period
        adx_period: ADX period
    
    Returns:
        DataFrame with added indicator columns
    """
    # RSI
    df['RSI'] = calculate_rsi(df['close'], period=rsi_period)
    
    # MACD
    macd_line, signal_line, histogram = calculate_macd(
        df['close'], fast=macd_fast, slow=macd_slow, signal=macd_signal
    )
    df['MACD'] = macd_line
    df['MACD_Signal'] = signal_line
    df['MACD_Histogram'] = histogram
    
    # Moving Averages
    df['MA50'] = calculate_ma(df['close'], period=ma50_period, method='SMA')
    df['MA200'] = calculate_ma(df['close'], period=ma200_period, method='SMA')
    
    # ATR
    df['ATR'] = calculate_atr(df['high'], df['low'], df['close'], period=atr_period)
    
    # ADX
    df['ADX'] = calculate_adx(df['high'], df['low'], df['close'], period=adx_period)
    
    # ROC Momentum
    df['ROC_12'] = calculate_momentum(df['close'], period=12)
    df['ROC_14'] = calculate_momentum(df['close'], period=14)
    
    return df
