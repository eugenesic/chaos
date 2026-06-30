//+------------------------------------------------------------------+
//| BillWilliamsChaosEA.mq5                                          |
//| Modular Bill Williams Chaos strategy for MetaTrader 5            |
//| Components: Alligator + Fractals + Awesome Oscillator + MFI/ATR  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Bill Williams Chaos EA: Alligator, Fractals, AO, optional MFI, ATR/RR risk management."

#include <Trade/Trade.mqh>

//----------------------------- Inputs ------------------------------
input group "General"
input ulong           InpMagicNumber          = 26063001;
input ENUM_TIMEFRAMES InpTradeTimeframe       = PERIOD_H1;
input ENUM_TIMEFRAMES InpTrendTimeframe       = PERIOD_D1;
input ENUM_TIMEFRAMES InpConfirmTimeframe     = PERIOD_M15;
input bool            InpTradeOnNewBarOnly    = true;
input int             InpMaxSpreadPoints      = 30;
input int             InpSlippagePoints       = 10;
input bool            InpUseTimeFilter        = false;
input int             InpTradeStartHour       = 7;
input int             InpTradeEndHour         = 20;
input bool            InpUseKillzones         = true;
input bool            InpUseKillzoneQualityFilter = false;
input double          InpKillzoneMinATRPoints = 50.0;
input long            InpKillzoneMinTickVolume = 100;
input double          InpKillzoneMinRangeATRRatio = 0.30;
input bool            InpTradeAsiaKillzone    = true;
input int             InpAsiaStartHour        = 0;
input int             InpAsiaEndHour          = 6;
input bool            InpTradeLondonKillzone  = true;
input int             InpLondonStartHour      = 7;
input int             InpLondonEndHour        = 10;
input bool            InpTradeNewYorkKillzone = true;
input int             InpNewYorkStartHour     = 13;
input int             InpNewYorkEndHour       = 16;
input bool            InpAvoidFridayAfterHour = true;
input int             InpFridayCutoffHour     = 18;

input group "Alligator"
input int             InpJawPeriod            = 13;
input int             InpJawShift             = 8;
input int             InpTeethPeriod          = 8;
input int             InpTeethShift           = 5;
input int             InpLipsPeriod           = 5;
input int             InpLipsShift            = 3;
input int             InpMinAlligatorGapPts   = 5;
input bool            InpRequireConfirmAlligator = false;
input bool            InpRequireTrendAlligator = false;
input bool            InpAllowConfirmAsTrendFallback = true;
input bool            InpRequirePriceBeyondAlligator = true;
input bool            InpRequireFractalOutsideAlligator = false;

input group "Adaptive Filters"
input bool            InpUseAdaptiveFlatFilter = false;
input double          InpFlatMaxAlligatorGapPts = 25.0;
input double          InpFlatMaxATRPoints    = 80.0;
input int             InpFlatConsolidationBars = 12;
input double          InpFlatMaxRangeATRRatio = 1.50;
input bool            InpUseATRVolatilityFilter = false;
input double          InpMinATRPoints        = 40.0;
input double          InpMaxATRPoints        = 400.0;
input bool            InpUseTrendStrengthFilter = false;
input double          InpMinTrendStrength    = 35.0;
input int             InpTrendStrengthLookback = 3;
input double          InpTrendGapFullScorePts = 120.0;
input double          InpTrendDivergenceFullScorePts = 30.0;
input double          InpTrendLipsSlopeFullScorePts = 30.0;
input bool            InpUseHigherTimeframeFilter = false;
input ENUM_TIMEFRAMES InpHigherTimeframe     = PERIOD_H4;
input bool            InpHigherRequireAlligator = true;
input bool            InpHigherRequireAO     = true;
input bool            InpUseEnhancedFractalFilter = false;
input double          InpFractalMinDistancePts = 50.0;
input int             InpFractalNarrowRangeBars = 8;
input double          InpFractalNarrowRangeATRRatio = 1.0;

input group "Awesome Oscillator / Fractals / MFI"
input int             InpAOFastPeriod         = 5;
input int             InpAOSlowPeriod         = 34;
input int             InpFractalLookbackBars  = 80;
input bool            InpRequireConfirmAO     = false;
input bool            InpRequireAOSign        = false;
input bool            InpRequireAOSlope       = true;
input bool            InpUseMfiFilter         = false;
input int             InpMfiAveragePeriod     = 20;

input group "Position Management"
input int             InpMaxOpenPositions     = 1;
input bool            InpAllowPyramiding      = false;
input int             InpMaxSameDirectionPositions = 1;
input bool            InpCloseOnOppositeSignal = true;
input bool            InpReverseOnOppositeSignal = false;
input bool            InpUseAlligatorTrailingStop = true;
input int             InpTrailingMode      = 2;
input int             InpTrailingBufferPoints = 20;
input double          InpTrailingATRMultiplier = 2.0;

input group "Risk Management"
input double          InpRiskPerTradePercent  = 1.0;
input bool            InpUseFractalStop       = true;
input int             InpATRPeriod            = 14;
input double          InpATRMultiplier        = 2.0;
input double          InpRewardRisk           = 2.0;
input int             InpStopBufferPoints     = 20;
input int             InpMinStopPoints        = 100;

input group "Logging"
input bool            InpEnableCsvLog         = true;
input string          InpLogFileName          = "BillWilliamsChaosEA_trades.csv";
input bool            InpLogEveryDecision     = true;

input group "Signal Score"
input bool            InpUseSignalScore       = false;
input double          InpMinSignalScore       = 70.0;
input double          InpWeightTrendStrength  = 20.0;
input double          InpWeightFlatFilter     = 15.0;
input double          InpWeightHigherTimeframe = 15.0;
input double          InpWeightFractalQuality = 20.0;
input double          InpWeightATRFilter      = 15.0;
input double          InpWeightKillzoneQuality = 15.0;

//----------------------------- Types -------------------------------
enum ENUM_SIGNAL_DIRECTION { SIGNAL_NONE = 0, SIGNAL_BUY = 1, SIGNAL_SELL = -1 };

enum ENUM_TRAILING_MODE
{
   TRAIL_OFF = 0,
   TRAIL_ATR,
   TRAIL_TEETH,
   TRAIL_FRACTAL,
   TRAIL_HYBRID
};

enum ENUM_EXIT_REASON
{
   EXIT_NONE = 0,
   EXIT_ALLIGATOR_CROSS,
   EXIT_OPPOSITE_FRACTAL,
   EXIT_AO_SIGN_CHANGE
};

struct AlligatorState
{
   double jaw;
   double teeth;
   double lips;
   bool   aligned_up;
   bool   aligned_down;
   bool   price_above;
   bool   price_below;
   bool   price_above_teeth;
   bool   price_below_teeth;
   double gap_points;
};

struct FractalSignal
{
   bool     found;
   datetime time;
   double   price;
   int      shift;
};

struct SignalContext
{
   ENUM_SIGNAL_DIRECTION direction;
   string reason;
   AlligatorState main_alligator;
   AlligatorState trend_alligator;
   double ao_current;
   double ao_previous;
   FractalSignal fractal;
   bool mfi_ok;
   double atr;
   double trend_strength;
   double signal_score;
   string alligator_state;
   string filter_params;
   string diagnostics;
};

