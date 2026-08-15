# Setup Instructions for M&W Pattern Backtester

## ⚠️ Python Installation Required

The backtesting system requires **Python 3.8 or higher** to run. Python is not currently installed on your system.

---

## 📦 Installation Steps

### Option 1: Install Python from Official Website (Recommended)

1. **Download Python**
   - Visit: https://www.python.org/downloads/
   - Download the latest Python 3.x version (3.8 or higher)
   - **Important**: During installation, CHECK the box "Add Python to PATH"

2. **Install Python**
   - Run the installer
   - Select "Install Now" or "Customize Installation"
   - Make sure "Add Python to PATH" is checked
   - Complete the installation

3. **Verify Installation**
   Open PowerShell or Command Prompt and run:
   ```powershell
   python --version
   ```
   You should see something like: `Python 3.11.x`

### Option 2: Install Python from Microsoft Store

1. Open Microsoft Store
2. Search for "Python 3.11" (or latest version)
3. Click "Get" or "Install"
4. After installation, verify with:
   ```powershell
   python --version
   ```

---

## 📚 Install Required Libraries

After installing Python, you need to install the required libraries:

```powershell
# Navigate to the project directory
cd "c:\Users\arsac\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Examples\2026"

# Install required packages
pip install pandas numpy matplotlib
```

**Required packages:**
- `pandas` - Data manipulation and analysis
- `numpy` - Numerical computing
- `matplotlib` - Plotting and visualization

---

## 🚀 Running the Backtest

Once Python and libraries are installed:

```powershell
# Navigate to the directory (if not already there)
cd "c:\Users\arsac\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Examples\2026"

# Run the backtest
python backtest_mw_pattern.py
```

The backtest will:
- ✅ Load CSV data for all 3 months (Feb, Mar, Apr 2026)
- ✅ Resample M1 data to H1 (hourly bars)
- ✅ Add technical indicators (RSI, MACD, MA50, MA200, ATR)
- ✅ Detect M & W patterns with confirmations
- ✅ Simulate trades with proper risk management
- ✅ Generate reports and equity curves

---

## 📊 Expected Output

After running successfully, you'll see:

1. **Console Output**
   - Loading progress
   - Trade entries and exits
   - Summary statistics for each month

2. **Generated Files** (in `reports/` folder)
   - `trade_log_2026_02.csv` - February trade details
   - `trade_log_2026_03.csv` - March trade details
   - `trade_log_2026_04.csv` - April trade details
   - `equity_curve_2026_02.png` - February equity chart
   - `equity_curve_2026_03.png` - March equity chart
   - `equity_curve_2026_04.png` - April equity chart

3. **Final Summary**
   - 3-month comparison table
   - Net profit/loss for each month
   - Win rate and profit factor
   - Maximum drawdown

---

## 🔧 Troubleshooting

### Error: "Python was not found"
- Python is not installed or not in PATH
- Reinstall Python and ensure "Add to PATH" is checked
- Restart PowerShell/Command Prompt after installation

### Error: "No module named 'pandas'"
- Required libraries not installed
- Run: `pip install pandas numpy matplotlib`

### Error: "Permission denied" or "Access denied"
- Run PowerShell as Administrator
- Or install Python in user directory (not Program Files)

### Error: "Cannot find CSV files"
- Ensure CSV files are in the correct location:
  - `DataHistory/DAT_MT_XAUUSD_M1_202602.csv`
  - `DataHistory/DAT_MT_XAUUSD_M1_202603.csv`
  - `DataHistory/DAT_MT_XAUUSD_M1_202604.csv`

---

## 📝 File Structure

```
2026/
├── backtest_mw_pattern.py      # Main backtesting engine
├── mw_pattern_strategy.py      # Pattern detection & strategy logic
├── indicators.py                # Technical indicators
├── SETUP_INSTRUCTIONS.md        # This file
├── DataHistory/
│   ├── DAT_MT_XAUUSD_M1_202602.csv
│   ├── DAT_MT_XAUUSD_M1_202603.csv
│   └── DAT_MT_XAUUSD_M1_202604.csv
└── reports/                     # Generated after running backtest
    ├── trade_log_2026_02.csv
    ├── trade_log_2026_03.csv
    ├── trade_log_2026_04.csv
    ├── equity_curve_2026_02.png
    ├── equity_curve_2026_03.png
    └── equity_curve_2026_04.png
```

---

## ⚙️ Configuration

You can modify backtest parameters in `backtest_mw_pattern.py` by editing the `create_default_config()` function:

**Key Parameters:**
- `initial_balance`: Starting balance (default: $10,000)
- `risk_percent`: Risk per trade (default: 1%)
- `entry_mode`: 'AGGRESSIVE' or 'CONSERVATIVE' (default: CONSERVATIVE)
- `rr_ratio`: Risk:Reward ratio (default: 1.5)
- `use_rsi_divergence`: Enable RSI divergence check (default: True)
- `use_macd_weakness`: Enable MACD weakness check (default: True)
- `use_trend_filter`: Enable MA trend filter (default: True)
- `time_mode`: 'SIMPLE' or 'OPTIMIZED' (default: OPTIMIZED)

---

## 🎯 Next Steps

1. ✅ Install Python 3.8+ (see instructions above)
2. ✅ Install required libraries (`pip install pandas numpy matplotlib`)
3. ✅ Run the backtest (`python backtest_mw_pattern.py`)
4. ✅ Review the generated reports in `reports/` folder
5. ✅ Analyze results and optimize parameters if needed

---

## 📧 Support

If you encounter any issues:
1. Check that Python is properly installed and in PATH
2. Verify all required libraries are installed
3. Ensure CSV data files are in the correct location
4. Check that you have write permissions for the reports folder

---

**Ready to start? Install Python and run the backtest!** 🚀
