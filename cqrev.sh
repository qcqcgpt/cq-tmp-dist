#!/bin/bash
# 立方反转 cube_reversal 参数变体回测（生产池 167 只，2023-01~2026-08 全历史 + 近一年）
TOKEN="X-Cube-Token: cubequant-dev-token"
URL="http://127.0.0.1:8700/api/backtest"

run() {
  local name="$1"; local params="$2"; local start="$3"; local end="$4"
  echo "===== $name [$start ~ $end] ====="
  curl -s --max-time 600 -X POST "$URL" \
    -H "$TOKEN" -H "Content-Type: application/json" \
    -d "{\"strategy_id\":\"cube_reversal\",\"params\":$params,\"start\":\"$start\",\"end\":\"$end\"}" \
  | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except Exception:
    print('ERROR:', raw[:200]); raise SystemExit
m=d.get('metrics',{})
eq=d.get('equity') or []
bm=d.get('benchmark') or []
def ann(curve):
    if len(curve)<2: return 0.0
    from datetime import date
    d0=date.fromisoformat(curve[0]['date']); d1=date.fromisoformat(curve[-1]['date'])
    yrs=max((d1-d0).days/365.25, 0.01)
    return (curve[-1]['value']/curve[0]['value'])**(1/yrs)-1
print('策略: 年化 %.1f%% 夏普 %.2f 回撤 %.1f%% 胜率 %.1f%% 交易 %d 笔' % (
    m.get('annual_return',0)*100, m.get('sharpe',0), m.get('max_drawdown',0)*100,
    m.get('win_rate',0)*100, m.get('total_trades',0)))
print('基准(等权全池): 年化 %.1f%%   期末净值 策略 %.3f vs 基准 %.3f' % (
    ann(bm)*100, eq[-1]['value'] if eq else 0, bm[-1]['value'] if bm else 0))
"
}

BASE='"top_n":15,"rebalance_days":10,"enter_rank":0.25,"exit_rank":0.40,"knife_ret":0.09,"knife_days":3,"vol_exclude_pct":0.90,"use_vol_target":0,"use_market_filter":0,"use_dd_brake":0'

run "A 推荐裸跑" "{$BASE}" "2023-01-03" "2026-08-21"
run "A 推荐裸跑" "{$BASE}" "2025-08-22" "2026-08-21"
run "B 5日调仓" '{"top_n":15,"rebalance_days":5,"enter_rank":0.25,"exit_rank":0.40,"knife_ret":0.09,"knife_days":3,"vol_exclude_pct":0.90,"use_vol_target":0,"use_market_filter":0,"use_dd_brake":0}' "2023-01-03" "2026-08-21"
run "C top10" '{"top_n":10,"rebalance_days":10,"enter_rank":0.25,"exit_rank":0.40,"knife_ret":0.09,"knife_days":3,"vol_exclude_pct":0.90,"use_vol_target":0,"use_market_filter":0,"use_dd_brake":0}' "2023-01-03" "2026-08-21"
run "D 默认全风控(对照)" '{}' "2023-01-03" "2026-08-21"
run "E 裸跑+宽大盘过滤" '{"top_n":15,"rebalance_days":10,"enter_rank":0.25,"exit_rank":0.40,"knife_ret":0.09,"knife_days":3,"vol_exclude_pct":0.90,"use_vol_target":0,"use_market_filter":1,"market_ma":20,"market_break":0.05,"use_dd_brake":0}' "2023-01-03" "2026-08-21"
run "E 裸跑+宽大盘过滤" '{"top_n":15,"rebalance_days":10,"enter_rank":0.25,"exit_rank":0.40,"knife_ret":0.09,"knife_days":3,"vol_exclude_pct":0.90,"use_vol_target":0,"use_market_filter":1,"market_ma":20,"market_break":0.05,"use_dd_brake":0}' "2025-08-22" "2026-08-21"
echo "REV-DONE"