//--------------------------- Indicator Engine ----------------------
class CIndicatorEngine
{
private:
   string m_symbol;

   bool CopyTfRates(const ENUM_TIMEFRAMES tf, const int bars, MqlRates &rates[]) const
   {
      ArraySetAsSeries(rates, true);
      return (CopyRates(m_symbol, tf, 0, bars, rates) >= bars);
   }

   double MedianSma(const ENUM_TIMEFRAMES tf, const int period, const int shift) const
   {
      MqlRates rates[];
      if(period <= 0 || shift < 0 || !CopyTfRates(tf, shift + period + 5, rates))
         return EMPTY_VALUE;

      double sum = 0.0;
      for(int i = shift; i < shift + period; i++)
         sum += (rates[i].high + rates[i].low) * 0.5;
      return sum / (double)period;
   }

public:
   void Init(const string symbol) { m_symbol = symbol; }

   AlligatorState GetAlligator(const ENUM_TIMEFRAMES tf, const int signal_bar_shift) const
   {
      AlligatorState state;
      ZeroMemory(state);

      state.jaw   = MedianSma(tf, InpJawPeriod,   signal_bar_shift + InpJawShift);
      state.teeth = MedianSma(tf, InpTeethPeriod, signal_bar_shift + InpTeethShift);
      state.lips  = MedianSma(tf, InpLipsPeriod,  signal_bar_shift + InpLipsShift);

      MqlRates rates[];
      if(!CopyTfRates(tf, signal_bar_shift + 2, rates))
         return state;

      const double close_price = rates[signal_bar_shift].close;
      state.aligned_up = (state.lips > state.teeth && state.teeth > state.jaw);
      state.aligned_down = (state.lips < state.teeth && state.teeth < state.jaw);
      state.price_above = (close_price > state.lips && close_price > state.teeth && close_price > state.jaw);
      state.price_below = (close_price < state.lips && close_price < state.teeth && close_price < state.jaw);
      state.price_above_teeth = (close_price > state.teeth);
      state.price_below_teeth = (close_price < state.teeth);
      state.gap_points = MathAbs(state.lips - state.jaw) / _Point;
      return state;
   }

   double GetAO(const ENUM_TIMEFRAMES tf, const int shift) const
   {
      const double fast = MedianSma(tf, InpAOFastPeriod, shift);
      const double slow = MedianSma(tf, InpAOSlowPeriod, shift);
      if(fast == EMPTY_VALUE || slow == EMPTY_VALUE)
         return EMPTY_VALUE;
      return fast - slow;
   }

   FractalSignal FindFractal(const ENUM_TIMEFRAMES tf, const bool bullish, const int max_lookback) const
   {
      FractalSignal out;
      out.found = false;
      out.time = 0;
      out.price = 0.0;
      out.shift = 0;
      MqlRates rates[];
      const int bars_needed = MathMax(max_lookback + 10, 20);
      if(!CopyTfRates(tf, bars_needed, rates))
         return out;

      // A 5-bar fractal centered at shift N is confirmed only after bars N-1 and N-2 close.
      for(int shift = 3; shift <= max_lookback; shift++)
      {
         bool ok = true;
         if(bullish)
         {
            const double v = rates[shift].low;
            ok = (v < rates[shift-1].low && v < rates[shift-2].low && v < rates[shift+1].low && v < rates[shift+2].low);
            if(ok) { out.found = true; out.time = rates[shift].time; out.price = v; out.shift = shift; return out; }
         }
         else
         {
            const double v = rates[shift].high;
            ok = (v > rates[shift-1].high && v > rates[shift-2].high && v > rates[shift+1].high && v > rates[shift+2].high);
            if(ok) { out.found = true; out.time = rates[shift].time; out.price = v; out.shift = shift; return out; }
         }
      }
      return out;
   }


   FractalSignal FindPreviousFractal(const ENUM_TIMEFRAMES tf, const bool bullish, const int min_shift, const int max_lookback) const
   {
      FractalSignal out;
      out.found = false;
      out.time = 0;
      out.price = 0.0;
      out.shift = 0;
      MqlRates rates[];
      const int bars_needed = MathMax(max_lookback + 10, 20);
      if(!CopyTfRates(tf, bars_needed, rates))
         return out;
      for(int shift = MathMax(3, min_shift); shift <= max_lookback; shift++)
      {
         if(bullish)
         {
            const double v = rates[shift].low;
            if(v < rates[shift-1].low && v < rates[shift-2].low && v < rates[shift+1].low && v < rates[shift+2].low)
            { out.found = true; out.time = rates[shift].time; out.price = v; out.shift = shift; return out; }
         }
         else
         {
            const double v = rates[shift].high;
            if(v > rates[shift-1].high && v > rates[shift-2].high && v > rates[shift+1].high && v > rates[shift+2].high)
            { out.found = true; out.time = rates[shift].time; out.price = v; out.shift = shift; return out; }
         }
      }
      return out;
   }

   bool MfiFilterOk(const ENUM_TIMEFRAMES tf, const bool buy) const
   {
      if(!InpUseMfiFilter)
         return true;

      MqlRates rates[];
      if(!CopyTfRates(tf, InpMfiAveragePeriod + 5, rates))
         return false;

      double avg = 0.0;
      for(int i = 2; i < InpMfiAveragePeriod + 2; i++)
      {
         const long vol = (rates[i].tick_volume > 0 ? rates[i].tick_volume : 1);
         avg += (rates[i].high - rates[i].low) / (double)vol;
      }
      avg /= (double)InpMfiAveragePeriod;

      const double current = (rates[1].high - rates[1].low) / (double)(rates[1].tick_volume > 0 ? rates[1].tick_volume : 1);
      const double previous = (rates[2].high - rates[2].low) / (double)(rates[2].tick_volume > 0 ? rates[2].tick_volume : 1);
      return (current > avg || (buy ? current > previous : current < previous));
   }

   double GetATR(const ENUM_TIMEFRAMES tf, const int shift) const
   {
      MqlRates rates[];
      if(!CopyTfRates(tf, shift + InpATRPeriod + 2, rates))
         return 0.0;
      double sum = 0.0;
      for(int i = shift; i < shift + InpATRPeriod; i++)
      {
         const double prev_close = rates[i+1].close;
         const double tr = MathMax(rates[i].high - rates[i].low,
                          MathMax(MathAbs(rates[i].high - prev_close), MathAbs(rates[i].low - prev_close)));
         sum += tr;
      }
      return sum / (double)InpATRPeriod;
   }

   double GetRangePoints(const ENUM_TIMEFRAMES tf, const int shift, const int bars) const
   {
      MqlRates rates[];
      if(bars <= 0 || !CopyTfRates(tf, shift + bars + 2, rates))
         return 0.0;
      double hi = rates[shift].high;
      double lo = rates[shift].low;
      for(int i = shift; i < shift + bars; i++)
      {
         hi = MathMax(hi, rates[i].high);
         lo = MathMin(lo, rates[i].low);
      }
      return (hi - lo) / _Point;
   }

