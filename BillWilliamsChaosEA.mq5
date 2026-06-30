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
input int             InpMinAlligatorGapPts   = 10;

input group "Awesome Oscillator / Fractals / MFI"
input int             InpAOFastPeriod         = 5;
input int             InpAOSlowPeriod         = 34;
input int             InpFractalLookbackBars  = 80;
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
         FileWrite(m_handle, "time", "symbol", "event", "direction", "reason", "ao", "jaw", "teeth", "lips", "fractal_price", "fractal_time");
      FileSeek(m_handle, 0, SEEK_END);
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
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
                   ctx.reason, DoubleToString(ctx.ao_current, _Digits), DoubleToString(ctx.main_alligator.jaw, _Digits),
                   DoubleToString(ctx.main_alligator.teeth, _Digits), DoubleToString(ctx.main_alligator.lips, _Digits),
                   DoubleToString(ctx.fractal.price, _Digits), TimeToString(ctx.fractal.time, TIME_DATE|TIME_SECONDS));
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
      ctx.main_alligator = m_ind.GetAlligator(InpTradeTimeframe, 1);
      ctx.trend_alligator = m_ind.GetAlligator(InpTrendTimeframe, 1);
      ctx.ao_current = m_ind.GetAO(InpTradeTimeframe, 1);
      ctx.ao_previous = m_ind.GetAO(InpTradeTimeframe, 2);

      const FractalSignal bull = m_ind.FindFractal(InpTradeTimeframe, true, InpFractalLookbackBars);
      const FractalSignal bear = m_ind.FindFractal(InpTradeTimeframe, false, InpFractalLookbackBars);
      const AlligatorState confirm = m_ind.GetAlligator(InpConfirmTimeframe, 1);
      const double confirm_ao = m_ind.GetAO(InpConfirmTimeframe, 1);
      const double confirm_ao_prev = m_ind.GetAO(InpConfirmTimeframe, 2);

      if(ctx.main_alligator.aligned_up && ctx.trend_alligator.aligned_up && confirm.aligned_up &&
         ctx.main_alligator.price_above && ctx.main_alligator.gap_points >= InpMinAlligatorGapPts &&
         bull.found && bull.price > MathMax(ctx.main_alligator.teeth, ctx.main_alligator.lips) &&
         ctx.ao_current > 0.0 && ctx.ao_current > ctx.ao_previous && confirm_ao > confirm_ao_prev &&
         m_ind.MfiFilterOk(InpTradeTimeframe, true))
      {
         ctx.direction = SIGNAL_BUY;
         ctx.fractal = bull;
         ctx.mfi_ok = true;
         ctx.reason = "Alligator up on H1/D1/M15; price above Alligator; bullish fractal above teeth/lips; AO positive and rising; MFI filter ok";
      }
      else if(ctx.main_alligator.aligned_down && ctx.trend_alligator.aligned_down && confirm.aligned_down &&
              ctx.main_alligator.price_below && ctx.main_alligator.gap_points >= InpMinAlligatorGapPts &&
              bear.found && bear.price < MathMin(ctx.main_alligator.teeth, ctx.main_alligator.lips) &&
              ctx.ao_current < 0.0 && ctx.ao_current < ctx.ao_previous && confirm_ao < confirm_ao_prev &&
              m_ind.MfiFilterOk(InpTradeTimeframe, false))
      {
         ctx.direction = SIGNAL_SELL;
         ctx.fractal = bear;
         ctx.mfi_ok = true;
         ctx.reason = "Alligator down on H1/D1/M15; price below Alligator; bearish fractal below teeth/lips; AO negative and falling; MFI filter ok";
      }
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

   bool Execute(const SignalContext &ctx, const double volume, const double sl, const double tp)
   {
      if(HasPositionDirection(ctx.direction))
         return false;
      const int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints)
      {
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

void OnTick()
{
   if(InpTradeOnNewBarOnly && !IsNewBar())
      return;

   g_execution.CloseByExitRules(g_signals);

   SignalContext ctx = g_signals.BuildSignal();
   if(ctx.direction == SIGNAL_NONE)
      return;

   double volume = 0.0, sl = 0.0, tp = 0.0;
   if(!g_risk.BuildOrderPlan(ctx.direction, ctx.fractal, volume, sl, tp))
   {
      Print("Risk manager failed to build order plan");
      return;
   }

   g_logger.LogSignal("ENTRY_SIGNAL", ctx);
   if(g_execution.Execute(ctx, volume, sl, tp))
      g_logger.LogSignal("ORDER_SENT", ctx);
   else
      Print("Order send failed: ", GetLastError());
}
//+------------------------------------------------------------------+
