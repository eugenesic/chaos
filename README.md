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
- H1 trading timeframe, optional D1 trend filter, and optional M15 confirmation

## Entry conditions

By default the EA now uses a less passive balanced configuration. A buy entry requires these filters to be true on the last closed bar:

1. H1 Alligator is aligned upward: Lips > Teeth > Jaw.
2. The D1 trend Alligator agrees only when `InpRequireTrendAlligator=true`; otherwise it is logged diagnostically and can be used during optimization.
3. The M15 confirmation Alligator agrees only when `InpRequireConfirmAlligator=true`.
4. H1 close is above the Teeth line by default; set `InpRequirePriceBeyondAlligator=true` to require a close above all three Alligator lines.
5. H1 Alligator Lips/Jaw gap is at least `InpMinAlligatorGapPts`.
6. A confirmed bullish fractal exists within `InpFractalLookbackBars`; set `InpRequireFractalOutsideAlligator=true` to require its price above the H1 Teeth/Lips area.
7. H1 AO is rising by default; set `InpRequireAOSign=true` to also require AO above zero, or `InpRequireAOSlope=false` to disable the slope check.
8. M15 AO is rising only when `InpRequireConfirmAO=true`.
9. The optional MFI filter passes when `InpUseMfiFilter=true`.
10. Risk sizing can build a valid order plan, spread is not above `InpMaxSpreadPoints`, and there is no existing same-direction EA position.

A sell entry mirrors the buy logic:

1. H1 Alligator is aligned downward: Lips < Teeth < Jaw; D1 and M15 Alligator filters are configurable with `InpRequireTrendAlligator` and `InpRequireConfirmAlligator`.
2. H1 close is below the Teeth line by default, or below all three Alligator lines when `InpRequirePriceBeyondAlligator=true`.
3. H1 Alligator gap is wide enough.
4. A confirmed bearish fractal exists within the lookback; its placement below the H1 Teeth/Lips area is required only when `InpRequireFractalOutsideAlligator=true`.
5. H1 AO is falling by default; AO below zero is required only when `InpRequireAOSign=true`.
6. M15 AO is falling only when `InpRequireConfirmAO=true`.
7. MFI, risk, spread, and duplicate-position checks pass.

## CSV decision log

When `InpEnableCsvLog=true`, the EA writes `InpLogFileName` (`BillWilliamsChaosEA_trades.csv` by default). With `InpLogEveryDecision=true`, every evaluated H1 bar is recorded, not only successful entries.

Important CSV events:

- `NO_ENTRY`: no trade was opened because at least one mandatory buy and sell filter failed. The `diagnostics` column shows every condition and whether it passed.
- `ENTRY_SIGNAL`: all strategy filters passed and an order plan was created.
- `ORDER_SENT`: the MetaTrader trade request was sent successfully.
- `ORDER_BLOCKED`: a signal existed, but execution was blocked by risk sizing, spread, duplicate position, or terminal order-send failure.
- `DEAL_EXECUTED`: an actual MetaTrader deal was added for this EA magic number, including entry/exit type, volume, price, profit, order, and position identifiers.

The CSV includes the event reason, full diagnostics, AO values, H1/D1 Alligator values, fractal price/time/shift, and direction.

## Why trades can be very rare

The original classic setup was intentionally restrictive and could produce only a few trades in multi-year H1 tests. The current defaults relax the most common blockers: the D1 trend filter is optional, M15 confirmation remains optional, price only has to clear the Teeth line, fractals no longer have to sit outside the Alligator, and AO only has to slope in the signal direction. If you want the classic behavior, set `InpRequireTrendAlligator=true`, `InpRequirePriceBeyondAlligator=true`, `InpRequireFractalOutsideAlligator=true`, `InpRequireAOSign=true`, and optionally require the confirmation filters.

The most common reasons for too few trades are:

- the D1 trend filter disagrees with otherwise valid H1 signals when `InpRequireTrendAlligator=true`;
- the M15 confirmation filter flips before or after the H1 signal bar when confirmation filters are required;
- the fractal filter remains confirmed 5-bar fractals only, and becomes stricter if `InpRequireFractalOutsideAlligator=true`;
- AO can be configured from slope-only to sign-and-slope H1 confirmation plus optional M15 AO confirmation;
- `InpTradeOnNewBarOnly=true` means checks happen only once per H1 bar by default;
- spread, risk, minimum stop distance, or an existing same-direction position can block execution after a signal.

Use the CSV `NO_ENTRY` rows to count which exact filter fails most often for the tested symbol and period.

## Optimization parameters

Recommended inputs to optimize in the MT5 Strategy Tester:

- `InpRiskPerTradePercent`
- `InpMinAlligatorGapPts`
- `InpRequireTrendAlligator`
- `InpRequirePriceBeyondAlligator`
- `InpRequireFractalOutsideAlligator`
- `InpRequireAOSign` and `InpRequireAOSlope`
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