   long GetTickVolume(const ENUM_TIMEFRAMES tf, const int shift) const
   {
      MqlRates rates[];
      if(!CopyTfRates(tf, shift + 2, rates))
         return 0;
      return rates[shift].tick_volume;
   }

   double GetClose(const ENUM_TIMEFRAMES tf, const int shift) const
   {
      MqlRates rates[];
      if(!CopyTfRates(tf, shift + 2, rates))
         return 0.0;
      return rates[shift].close;
   }
};

string BoolText(const bool value)
{
   return (value ? "yes" : "no");
}

bool IsHourInRange(const int hour, const int start_hour, const int end_hour)
{
   return (start_hour <= end_hour
           ? (hour >= start_hour && hour < end_hour)
           : (hour >= start_hour || hour < end_hour));
}

bool IsTradingTimeAllowed(string &reason)
{
   reason = "";
   if(!InpUseTimeFilter && !InpUseKillzones && !InpAvoidFridayAfterHour)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(InpUseTimeFilter)
   {
      const bool in_session = IsHourInRange(now.hour, InpTradeStartHour, InpTradeEndHour);
      if(!in_session)
      {
         reason = StringFormat("time filter blocked entry: hour=%d session=%02d-%02d", now.hour, InpTradeStartHour, InpTradeEndHour);
         return false;
      }
   }
   if(InpUseKillzones)
   {
      const bool in_asia = (InpTradeAsiaKillzone && IsHourInRange(now.hour, InpAsiaStartHour, InpAsiaEndHour));
      const bool in_london = (InpTradeLondonKillzone && IsHourInRange(now.hour, InpLondonStartHour, InpLondonEndHour));
      const bool in_new_york = (InpTradeNewYorkKillzone && IsHourInRange(now.hour, InpNewYorkStartHour, InpNewYorkEndHour));
      if(!in_asia && !in_london && !in_new_york)
      {
         reason = StringFormat("killzone filter blocked entry: hour=%d Asia=%s(%02d-%02d) London=%s(%02d-%02d) NewYork=%s(%02d-%02d)",
                               now.hour,
                               BoolText(InpTradeAsiaKillzone), InpAsiaStartHour, InpAsiaEndHour,
                               BoolText(InpTradeLondonKillzone), InpLondonStartHour, InpLondonEndHour,
                               BoolText(InpTradeNewYorkKillzone), InpNewYorkStartHour, InpNewYorkEndHour);
         return false;
      }
   }
   if(InpAvoidFridayAfterHour && now.day_of_week == 5 && now.hour >= InpFridayCutoffHour)
   {
      reason = StringFormat("friday cutoff blocked entry: hour=%d cutoff=%02d", now.hour, InpFridayCutoffHour);
      return false;
   }
   return true;
}


//-------------------------- Quality Modules ------------------------
double ClampScore(const double value)
{
   return MathMax(0.0, MathMin(100.0, value));
}

class CTrendStrengthEvaluator
{
private:
   CIndicatorEngine *m_ind;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }

   double Strength(const ENUM_TIMEFRAMES tf, const ENUM_SIGNAL_DIRECTION direction, string &details) const
   {
      const AlligatorState cur = m_ind.GetAlligator(tf, 1);
      const AlligatorState prev = m_ind.GetAlligator(tf, 1 + MathMax(1, InpTrendStrengthLookback));
      const double order_score = ((direction == SIGNAL_BUY && cur.aligned_up) || (direction == SIGNAL_SELL && cur.aligned_down) ? 25.0 : 0.0);
      const double gap_score = MathMin(25.0, 25.0 * cur.gap_points / MathMax(1.0, InpTrendGapFullScorePts));
      const double divergence = (cur.gap_points - prev.gap_points);
      const double divergence_score = MathMin(25.0, 25.0 * MathMax(0.0, divergence) / MathMax(1.0, InpTrendDivergenceFullScorePts));
      const double lips_slope_pts = (direction == SIGNAL_BUY ? cur.lips - prev.lips : prev.lips - cur.lips) / _Point;
      const double slope_score = MathMin(25.0, 25.0 * MathMax(0.0, lips_slope_pts) / MathMax(1.0, InpTrendLipsSlopeFullScorePts));
      const double score = ClampScore(order_score + gap_score + divergence_score + slope_score);
      details = StringFormat("trend_strength=%.1f order=%.1f gap=%.1f divergence_pts=%.1f lips_slope_pts=%.1f", score, order_score, cur.gap_points, divergence, lips_slope_pts);
      return score;
   }
};

class CFlatMarketFilter
{
private:
   CIndicatorEngine *m_ind;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }
   bool Allows(const AlligatorState &alligator, const double atr, string &details) const
   {
      const double atr_pts = atr / _Point;
      const double range_pts = m_ind.GetRangePoints(InpTradeTimeframe, 1, InpFlatConsolidationBars);
      const bool close_lines = (alligator.gap_points <= InpFlatMaxAlligatorGapPts);
      const bool low_atr = (atr_pts <= InpFlatMaxATRPoints);
      const bool consolidated = (range_pts <= atr_pts * InpFlatMaxRangeATRRatio);
      details = StringFormat("flat_filter enabled=%s close_lines=%s(gap=%.1f max=%.1f) low_atr=%s(atr=%.1f max=%.1f) consolidation=%s(range=%.1f ratio_max=%.2f)", BoolText(InpUseAdaptiveFlatFilter), BoolText(close_lines), alligator.gap_points, InpFlatMaxAlligatorGapPts, BoolText(low_atr), atr_pts, InpFlatMaxATRPoints, BoolText(consolidated), range_pts, InpFlatMaxRangeATRRatio);
      return (!InpUseAdaptiveFlatFilter || !(close_lines && low_atr && consolidated));
   }
};

class CHigherTimeframeFilter
{
private:
   CIndicatorEngine *m_ind;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }
   bool Allows(const ENUM_SIGNAL_DIRECTION direction, string &details) const
   {
      const AlligatorState htf = m_ind.GetAlligator(InpHigherTimeframe, 1);
      const double ao = m_ind.GetAO(InpHigherTimeframe, 1);
      const double ao_prev = m_ind.GetAO(InpHigherTimeframe, 2);
      const bool alligator_ok = (!InpHigherRequireAlligator || (direction == SIGNAL_BUY ? htf.aligned_up : htf.aligned_down));
      const bool ao_ok = (!InpHigherRequireAO || (direction == SIGNAL_BUY ? (ao > 0.0 && ao >= ao_prev) : (ao < 0.0 && ao <= ao_prev)));
      details = StringFormat("htf_filter enabled=%s tf=%s alligator_ok=%s ao_ok=%s ao=%s prev=%s", BoolText(InpUseHigherTimeframeFilter), EnumToString(InpHigherTimeframe), BoolText(alligator_ok), BoolText(ao_ok), DoubleToString(ao, _Digits), DoubleToString(ao_prev, _Digits));
      return (!InpUseHigherTimeframeFilter || (alligator_ok && ao_ok));
   }
};

