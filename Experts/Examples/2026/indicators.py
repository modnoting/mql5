"""
Technical Indicators Module
Calculate RSI, MACD, Moving Averages, and ATR for backtesting
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


def add_all_indicators(df, rsi_period=14, macd_fast=12, macd_slow=26, macd_signal=9,
                       ma50_period=50, ma200_period=200, atr_period=14):
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
    
    return df
