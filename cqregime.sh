#!/bin/bash
# 立方量化 · 市场温度计部署脚本（core regime 模块 + 前端构建）
# 用法: bash /tmp/cqregime.sh   （部署需开机密码，sudo 时会提示）
set -e
MD5EXP="c1f2d521a45ee3ed06c62c62fa9f6016"
URL="https://cdn.jsdelivr.net/gh/qcqcgpt/cq-tmp-dist@3dc16d725b4b55defc6eabe580e37aec69e150bd/cqregime.tar.b64"
TOK="cubequant-dev-token"
API="http://127.0.0.1:8700"

echo "-- 下载温度计负载"
curl -sL "$URL" -o /tmp/cqregime.tar.b64
base64 -D -i /tmp/cqregime.tar.b64 -o /tmp/cqregime.tar
MD5=$(md5 -q /tmp/cqregime.tar)
if [ "$MD5" != "$MD5EXP" ]; then echo "md5 不符: $MD5（应为 $MD5EXP），中止"; exit 1; fi
echo "md5 校验通过"

echo "-- 保存当前自动交易配置到 /tmp/autocfg.json"
curl -s "$API/api/auto/status" -H "X-Cube-Token: $TOK" > /tmp/autocfg.json
python3 - <<'EOF'
import json
st = json.load(open('/tmp/autocfg.json'))
cfg = st.get('config') or {}
out = {
  'strategy_id': cfg.get('strategy_id', ''),
  'params': cfg.get('params') or {},
  'interval_sec': cfg.get('interval_sec', 60),
  'invest_pct': cfg.get('invest_pct', 0.95),
  'min_order_value': cfg.get('min_order_value', 3000),
  'confirm': True,
}
json.dump({'running': bool(st.get('running')), 'start': out}, open('/tmp/autostart.json', 'w'))
print('当前运行中:', st.get('running'), '策略:', out['strategy_id'])
EOF

echo "-- 部署 core + 前端文件(需要开机密码)"
sudo rm -rf /Users/qiubo/cubequant/apps/terminal/dist
sudo tar -xf /tmp/cqregime.tar -C /Users/qiubo/cubequant/
sudo chown -R qiubo:staff /Users/qiubo/cubequant/apps/core/regime \
  /Users/qiubo/cubequant/apps/core/main.py \
  /Users/qiubo/cubequant/apps/core/tests/test_regime.py \
  /Users/qiubo/cubequant/apps/terminal/dist

echo "-- 重启 core"
launchctl kickstart -k gui/$(id -u)/com.cubequant.core

echo "-- 等待 core 就绪(最多 60s)"
ok=""
for i in $(seq 1 30); do
  sleep 2
  H=$(curl -s -m 3 "$API/api/health" || true)
  if [ -n "$H" ]; then echo "health: $H"; ok=1; break; fi
done
if [ -z "$ok" ]; then echo "core 60s 内未就绪，请查日志"; exit 1; fi

if python3 -c "import json;import sys;sys.exit(0 if json.load(open('/tmp/autostart.json'))['running'] else 1)"; then
  echo "-- 按刚保存的配置恢复自动交易"
  python3 -c "import json;print(json.dumps(json.load(open('/tmp/autostart.json'))['start']))" > /tmp/autostart_body.json
  curl -s -X POST "$API/api/auto/start" -H "X-Cube-Token: $TOK" -H "Content-Type: application/json" -d @/tmp/autostart_body.json
  echo
else
  echo "-- 自动交易原本未运行，不恢复"
fi

echo "-- 温度计状态(首次应为 trend / 未计算)"
curl -s "$API/api/regime/status" -H "X-Cube-Token: $TOK"
echo
echo "-- 手动触发首次计算(全历史回测，最长约 3 分钟，请耐心等待)"
curl -s -m 200 -X POST "$API/api/regime/run" -H "X-Cube-Token: $TOK" | head -c 1500
echo
echo "完成。浏览器里对立方量化页面按 Cmd+Shift+R 强制刷新。"