class CFractalQualityFilter
{
private:
   CIndicatorEngine *m_ind;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }
   bool Allows(const ENUM_SIGNAL_DIRECTION direction, const FractalSignal &fractal, const AlligatorState &alligator, const double atr, string &details) const
   {
      if(!fractal.found)
      {
         details = "fractal_quality found=no";
         return false;
      }
      const bool outside = (direction == SIGNAL_BUY ? fractal.price > MathMax(alligator.lips, alligator.teeth) : fractal.price < MathMin(alligator.lips, alligator.teeth));
      const bool after_open = (alligator.gap_points >= InpMinAlligatorGapPts);
      const FractalSignal prev = m_ind.FindPreviousFractal(InpTradeTimeframe, direction == SIGNAL_BUY, fractal.shift + 1, MathMin(InpFractalLookbackBars, fractal.shift + 40));
      const double prev_dist = (prev.found ? MathAbs(fractal.price - prev.price) / _Point : InpFractalMinDistancePts);
      const bool enough_distance = (prev_dist >= InpFractalMinDistancePts);
      const double range_pts = m_ind.GetRangePoints(InpTradeTimeframe, 1, InpFractalNarrowRangeBars);
      const double atr_pts = atr / _Point;
      const bool narrow = (range_pts <= atr_pts * InpFractalNarrowRangeATRRatio);
      details = StringFormat("fractal_quality enabled=%s outside=%s after_open=%s prev_dist=%.1f min=%.1f narrow=%s range=%.1f", BoolText(InpUseEnhancedFractalFilter), BoolText(outside), BoolText(after_open), prev_dist, InpFractalMinDistancePts, BoolText(narrow), range_pts);
      return (!InpUseEnhancedFractalFilter || (outside && after_open && enough_distance && !narrow));
   }
};

class CSignalQualityScorer
{
public:
   double Score(const bool flat_ok, const bool htf_ok, const bool fractal_ok, const bool atr_ok, const bool killzone_ok, const double trend_strength, string &details) const
   {
      const double total = InpWeightTrendStrength + InpWeightFlatFilter + InpWeightHigherTimeframe + InpWeightFractalQuality + InpWeightATRFilter + InpWeightKillzoneQuality;
      if(total <= 0.0) { details = "signal_score disabled_weights"; return 100.0; }
      double raw = 0.0;
      raw += InpWeightTrendStrength * ClampScore(trend_strength) / 100.0;
      raw += InpWeightFlatFilter * (flat_ok ? 1.0 : 0.0);
      raw += InpWeightHigherTimeframe * (htf_ok ? 1.0 : 0.0);
      raw += InpWeightFractalQuality * (fractal_ok ? 1.0 : 0.0);
      raw += InpWeightATRFilter * (atr_ok ? 1.0 : 0.0);
      raw += InpWeightKillzoneQuality * (killzone_ok ? 1.0 : 0.0);
      const double score = ClampScore(100.0 * raw / total);
      details = StringFormat("SignalScore=%.1f min=%.1f weights trend=%.1f flat=%.1f htf=%.1f fractal=%.1f atr=%.1f killzone=%.1f", score, InpMinSignalScore, InpWeightTrendStrength, InpWeightFlatFilter, InpWeightHigherTimeframe, InpWeightFractalQuality, InpWeightATRFilter, InpWeightKillzoneQuality);
      return score;
   }
};

bool KillzoneQualityAllows(CIndicatorEngine *ind, string &details)
{
   const double atr_pts = ind.GetATR(InpTradeTimeframe, 1) / _Point;
   const long volume = ind.GetTickVolume(InpTradeTimeframe, 1);
   const double range_pts = ind.GetRangePoints(InpTradeTimeframe, 1, 1);
   const bool ok = (!InpUseKillzoneQualityFilter || (atr_pts >= InpKillzoneMinATRPoints && volume >= InpKillzoneMinTickVolume && range_pts >= atr_pts * InpKillzoneMinRangeATRRatio));
   details = StringFormat("killzone_quality enabled=%s atr=%.1f min=%.1f volume=%d min=%d range=%.1f activity_ratio=%.2f ok=%s", BoolText(InpUseKillzoneQualityFilter), atr_pts, InpKillzoneMinATRPoints, volume, InpKillzoneMinTickVolume, range_pts, InpKillzoneMinRangeATRRatio, BoolText(ok));
   return ok;
}

//----------------------------- Logger ------------------------------
class CBacktestLogger
{
private:
   int m_handle;
public:
   CBacktestLogger() : m_handle(INVALID_HANDLE) {}

   void Init()
   {
      if(!InpEnableCsvLog)
         return;
      m_handle = FileOpen(InpLogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ';');
      if(m_handle == INVALID_HANDLE)
      {
         Print("CSV log open failed: ", GetLastError());
         return;
      }
      if(FileSize(m_handle) == 0)
         FileWrite(m_handle, "time", "symbol", "event", "direction", "reason", "diagnostics", "ao", "ao_previous", "jaw", "teeth", "lips", "trend_jaw", "trend_teeth", "trend_lips", "fractal_price", "fractal_time", "fractal_shift", "trend_strength", "atr", "alligator_state", "signal_score", "filter_params");
      FileSeek(m_handle, 0, SEEK_END);
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
   }


   void LogDeal(const ulong deal_ticket) const
   {
      if(m_handle == INVALID_HANDLE || !HistoryDealSelect(deal_ticket))
         return;
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != (long)InpMagicNumber)
         return;

      const ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         return;

      const ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      const string direction = (deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL");
      const string reason = StringFormat("Executed deal: entry=%s volume=%s price=%s profit=%s comment=%s",
                                         EnumToString(deal_entry),
                                         DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_VOLUME), 2),
                                         DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PRICE), _Digits),
                                         DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PROFIT), 2),
                                         HistoryDealGetString(deal_ticket, DEAL_COMMENT));
      const string diagnostics = StringFormat("deal=%I64u order=%I64u position=%I64u",
                                              deal_ticket,
                                              HistoryDealGetInteger(deal_ticket, DEAL_ORDER),
                                              HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID));
      FileWrite(m_handle, TimeToString((datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME), TIME_DATE|TIME_SECONDS),
                _Symbol, "DEAL_EXECUTED", direction, reason, diagnostics, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "");
      FileFlush(m_handle);
   }

   void LogSignal(const string event_name, const SignalContext &ctx) const
   {
      const string dir = (ctx.direction == SIGNAL_BUY ? "BUY" : (ctx.direction == SIGNAL_SELL ? "SELL" : "NONE"));
      const string msg = StringFormat("%s %s %s | AO=%.6f prev=%.6f | Alligator J=%.5f T=%.5f L=%.5f | fractal=%.5f %s",
                                      event_name, _Symbol, dir, ctx.ao_current, ctx.ao_previous,
                                      ctx.main_alligator.jaw, ctx.main_alligator.teeth, ctx.main_alligator.lips,
                                      ctx.fractal.price, TimeToString(ctx.fractal.time));
      Print(msg, " | ", ctx.reason);
      if(m_handle != INVALID_HANDLE)
      {
         FileWrite(m_handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), _Symbol, event_name, dir,
                   ctx.reason, ctx.diagnostics, DoubleToString(ctx.ao_current, _Digits), DoubleToString(ctx.ao_previous, _Digits),
                   DoubleToString(ctx.main_alligator.jaw, _Digits), DoubleToString(ctx.main_alligator.teeth, _Digits),
                   DoubleToString(ctx.main_alligator.lips, _Digits), DoubleToString(ctx.trend_alligator.jaw, _Digits),
                   DoubleToString(ctx.trend_alligator.teeth, _Digits), DoubleToString(ctx.trend_alligator.lips, _Digits),
                   DoubleToString(ctx.fractal.price, _Digits), TimeToString(ctx.fractal.time, TIME_DATE|TIME_SECONDS), ctx.fractal.shift,
                   DoubleToString(ctx.trend_strength, 1), DoubleToString(ctx.atr / _Point, 1), ctx.alligator_state, DoubleToString(ctx.signal_score, 1), ctx.filter_params);
         FileFlush(m_handle);
      }
   }
};

