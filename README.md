# Bill Williams Chaos EA for MT5

This repository contains a MetaTrader 5 Expert Advisor implementing a modular Bill Williams Chaos strategy in MQL5.

## Strategy

`BillWilliamsChaosEA.mq5` combines:

- Alligator alignment based on SMA median price lines:
  - Jaw: period 13, shift 8
  - Teeth: period 8, shift 5
  - Lips: period 5, shift 3
- Awesome Oscillator: SMA(5, median price) - SMA(34, median price)
- Confirmed 5-bar fractals
- Optional Market Facilitation Index filter
- ATR/fractal stop-loss selection and reward-risk take-profit
- H1 trading timeframe, D1 trend filter, and M15 confirmation by default

## Optimization parameters

Recommended inputs to optimize in the MT5 Strategy Tester:

- `InpRiskPerTradePercent`
- `InpMinAlligatorGapPts`
- `InpFractalLookbackBars`
- `InpUseMfiFilter` and `InpMfiAveragePeriod`
- `InpATRPeriod` and `InpATRMultiplier`
- `InpRewardRisk`
- `InpStopBufferPoints` and `InpMinStopPoints`
- Timeframe inputs for symbol-specific behavior

## Improvement ideas

- Add an ADX or Bollinger Band width filter to avoid flat markets.
- Adapt `InpATRMultiplier` by volatility regime.
- Require breakout beyond the confirming fractal before market entry.
- Add session/time-of-day filters and economic news blackout windows.
- Train a lightweight ML classifier on AO slope, Alligator gaps, ATR percentile, and fractal age to reject low-quality signals.
