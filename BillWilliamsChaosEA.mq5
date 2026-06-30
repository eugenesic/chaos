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

input group "Alligator"
input int             InpJawPeriod            = 13;
input int             InpJawShift             = 8;
input int             InpTeethPeriod          = 8;
input int             InpTeethShift           = 5;
input int             InpLipsPeriod           = 5;
input int             InpLipsShift            = 3;
input int             InpMinAlligatorGapPts   = 5;
input bool            InpRequireConfirmAlligator = false;

input group "Awesome Oscillator / Fractals / MFI"
input int             InpAOFastPeriod         = 5;
input int             InpAOSlowPeriod         = 34;
input int             InpFractalLookbackBars  = 80;
input bool            InpRequireConfirmAO     = false;
input bool            InpUseMfiFilter         = false;
input int             InpMfiAveragePeriod     = 20;

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

//----------------------------- Types -------------------------------
enum ENUM_SIGNAL_DIRECTION { SIGNAL_NONE = 0, SIGNAL_BUY = 1, SIGNAL_SELL = -1 };

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
};

string BoolText(const bool value)
{
   return (value ? "yes" : "no");
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
         FileWrite(m_handle, "time", "symbol", "event", "direction", "reason", "diagnostics", "ao", "ao_previous", "jaw", "teeth", "lips", "trend_jaw", "trend_teeth", "trend_lips", "fractal_price", "fractal_time", "fractal_shift");
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
                _Symbol, "DEAL_EXECUTED", direction, reason, diagnostics, "", "", "", "", "", "", "", "", "", "", "");
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
                   DoubleToString(ctx.fractal.price, _Digits), TimeToString(ctx.fractal.time, TIME_DATE|TIME_SECONDS), ctx.fractal.shift);
         FileFlush(m_handle);
      }
   }
};

//--------------------------- Signal Engine -------------------------
class CSignalEngine
{
private:
   CIndicatorEngine *m_ind;
public:
   void Init(CIndicatorEngine &ind) { m_ind = &ind; }

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
      const bool buy_fractal_ok = (bull.found && bull.price > MathMax(ctx.main_alligator.teeth, ctx.main_alligator.lips));
      const bool sell_fractal_ok = (bear.found && bear.price < MathMin(ctx.main_alligator.teeth, ctx.main_alligator.lips));
      const bool gap_ok = (ctx.main_alligator.gap_points >= InpMinAlligatorGapPts);
      const bool buy_confirm_alligator_ok = (!InpRequireConfirmAlligator || confirm.aligned_up);
      const bool sell_confirm_alligator_ok = (!InpRequireConfirmAlligator || confirm.aligned_down);
      const bool buy_confirm_ao_ok = (!InpRequireConfirmAO || confirm_ao > confirm_ao_prev);
      const bool sell_confirm_ao_ok = (!InpRequireConfirmAO || confirm_ao < confirm_ao_prev);
      const bool buy_ao_ok = (ctx.ao_current > 0.0 && ctx.ao_current > ctx.ao_previous && buy_confirm_ao_ok);
      const bool sell_ao_ok = (ctx.ao_current < 0.0 && ctx.ao_current < ctx.ao_previous && sell_confirm_ao_ok);

      ctx.diagnostics = StringFormat("BUY checks: main_up=%s trend_up=%s confirm_up=%s(confirm_required=%s confirm_ok=%s) price_above=%s gap_ok=%s(%.1f/%d) fractal_ok=%s(found=%s price=%s shift=%d) ao_ok=%s(ao=%s prev=%s confirm_required=%s confirm_ao=%s confirm_prev=%s confirm_ok=%s) mfi_ok=%s | SELL checks: main_down=%s trend_down=%s confirm_down=%s(confirm_required=%s confirm_ok=%s) price_below=%s gap_ok=%s fractal_ok=%s(found=%s price=%s shift=%d) ao_ok=%s(confirm_required=%s confirm_ok=%s) mfi_ok=%s",
                                     BoolText(ctx.main_alligator.aligned_up), BoolText(ctx.trend_alligator.aligned_up), BoolText(confirm.aligned_up),
                                     BoolText(InpRequireConfirmAlligator), BoolText(buy_confirm_alligator_ok),
                                     BoolText(ctx.main_alligator.price_above), BoolText(gap_ok), ctx.main_alligator.gap_points, InpMinAlligatorGapPts,
                                     BoolText(buy_fractal_ok), BoolText(bull.found), DoubleToString(bull.price, _Digits), bull.shift,
                                     BoolText(buy_ao_ok), DoubleToString(ctx.ao_current, _Digits), DoubleToString(ctx.ao_previous, _Digits),
                                     BoolText(InpRequireConfirmAO), DoubleToString(confirm_ao, _Digits), DoubleToString(confirm_ao_prev, _Digits),
                                     BoolText(buy_confirm_ao_ok), BoolText(buy_mfi_ok),
                                     BoolText(ctx.main_alligator.aligned_down), BoolText(ctx.trend_alligator.aligned_down), BoolText(confirm.aligned_down),
                                     BoolText(InpRequireConfirmAlligator), BoolText(sell_confirm_alligator_ok),
                                     BoolText(ctx.main_alligator.price_below), BoolText(gap_ok), BoolText(sell_fractal_ok), BoolText(bear.found),
                                     DoubleToString(bear.price, _Digits), bear.shift, BoolText(sell_ao_ok),
                                     BoolText(InpRequireConfirmAO), BoolText(sell_confirm_ao_ok), BoolText(sell_mfi_ok));

      if(ctx.main_alligator.aligned_up && ctx.trend_alligator.aligned_up && buy_confirm_alligator_ok &&
         ctx.main_alligator.price_above && gap_ok && buy_fractal_ok && buy_ao_ok && buy_mfi_ok)
      {
         ctx.direction = SIGNAL_BUY;
         ctx.fractal = bull;
         ctx.mfi_ok = true;
         ctx.reason = "Plan A BUY: Alligator up on trade/trend timeframes; confirm Alligator optional; price above Alligator; bullish fractal above teeth/lips; AO positive and rising; confirm AO optional; MFI filter ok";
      }
      else if(ctx.main_alligator.aligned_down && ctx.trend_alligator.aligned_down && sell_confirm_alligator_ok &&
              ctx.main_alligator.price_below && gap_ok && sell_fractal_ok && sell_ao_ok && sell_mfi_ok)
      {
         ctx.direction = SIGNAL_SELL;
         ctx.fractal = bear;
         ctx.mfi_ok = true;
         ctx.reason = "Plan A SELL: Alligator down on trade/trend timeframes; confirm Alligator optional; price below Alligator; bearish fractal below teeth/lips; AO negative and falling; confirm AO optional; MFI filter ok";
      }
      if(ctx.direction == SIGNAL_NONE)
         ctx.reason = "No entry: not all mandatory BUY or SELL filters passed. See diagnostics column for the exact failed checks.";
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

   bool HasPositionDirection(const ENUM_SIGNAL_DIRECTION direction) const
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
            continue;
         const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if((direction == SIGNAL_BUY && type == POSITION_TYPE_BUY) || (direction == SIGNAL_SELL && type == POSITION_TYPE_SELL))
            return true;
      }
      return false;
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
      if(HasPositionDirection(ctx.direction))
      {
         reject_reason = "position in the same direction already exists";
         return false;
      }
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

   SignalContext ctx = g_signals.BuildSignal();
   if(ctx.direction == SIGNAL_NONE)
   {
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
   string reject_reason = "";
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