//--------------------------- Signal Engine -------------------------
class CSignalEngine
{
private:
   CIndicatorEngine *m_ind;
   CTrendStrengthEvaluator m_trend_strength;
   CFlatMarketFilter m_flat_filter;
   CHigherTimeframeFilter m_htf_filter;
   CFractalQualityFilter m_fractal_quality;
   CSignalQualityScorer m_scorer;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; m_trend_strength.Init(ind); m_flat_filter.Init(ind); m_htf_filter.Init(ind); m_fractal_quality.Init(ind); }

   SignalContext BuildSignal()
   {
      SignalContext ctx;
      ctx.direction = SIGNAL_NONE;
      ctx.reason = "";
      ctx.ao_current = 0.0;
      ctx.ao_previous = 0.0;
      ctx.fractal.found = false;
      ctx.fractal.time = 0;
      ctx.fractal.price = 0.0;
      ctx.fractal.shift = 0;
      ctx.mfi_ok = false;
      ctx.atr = 0.0;
      ctx.trend_strength = 0.0;
      ctx.signal_score = 0.0;
      ctx.alligator_state = "";
      ctx.filter_params = "";
      ctx.diagnostics = "";
      ctx.main_alligator = m_ind.GetAlligator(InpTradeTimeframe, 1);
      ctx.trend_alligator = m_ind.GetAlligator(InpTrendTimeframe, 1);
      ctx.ao_current = m_ind.GetAO(InpTradeTimeframe, 1);
      ctx.ao_previous = m_ind.GetAO(InpTradeTimeframe, 2);

      const FractalSignal bull = m_ind.FindFractal(InpTradeTimeframe, true, InpFractalLookbackBars);
      const FractalSignal bear = m_ind.FindFractal(InpTradeTimeframe, false, InpFractalLookbackBars);
      const AlligatorState confirm = m_ind.GetAlligator(InpConfirmTimeframe, 1);
      const double confirm_ao = m_ind.GetAO(InpConfirmTimeframe, 1);
      const double confirm_ao_prev = m_ind.GetAO(InpConfirmTimeframe, 2);

      const bool buy_mfi_ok = m_ind.MfiFilterOk(InpTradeTimeframe, true);
      const bool sell_mfi_ok = m_ind.MfiFilterOk(InpTradeTimeframe, false);
      const bool buy_trend_ok = (!InpRequireTrendAlligator || ctx.trend_alligator.aligned_up || (InpAllowConfirmAsTrendFallback && confirm.aligned_up));
      const bool sell_trend_ok = (!InpRequireTrendAlligator || ctx.trend_alligator.aligned_down || (InpAllowConfirmAsTrendFallback && confirm.aligned_down));
      const bool buy_price_ok = (InpRequirePriceBeyondAlligator ? ctx.main_alligator.price_above : ctx.main_alligator.price_above_teeth);
      const bool sell_price_ok = (InpRequirePriceBeyondAlligator ? ctx.main_alligator.price_below : ctx.main_alligator.price_below_teeth);
      const bool buy_fractal_position_ok = (!InpRequireFractalOutsideAlligator || bull.price > MathMax(ctx.main_alligator.teeth, ctx.main_alligator.lips));
      const bool sell_fractal_position_ok = (!InpRequireFractalOutsideAlligator || bear.price < MathMin(ctx.main_alligator.teeth, ctx.main_alligator.lips));
      const bool buy_fractal_ok = (bull.found && buy_fractal_position_ok);
      const bool sell_fractal_ok = (bear.found && sell_fractal_position_ok);
      const bool gap_ok = (ctx.main_alligator.gap_points >= InpMinAlligatorGapPts);
      const bool buy_confirm_alligator_ok = (!InpRequireConfirmAlligator || confirm.aligned_up);
      const bool sell_confirm_alligator_ok = (!InpRequireConfirmAlligator || confirm.aligned_down);
      const bool buy_confirm_ao_ok = (!InpRequireConfirmAO || confirm_ao > confirm_ao_prev);
      const bool sell_confirm_ao_ok = (!InpRequireConfirmAO || confirm_ao < confirm_ao_prev);
      const bool buy_ao_sign_ok = (!InpRequireAOSign || ctx.ao_current > 0.0);
      const bool sell_ao_sign_ok = (!InpRequireAOSign || ctx.ao_current < 0.0);
      const bool buy_ao_slope_ok = (!InpRequireAOSlope || ctx.ao_current > ctx.ao_previous);
      const bool sell_ao_slope_ok = (!InpRequireAOSlope || ctx.ao_current < ctx.ao_previous);
      const bool buy_ao_ok = (buy_ao_sign_ok && buy_ao_slope_ok && buy_confirm_ao_ok);
      const bool sell_ao_ok = (sell_ao_sign_ok && sell_ao_slope_ok && sell_confirm_ao_ok);
      ctx.atr = m_ind.GetATR(InpTradeTimeframe, 1);
      const double atr_pts = ctx.atr / _Point;
      const bool atr_filter_ok = (!InpUseATRVolatilityFilter || (atr_pts >= InpMinATRPoints && atr_pts <= InpMaxATRPoints));
      string flat_details = "", htf_buy_details = "", htf_sell_details = "", fractal_buy_details = "", fractal_sell_details = "", score_details = "", trend_buy_details = "", trend_sell_details = "", killzone_quality_details = "";
      const bool flat_ok = m_flat_filter.Allows(ctx.main_alligator, ctx.atr, flat_details);
      const bool htf_buy_ok = m_htf_filter.Allows(SIGNAL_BUY, htf_buy_details);
      const bool htf_sell_ok = m_htf_filter.Allows(SIGNAL_SELL, htf_sell_details);
      const bool buy_fractal_quality_ok = m_fractal_quality.Allows(SIGNAL_BUY, bull, ctx.main_alligator, ctx.atr, fractal_buy_details);
      const bool sell_fractal_quality_ok = m_fractal_quality.Allows(SIGNAL_SELL, bear, ctx.main_alligator, ctx.atr, fractal_sell_details);
      const bool killzone_quality_ok = KillzoneQualityAllows(m_ind, killzone_quality_details);
      const double buy_trend_strength = m_trend_strength.Strength(InpTradeTimeframe, SIGNAL_BUY, trend_buy_details);
      const double sell_trend_strength = m_trend_strength.Strength(InpTradeTimeframe, SIGNAL_SELL, trend_sell_details);
      const bool buy_trend_strength_ok = (!InpUseTrendStrengthFilter || buy_trend_strength >= InpMinTrendStrength);
      const bool sell_trend_strength_ok = (!InpUseTrendStrengthFilter || sell_trend_strength >= InpMinTrendStrength);
      const double buy_score = m_scorer.Score(flat_ok, htf_buy_ok, buy_fractal_quality_ok, atr_filter_ok, killzone_quality_ok, buy_trend_strength, score_details);
      const string buy_score_details = score_details;
      const double sell_score = m_scorer.Score(flat_ok, htf_sell_ok, sell_fractal_quality_ok, atr_filter_ok, killzone_quality_ok, sell_trend_strength, score_details);
      const bool buy_score_ok = (!InpUseSignalScore || buy_score >= InpMinSignalScore);
      const bool sell_score_ok = (!InpUseSignalScore || sell_score >= InpMinSignalScore);
      ctx.alligator_state = StringFormat("main_up=%s main_down=%s gap=%.1f price_above=%s price_below=%s", BoolText(ctx.main_alligator.aligned_up), BoolText(ctx.main_alligator.aligned_down), ctx.main_alligator.gap_points, BoolText(ctx.main_alligator.price_above), BoolText(ctx.main_alligator.price_below));
      ctx.filter_params = StringFormat("ATR=%.1f min=%.1f max=%.1f | %s | %s | BUY %s | SELL %s | BUY %s | SELL %s | %s | BUY %s | SELL %s", atr_pts, InpMinATRPoints, InpMaxATRPoints, flat_details, killzone_quality_details, htf_buy_details, htf_sell_details, fractal_buy_details, fractal_sell_details, trend_buy_details, trend_sell_details, buy_score_details, score_details);

      ctx.diagnostics = StringFormat("BUY checks: main_up=%s trend_up=%s(trend_required=%s trend_ok=%s) confirm_up=%s(confirm_required=%s confirm_ok=%s) price_ok=%s(price_above_all=%s above_teeth=%s require_all=%s) gap_ok=%s(%.1f/%d) fractal_ok=%s(found=%s price=%s shift=%d) ao_ok=%s(ao=%s prev=%s require_sign=%s sign_ok=%s require_slope=%s slope_ok=%s confirm_required=%s confirm_ao=%s confirm_prev=%s confirm_ok=%s) mfi_ok=%s | SELL checks: main_down=%s trend_down=%s(trend_required=%s trend_ok=%s) confirm_down=%s(confirm_required=%s confirm_ok=%s) price_ok=%s(price_below_all=%s below_teeth=%s require_all=%s) gap_ok=%s fractal_ok=%s(found=%s price=%s shift=%d) ao_ok=%s(require_sign=%s sign_ok=%s require_slope=%s slope_ok=%s confirm_required=%s confirm_ok=%s) mfi_ok=%s",
                                     BoolText(ctx.main_alligator.aligned_up), BoolText(ctx.trend_alligator.aligned_up), BoolText(InpRequireTrendAlligator), BoolText(buy_trend_ok), BoolText(confirm.aligned_up),
                                     BoolText(InpRequireConfirmAlligator), BoolText(buy_confirm_alligator_ok),
                                     BoolText(buy_price_ok), BoolText(ctx.main_alligator.price_above), BoolText(ctx.main_alligator.price_above_teeth), BoolText(InpRequirePriceBeyondAlligator), BoolText(gap_ok), ctx.main_alligator.gap_points, InpMinAlligatorGapPts,
                                     BoolText(buy_fractal_ok), BoolText(bull.found), DoubleToString(bull.price, _Digits), bull.shift,
                                     BoolText(buy_ao_ok), DoubleToString(ctx.ao_current, _Digits), DoubleToString(ctx.ao_previous, _Digits),
                                     BoolText(InpRequireAOSign), BoolText(buy_ao_sign_ok), BoolText(InpRequireAOSlope), BoolText(buy_ao_slope_ok),
                                     BoolText(InpRequireConfirmAO), DoubleToString(confirm_ao, _Digits), DoubleToString(confirm_ao_prev, _Digits),
                                     BoolText(buy_confirm_ao_ok), BoolText(buy_mfi_ok),
                                     BoolText(ctx.main_alligator.aligned_down), BoolText(ctx.trend_alligator.aligned_down), BoolText(InpRequireTrendAlligator), BoolText(sell_trend_ok), BoolText(confirm.aligned_down),
                                     BoolText(InpRequireConfirmAlligator), BoolText(sell_confirm_alligator_ok),
                                     BoolText(sell_price_ok), BoolText(ctx.main_alligator.price_below), BoolText(ctx.main_alligator.price_below_teeth), BoolText(InpRequirePriceBeyondAlligator), BoolText(gap_ok), BoolText(sell_fractal_ok), BoolText(bear.found),
                                     DoubleToString(bear.price, _Digits), bear.shift, BoolText(sell_ao_ok),
                                     BoolText(InpRequireAOSign), BoolText(sell_ao_sign_ok), BoolText(InpRequireAOSlope), BoolText(sell_ao_slope_ok),
                                     BoolText(InpRequireConfirmAO), BoolText(sell_confirm_ao_ok), BoolText(sell_mfi_ok));
      ctx.diagnostics += StringFormat(" | Adaptive filters: flat_ok=%s atr_ok=%s htf_buy_ok=%s htf_sell_ok=%s fractal_quality_buy=%s fractal_quality_sell=%s killzone_quality_ok=%s trend_strength_buy=%.1f(ok=%s) trend_strength_sell=%.1f(ok=%s) score_buy=%.1f(ok=%s) score_sell=%.1f(ok=%s) | %s",
                                      BoolText(flat_ok), BoolText(atr_filter_ok), BoolText(htf_buy_ok), BoolText(htf_sell_ok), BoolText(buy_fractal_quality_ok), BoolText(sell_fractal_quality_ok), BoolText(killzone_quality_ok),
                                      buy_trend_strength, BoolText(buy_trend_strength_ok), sell_trend_strength, BoolText(sell_trend_strength_ok), buy_score, BoolText(buy_score_ok), sell_score, BoolText(sell_score_ok), ctx.filter_params);

      if(ctx.main_alligator.aligned_up && buy_trend_ok && buy_confirm_alligator_ok &&
         buy_price_ok && gap_ok && buy_fractal_ok && buy_ao_ok && buy_mfi_ok &&
         flat_ok && atr_filter_ok && htf_buy_ok && buy_fractal_quality_ok && killzone_quality_ok && buy_trend_strength_ok && buy_score_ok)
      {
         ctx.direction = SIGNAL_BUY;
         ctx.fractal = bull;
         ctx.mfi_ok = true;
         ctx.trend_strength = buy_trend_strength;
         ctx.signal_score = buy_score;
         ctx.reason = "Plan A BUY: trade Alligator up; trend filter configurable; confirm Alligator optional; price beyond configured Alligator threshold; bullish fractal accepted by configured placement rule; AO sign/slope filters configurable; confirm AO optional; MFI filter ok";
      }
      else if(ctx.main_alligator.aligned_down && sell_trend_ok && sell_confirm_alligator_ok &&
              sell_price_ok && gap_ok && sell_fractal_ok && sell_ao_ok && sell_mfi_ok &&
              flat_ok && atr_filter_ok && htf_sell_ok && sell_fractal_quality_ok && killzone_quality_ok && sell_trend_strength_ok && sell_score_ok)
      {
         ctx.direction = SIGNAL_SELL;
         ctx.fractal = bear;
         ctx.mfi_ok = true;
         ctx.trend_strength = sell_trend_strength;
         ctx.signal_score = sell_score;
         ctx.reason = "Plan A SELL: trade Alligator down; trend filter configurable; confirm Alligator optional; price beyond configured Alligator threshold; bearish fractal accepted by configured placement rule; AO sign/slope filters configurable; confirm AO optional; MFI filter ok";
      }
      if(ctx.direction == SIGNAL_NONE)
         ctx.reason = StringFormat("No entry: mandatory or adaptive filters failed. ATR=%.1f trend_buy=%.1f trend_sell=%.1f score_buy=%.1f score_sell=%.1f. See diagnostics for exact refusal reasons.", atr_pts, buy_trend_strength, sell_trend_strength, buy_score, sell_score);
      return ctx;
   }

   ENUM_EXIT_REASON ExitReason(const ENUM_POSITION_TYPE type)
   {
      const AlligatorState cur = m_ind.GetAlligator(InpTradeTimeframe, 1);
      const double ao = m_ind.GetAO(InpTradeTimeframe, 1);
      if(type == POSITION_TYPE_BUY)
      {
         if(cur.lips < cur.teeth) return EXIT_ALLIGATOR_CROSS;
         if(m_ind.FindFractal(InpTradeTimeframe, false, 10).found) return EXIT_OPPOSITE_FRACTAL;
         if(ao < 0.0) return EXIT_AO_SIGN_CHANGE;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(cur.lips > cur.teeth) return EXIT_ALLIGATOR_CROSS;
         if(m_ind.FindFractal(InpTradeTimeframe, true, 10).found) return EXIT_OPPOSITE_FRACTAL;
         if(ao > 0.0) return EXIT_AO_SIGN_CHANGE;
      }
      return EXIT_NONE;
   }
};

