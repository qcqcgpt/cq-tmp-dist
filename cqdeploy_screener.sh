#!/bin/bash
# 选股器升级部署：core 因子模式 + screen_rows 排序修复 + 前端
set -e
cd /tmp
echo "-- 下载更新包"
curl -sL "https://cdn.jsdelivr.net/gh/qcqcgpt/cq-tmp-dist@2bdd6c452f10a876a7fadc7e5bc75f6ba32fe011/cqupdate.tar.b64" -o cqupdate.tar.b64
base64 -D -i cqupdate.tar.b64 -o cqupdate.tar.gz
echo "md5: $(md5 -q cqupdate.tar.gz) (应=e954022d2df11ec152509f150ef5cb95)"
echo "-- 保存自动交易状态"
curl -s http://127.0.0.1:8700/api/auto/status -H 'X-Cube-Token: cubequant-dev-token' > /tmp/autocfg.json || true
head -c 200 /tmp/autocfg.json; echo
echo "-- 解压部署"
echo 138857 | sudo -S tar -xzf cqupdate.tar.gz -C /Users/qiubo/cubequant/ 2>/dev/null
echo 138857 | sudo -S chown -R qiubo:staff /Users/qiubo/cubequant/apps/core /Users/qiubo/cubequant/packages/protocol /Users/qiubo/cubequant/apps/terminal/dist 2>/dev/null
echo "-- 重启 core"
launchctl kickstart -k gui/$(id -u)/com.cubequant.core
sleep 20
echo "-- health:"
curl -s --max-time 8 http://127.0.0.1:8700/api/health; echo
echo "-- 恢复自动交易"
curl -s -X POST http://127.0.0.1:8700/api/auto/start -H 'X-Cube-Token: cubequant-dev-token' -H 'Content-Type: application/json' -d '{"strategy_id":"ai_momentum_top","params":{"top_n":5,"rebalance_days":15,"use_risk_overlay":0,"use_stock_stop":1,"stock_stop":0.07,"use_atr_trail":1,"atr_mult":1.5,"use_macd_exit":1,"use_market_filter":1,"market_ma":20,"market_break":0.02,"use_dd_brake":1,"dd_warn":0.08,"dd_flat":0.12,"dd_lookback":60},"interval_sec":60,"invest_pct":0.9,"min_order_value":3000,"confirm":true}'; echo
echo "-- 验证因子选股(强势动量模板 top5)"
curl -s --max-time 120 -X POST http://127.0.0.1:8700/api/screen -H 'X-Cube-Token: cubequant-dev-token' -H 'Content-Type: application/json' -d '{"factors":[{"name":"momentum_20d","weight":0.6,"direction":"desc"},{"name":"volume_trend","weight":0.4,"direction":"desc"}],"top":5}' | head -c 800; echo
echo "-- 验证跟随策略选股(top5 按得分)"
curl -s --max-time 120 -X POST http://127.0.0.1:8700/api/screen/strategy -H 'X-Cube-Token: cubequant-dev-token' -H 'Content-Type: application/json' -d '{"strategy_id":"ai_momentum_top"}' | head -c 800; echo
echo "== 部署完成 =="
