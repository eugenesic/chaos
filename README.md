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
- Killzone entry filter that trades only the enabled Asia, London, and New York sessions by default

## Entry conditions

By default the EA now uses a less passive balanced configuration. A buy entry requires these filters to be true on the last closed bar:

1. H1 Alligator is aligned upward: Lips > Teeth > Jaw.
2. The D1 trend Alligator agrees only when `InpRequireTrendAlligator=true`; otherwise it is logged diagnostically and can be used during optimization.
3. The M15 confirmation Alligator agrees only when `InpRequireConfirmAlligator=true`.
4. H1 close is above all three Alligator lines by default (`InpRequirePriceBeyondAlligator=true`); set it to `false` during aggressive tests to require only a close above the Teeth line.
5. H1 Alligator Lips/Jaw gap is at least `InpMinAlligatorGapPts`.
6. A confirmed bullish fractal exists within `InpFractalLookbackBars`; set `InpRequireFractalOutsideAlligator=true` to require its price above the H1 Teeth/Lips area.
7. H1 AO is rising by default; set `InpRequireAOSign=true` to also require AO above zero, or `InpRequireAOSlope=false` to disable the slope check.
8. M15 AO is rising only when `InpRequireConfirmAO=true`.
9. The optional MFI filter passes when `InpUseMfiFilter=true`.
10. Risk sizing can build a valid order plan, spread is not above `InpMaxSpreadPoints`, the enabled killzones/time filters allow the bar, and the position manager allows exposure (`InpMaxOpenPositions=1`, no pyramiding by default).

A sell entry mirrors the buy logic:

1. H1 Alligator is aligned downward: Lips < Teeth < Jaw; D1 and M15 Alligator filters are configurable with `InpRequireTrendAlligator` and `InpRequireConfirmAlligator`.
2. H1 close is below all three Alligator lines by default, or only below the Teeth line when `InpRequirePriceBeyondAlligator=false`.
3. H1 Alligator gap is wide enough.
4. A confirmed bearish fractal exists within the lookback; its placement below the H1 Teeth/Lips area is required only when `InpRequireFractalOutsideAlligator=true`.
5. H1 AO is falling by default; AO below zero is required only when `InpRequireAOSign=true`.
6. M15 AO is falling only when `InpRequireConfirmAO=true`.
7. MFI, risk, spread, killzone/time, and exposure checks pass.


## Position management

The EA now includes a dedicated position-management layer to reduce repeated blocked order attempts from clusters of same-direction signals:

- `InpMaxOpenPositions=1` limits the EA to one open position on the symbol/magic number by default.
- `InpAllowPyramiding=false` skips fresh same-direction signals instead of sending orders that the terminal or broker will reject.
- `InpMaxSameDirectionPositions=1` provides an explicit cap if pyramiding is enabled for optimization.
- `InpCloseOnOppositeSignal=true` closes an existing opposite EA position when a new Plan A signal appears.
- `InpReverseOnOppositeSignal=false` makes that opposite-signal close a flat exit by default; set it to `true` to close and immediately attempt a reverse entry.
- `InpUseAlligatorTrailingStop=true` trails stops toward the Alligator Teeth with `InpTrailingBufferPoints`.
- `InpUseKillzones=true` limits new entries to the enabled Asia (`InpAsiaStartHour`-`InpAsiaEndHour`), London (`InpLondonStartHour`-`InpLondonEndHour`), and New York (`InpNewYorkStartHour`-`InpNewYorkEndHour`) killzones. Hours are evaluated in broker/server time and use an inclusive start with an exclusive end.
- `InpUseTimeFilter`, `InpTradeStartHour`, `InpTradeEndHour`, `InpAvoidFridayAfterHour`, and `InpFridayCutoffHour` can further avoid unwanted sessions or late-Friday entries.

## CSV decision log

When `InpEnableCsvLog=true`, the EA writes `InpLogFileName` (`BillWilliamsChaosEA_trades.csv` by default). With `InpLogEveryDecision=true`, every evaluated H1 bar is recorded, not only successful entries.

Important CSV events:

- `NO_ENTRY`: no trade was opened because at least one mandatory buy and sell filter failed. The `diagnostics` column shows every condition and whether it passed.
- `ENTRY_SIGNAL`: all strategy filters passed and an order plan was created.
- `ORDER_SENT`: the MetaTrader trade request was sent successfully.
- `ORDER_BLOCKED`: a signal existed, but execution was blocked by risk sizing, spread, exposure limits, time filter, opposite-signal close without reverse, or terminal order-send failure.
- `DEAL_EXECUTED`: an actual MetaTrader deal was added for this EA magic number, including entry/exit type, volume, price, profit, order, and position identifiers.

The CSV includes the event reason, full diagnostics, AO values, H1/D1 Alligator values, fractal price/time/shift, and direction.

## Why trades can be very rare

The original classic setup was intentionally restrictive and could produce only a few trades in multi-year H1 tests. The current defaults keep the D1 trend filter optional, M15 confirmation optional, and fractals no longer have to sit outside the Alligator, while price must clear all three Alligator lines and AO must slope in the signal direction. If you want the classic behavior, set `InpRequireTrendAlligator=true`, `InpRequirePriceBeyondAlligator=true`, `InpRequireFractalOutsideAlligator=true`, `InpRequireAOSign=true`, and optionally require the confirmation filters.

The most common reasons for too few trades are:

- the D1 trend filter disagrees with otherwise valid H1 signals when `InpRequireTrendAlligator=true`;
- the M15 confirmation filter flips before or after the H1 signal bar when confirmation filters are required;
- the fractal filter remains confirmed 5-bar fractals only, and becomes stricter if `InpRequireFractalOutsideAlligator=true`;
- AO can be configured from slope-only to sign-and-slope H1 confirmation plus optional M15 AO confirmation;
- `InpTradeOnNewBarOnly=true` means checks happen only once per H1 bar by default;
- spread, risk, minimum stop distance, killzone/time filters, or position exposure limits can block execution after a signal.

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
- `InpUseKillzones`, individual killzone toggles, and killzone start/end hours

## Improvement ideas

- Add an ADX or Bollinger Band width filter to avoid flat markets.
- Adapt `InpATRMultiplier` by volatility regime.
- Require breakout beyond the confirming fractal before market entry.
- Add economic news blackout windows around the killzone/session filter.
- Train a lightweight ML classifier on AO slope, Alligator gaps, ATR percentile, and fractal age to reject low-quality signals.

## Adaptive quality modules

The EA now keeps the original Plan A logic intact and adds optional, optimizer-friendly modules. All additions are controlled by inputs and default to disabled where they could reduce trade frequency.

- Adaptive flat filter (`InpUseAdaptiveFlatFilter`) blocks entries only when the Alligator lines are close, ATR is below the flat threshold, and recent range confirms consolidation.
- Trend strength (`InpUseTrendStrengthFilter`) scores Alligator order, line distance, divergence speed, and Lips slope from 0 to 100.
- Higher-timeframe filter (`InpUseHigherTimeframeFilter`, `InpHigherTimeframe`) can require both HTF Alligator direction and HTF AO confirmation.
- Enhanced fractal quality (`InpUseEnhancedFractalFilter`) can require fractals outside the Alligator, after Alligator opening, far enough from a previous fractal, and outside a narrow range.
- ATR volatility filter (`InpUseATRVolatilityFilter`) rejects both low-volatility and excessive-volatility entries.
- Signal scoring (`InpUseSignalScore`) combines weighted filter results into `SignalScore` from 0 to 100 and opens only above `InpMinSignalScore`.
- Killzone quality (`InpUseKillzoneQualityFilter`) remains an additional filter only: it can require minimum ATR, tick volume, and bar activity, but it never creates trades by time alone.
- Trailing stop mode (`InpTrailingMode`) supports off, ATR, Teeth, Fractal, and Hybrid behavior while preserving the existing Alligator trailing toggle.

The CSV log now includes trend strength, ATR in points, Alligator state, SignalScore, and serialized filter parameters so rejected entries can be analyzed without changing the EA code.