//---------------------------- Risk Manager -------------------------
class CRiskManager
{
private:
   CIndicatorEngine *m_ind;

   double NormalizeVolume(const double lots) const
   {
      const double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      const double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double normalized = MathFloor(lots / step) * step;
      normalized = MathMax(min_lot, MathMin(max_lot, normalized));
      return normalized;
   }

public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }

   bool BuildOrderPlan(const ENUM_SIGNAL_DIRECTION direction, const FractalSignal &fractal,
                       double &volume, double &sl, double &tp)
   {
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double entry = (direction == SIGNAL_BUY ? ask : bid);
      const double atr = m_ind.GetATR(InpTradeTimeframe, 1);
      const double atr_stop = atr * InpATRMultiplier;
      const double min_stop = MathMax((double)InpMinStopPoints * _Point, (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point);

      if(direction == SIGNAL_BUY)
      {
         const double fractal_stop = (fractal.found ? entry - (fractal.price - InpStopBufferPoints * _Point) : 0.0);
         const double distance = MathMax(min_stop, InpUseFractalStop && fractal_stop > 0.0 ? MathMax(fractal_stop, atr_stop) : atr_stop);
         sl = entry - distance;
         tp = entry + distance * InpRewardRisk;
      }
      else if(direction == SIGNAL_SELL)
      {
         const double fractal_stop = (fractal.found ? (fractal.price + InpStopBufferPoints * _Point) - entry : 0.0);
         const double distance = MathMax(min_stop, InpUseFractalStop && fractal_stop > 0.0 ? MathMax(fractal_stop, atr_stop) : atr_stop);
         sl = entry + distance;
         tp = entry - distance * InpRewardRisk;
      }
      else
         return false;

      const double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPerTradePercent / 100.0;
      const double stop_money_per_lot = MathAbs(entry - sl) / tick_size * tick_value;
      if(stop_money_per_lot <= 0.0)
         return false;

      volume = NormalizeVolume(risk_money / stop_money_per_lot);
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);
      return (volume > 0.0);
   }
};

