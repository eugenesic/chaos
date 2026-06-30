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

## Entry conditions

A buy entry requires all of these filters to be true on the last closed bar:

1. H1 Alligator is aligned upward: Lips > Teeth > Jaw.
2. D1 trend Alligator is aligned upward.
3. M15 confirmation Alligator is aligned upward.
4. H1 close is above all three Alligator lines.
5. H1 Alligator Lips/Jaw gap is at least `InpMinAlligatorGapPts`.
6. A confirmed bullish fractal exists within `InpFractalLookbackBars` and its price is above the H1 Teeth/Lips area.
7. H1 AO is positive and rising.
8. M15 AO is rising.
9. The optional MFI filter passes when `InpUseMfiFilter=true`.
10. Risk sizing can build a valid order plan, spread is not above `InpMaxSpreadPoints`, and there is no existing same-direction EA position.

A sell entry mirrors the buy logic:

1. H1, D1, and M15 Alligators are aligned downward: Lips < Teeth < Jaw.
2. H1 close is below all three Alligator lines.
3. H1 Alligator gap is wide enough.
4. A confirmed bearish fractal exists within the lookback and its price is below the H1 Teeth/Lips area.
5. H1 AO is negative and falling.
6. M15 AO is falling.
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

The default setup is intentionally restrictive. A trade is opened only when H1, D1, and M15 trend filters agree, price is on the correct side of the H1 Alligator, AO momentum agrees on H1 and M15, and a confirmed fractal is positioned beyond the Alligator. In a six-year test this can easily reduce the sample to only a few trades, especially on symbols that spend long periods in ranges or have wide spreads.

The most common reasons for too few trades are:

- the D1 trend filter disagrees with otherwise valid H1 signals;
- the M15 confirmation filter flips before or after the H1 signal bar;
- the fractal filter is very strict because the fractal must be confirmed and also be beyond the Teeth/Lips area;
- AO must have both the correct sign and slope on H1, while M15 AO must also confirm;
- `InpTradeOnNewBarOnly=true` means checks happen only once per H1 bar by default;
- spread, risk, minimum stop distance, or an existing same-direction position can block execution after a signal.

Use the CSV `NO_ENTRY` rows to count which exact filter fails most often for the tested symbol and period.

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