//-------------------------- Execution Engine -----------------------
class CExecutionEngine
{
private:
   CTrade m_trade;

public:
   void Init()
   {
      m_trade.SetExpertMagicNumber(InpMagicNumber);
      m_trade.SetDeviationInPoints(InpSlippagePoints);
   }

   bool IsOwnPositionSelected() const
   {
      return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
              PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber);
   }

   int CountPositions(const ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE) const
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOwnPositionSelected())
            continue;
         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(direction == SIGNAL_NONE ||
            (direction == SIGNAL_BUY && type == POSITION_TYPE_BUY) ||
            (direction == SIGNAL_SELL && type == POSITION_TYPE_SELL))
            count++;
      }
      return count;
   }

   bool HasPositionDirection(const ENUM_SIGNAL_DIRECTION direction) const
   {
      return (CountPositions(direction) > 0);
   }

   bool HasOppositePosition(const ENUM_SIGNAL_DIRECTION direction) const
   {
      if(direction == SIGNAL_BUY)
         return HasPositionDirection(SIGNAL_SELL);
      if(direction == SIGNAL_SELL)
         return HasPositionDirection(SIGNAL_BUY);
      return false;
   }

   bool ClosePositionsByDirection(const ENUM_SIGNAL_DIRECTION direction)
   {
      bool ok = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOwnPositionSelected())
            continue;
         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if((direction == SIGNAL_BUY && type == POSITION_TYPE_BUY) ||
            (direction == SIGNAL_SELL && type == POSITION_TYPE_SELL))
         {
            Print("Closing position ", ticket, " before opposite signal handling");
            ok = (m_trade.PositionClose(ticket) && ok);
         }
      }
      return ok;
   }

   void CloseOppositePositions(const ENUM_SIGNAL_DIRECTION signal_direction)
   {
      if(!InpCloseOnOppositeSignal)
         return;
      if(signal_direction == SIGNAL_BUY)
         ClosePositionsByDirection(SIGNAL_SELL);
      else if(signal_direction == SIGNAL_SELL)
         ClosePositionsByDirection(SIGNAL_BUY);
   }

   bool ExposureAllowsEntry(const ENUM_SIGNAL_DIRECTION direction, string &reject_reason) const
   {
      reject_reason = "";
      const int total = CountPositions();
      const int same_direction = CountPositions(direction);
      if(!InpAllowPyramiding && same_direction > 0)
      {
         reject_reason = "same-direction position already exists; new order skipped by position manager";
         return false;
      }
      if(same_direction >= InpMaxSameDirectionPositions)
      {
         reject_reason = StringFormat("same-direction position limit reached: current=%d max=%d", same_direction, InpMaxSameDirectionPositions);
         return false;
      }
      if(total >= InpMaxOpenPositions && !(InpReverseOnOppositeSignal && HasOppositePosition(direction)))
      {
         reject_reason = StringFormat("open position limit reached: current=%d max=%d", total, InpMaxOpenPositions);
         return false;
      }
      return true;
   }

   void ApplyAlligatorTrailingStop(const CIndicatorEngine &ind)
   {
      if(!InpUseAlligatorTrailingStop || InpTrailingMode == TRAIL_OFF)
         return;
      const AlligatorState alligator = ind.GetAlligator(InpTradeTimeframe, 1);
      const double atr = ind.GetATR(InpTradeTimeframe, 1);
      const FractalSignal buy_fractal = ind.FindFractal(InpTradeTimeframe, true, InpFractalLookbackBars);
      const FractalSignal sell_fractal = ind.FindFractal(InpTradeTimeframe, false, InpFractalLookbackBars);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOwnPositionSelected())
            continue;
         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         const double current_sl = PositionGetDouble(POSITION_SL);
         const double current_tp = PositionGetDouble(POSITION_TP);
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double teeth_sl = 0.0, atr_sl = 0.0, fractal_sl = 0.0, next_sl = 0.0;
         if(type == POSITION_TYPE_BUY)
         {
            teeth_sl = alligator.teeth - InpTrailingBufferPoints * _Point;
            atr_sl = bid - atr * InpTrailingATRMultiplier;
            fractal_sl = (buy_fractal.found ? buy_fractal.price - InpTrailingBufferPoints * _Point : 0.0);
            if(InpTrailingMode == TRAIL_TEETH) next_sl = teeth_sl;
            else if(InpTrailingMode == TRAIL_ATR) next_sl = atr_sl;
            else if(InpTrailingMode == TRAIL_FRACTAL) next_sl = fractal_sl;
            else if(InpTrailingMode == TRAIL_HYBRID) next_sl = MathMax(teeth_sl, MathMax(atr_sl, fractal_sl));
            next_sl = NormalizeDouble(next_sl, _Digits);
            if(next_sl > 0.0 && next_sl > current_sl && next_sl < bid)
               m_trade.PositionModify(ticket, next_sl, current_tp);
         }
         else if(type == POSITION_TYPE_SELL)
         {
            teeth_sl = alligator.teeth + InpTrailingBufferPoints * _Point;
            atr_sl = ask + atr * InpTrailingATRMultiplier;
            fractal_sl = (sell_fractal.found ? sell_fractal.price + InpTrailingBufferPoints * _Point : 0.0);
            if(InpTrailingMode == TRAIL_TEETH) next_sl = teeth_sl;
            else if(InpTrailingMode == TRAIL_ATR) next_sl = atr_sl;
            else if(InpTrailingMode == TRAIL_FRACTAL) next_sl = fractal_sl;
            else if(InpTrailingMode == TRAIL_HYBRID) next_sl = (fractal_sl > 0.0 ? MathMin(teeth_sl, MathMin(atr_sl, fractal_sl)) : MathMin(teeth_sl, atr_sl));
            next_sl = NormalizeDouble(next_sl, _Digits);
            if(next_sl > ask && (current_sl == 0.0 || next_sl < current_sl))
               m_trade.PositionModify(ticket, next_sl, current_tp);
         }
      }
   }

   void CloseByExitRules(CSignalEngine &signals)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
            continue;

         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         const ENUM_EXIT_REASON reason = signals.ExitReason(type);
         if(reason != EXIT_NONE)
         {
            Print("Closing position ", ticket, " by rule ", EnumToString(reason));
            m_trade.PositionClose(ticket);
         }
      }
   }

   bool Execute(const SignalContext &ctx, const double volume, const double sl, const double tp, string &reject_reason)
   {
      reject_reason = "";
      const int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints)
      {
         reject_reason = StringFormat("spread filter blocked entry: spread=%d max=%d", spread, InpMaxSpreadPoints);
         Print("Spread filter blocked entry. Spread=", spread);
         return false;
      }
      if(ctx.direction == SIGNAL_BUY)
         return m_trade.Buy(volume, _Symbol, 0.0, sl, tp, ctx.reason);
      if(ctx.direction == SIGNAL_SELL)
         return m_trade.Sell(volume, _Symbol, 0.0, sl, tp, ctx.reason);
      return false;
   }
};

//----------------------------- Globals -----------------------------
CIndicatorEngine  g_indicators;
CSignalEngine     g_signals;
CRiskManager      g_risk;
CExecutionEngine  g_execution;
CBacktestLogger   g_logger;
datetime          g_last_bar_time = 0;

bool IsNewBar()
{
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpTradeTimeframe, 0, 2, t) < 2)
      return false;
   if(t[0] == g_last_bar_time)
      return false;
   g_last_bar_time = t[0];
   return true;
}

int OnInit()
{
   g_indicators.Init(_Symbol);
   g_signals.Init(g_indicators);
   g_risk.Init(g_indicators);
   g_execution.Init();
   g_logger.Init();
   Print("BillWilliamsChaosEA initialized for ", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_logger.Deinit();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      g_logger.LogDeal(trans.deal);
}

void OnTick()
{
   if(InpTradeOnNewBarOnly && !IsNewBar())
      return;

   g_execution.CloseByExitRules(g_signals);
   g_execution.ApplyAlligatorTrailingStop(g_indicators);

   SignalContext ctx = g_signals.BuildSignal();
   if(ctx.direction == SIGNAL_NONE)
   {
      if(InpLogEveryDecision)
         g_logger.LogSignal("NO_ENTRY", ctx);
      return;
   }

   string reject_reason = "";
   if(!IsTradingTimeAllowed(reject_reason))
   {
      ctx.reason = reject_reason;
      g_logger.LogSignal("ORDER_BLOCKED", ctx);
      return;
   }

   if(g_execution.HasOppositePosition(ctx.direction) && InpCloseOnOppositeSignal)
   {
      g_execution.CloseOppositePositions(ctx.direction);
      if(!InpReverseOnOppositeSignal)
      {
         ctx.reason = "opposite signal closed existing position; reverse entry disabled";
         g_logger.LogSignal("ORDER_BLOCKED", ctx);
         return;
      }
   }

   if(!g_execution.ExposureAllowsEntry(ctx.direction, reject_reason))
   {
      ctx.reason = reject_reason;
      if(InpLogEveryDecision)
         g_logger.LogSignal("NO_ENTRY", ctx);
      return;
   }

   double volume = 0.0, sl = 0.0, tp = 0.0;
   if(!g_risk.BuildOrderPlan(ctx.direction, ctx.fractal, volume, sl, tp))
   {
      ctx.reason = "No order: risk manager failed to build order plan";
      g_logger.LogSignal("ORDER_BLOCKED", ctx);
      Print("Risk manager failed to build order plan");
      return;
   }

   g_logger.LogSignal("ENTRY_SIGNAL", ctx);
   reject_reason = "";
   if(g_execution.Execute(ctx, volume, sl, tp, reject_reason))
      g_logger.LogSignal("ORDER_SENT", ctx);
   else
   {
      if(reject_reason == "")
         reject_reason = StringFormat("order send failed: terminal error %d", GetLastError());
      ctx.reason = reject_reason;
      g_logger.LogSignal("ORDER_BLOCKED", ctx);
      Print("Order send failed: ", reject_reason);
   }
}
//+------------------------------------------------------------------+
