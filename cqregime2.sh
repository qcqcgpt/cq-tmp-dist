#!/bin/bash
# 立方量化 · 市场温度计 + 行情补数修复 部署脚本 v2
# 内容：core regime 模块 / 数据源收盘后补拉 / 前端构建
# 用法: bash /tmp/cqregime2.sh   （部署需开机密码，sudo 时会提示）
set -e
MD5EXP="2c01f335f40117f79f3527b5d7fff6ec"
URL="https://cdn.jsdelivr.net/gh/qcqcgpt/cq-tmp-dist@47f7b83c945d6a2f728ce9fb26e401d696d5b872/cqregime2.tar.b64"
TOK="cubequant-dev-token"
API="http://127.0.0.1:8700"

echo "-- 下载负载"
curl -sL "$URL" -o /tmp/cqregime2.tar.b64
base64 -D -i /tmp/cqregime2.tar.b64 -o /tmp/cqregime2.tar
MD5=$(md5 -q /tmp/cqregime2.tar)
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

echo "-- 触发 datafeed 补下今日日线（根因修复：今日数据未下载到 QMT 本地库）"
python3 - <<'EOF' || true
import json, re, urllib.request
from datetime import date

# 找 core 实际使用的 yaml（含 xt_remote_url 的那个）
import glob
yaml_path = None
for p in glob.glob('/Users/qiubo/cubequant/configs/*.yaml'):
    if 'xt_remote_url' in open(p, encoding='utf-8').read():
        yaml_path = p
        break
txt = open(yaml_path, encoding='utf-8').read()
df = re.search(r'xt_remote_url:\s*["\']?([^"\'\s]+)', txt).group(1)
tok_m = re.search(r'remote_token:\s*["\']?([^"\'\s]+)', txt)
tok = tok_m.group(1) if tok_m else ''
m = re.search(r'watchlist:\n((?:\s+-.*\n)+)', txt)
syms = re.findall(r'-\s*["\']?(\d{6}\.(?:SH|SZ))', m.group(1)) if m else []
today = date.today().isoformat()
today_nd = today.replace('-', '')
print(f'配置文件 {yaml_path}，观察池 {len(syms)} 只，补下 {today} 日线…')
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # 直连绕代理
ok = 0
for s in syms:
    req = urllib.request.Request(f'{df}/md/daily?symbol={s}&start={today_nd}&end=')
    if tok:
        req.add_header('X-Cube-Token', tok)
    try:
        with opener.open(req, timeout=15) as r:
            bars = json.loads(r.read().decode()).get('bars', [])
        if bars and bars[-1].get('date') == today:
            ok += 1
    except Exception as e:
        print('  跳过', s, e)
print(f'今日日线就绪 {ok}/{len(syms)}（未就绪的由 core 收盘后补拉兜底）')
EOF

echo "-- 部署 core + 前端文件(需要开机密码)"
sudo rm -rf /Users/qiubo/cubequant/apps/terminal/dist
sudo tar -xf /tmp/cqregime2.tar -C /Users/qiubo/cubequant/
sudo chown -R qiubo:staff /Users/qiubo/cubequant/apps/core/regime \
  /Users/qiubo/cubequant/apps/core/main.py \
  /Users/qiubo/cubequant/apps/core/datahub/xt_remote_source.py \
  /Users/qiubo/cubequant/apps/core/tests/test_regime.py \
  /Users/qiubo/cubequant/apps/core/tests/test_xt_remote_source.py \
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

echo "-- 等待日线缓存预热 90s（后台仍在继续）"
sleep 90

echo "-- 选股器数据新鲜度自检（面板尾日期应为今天）"
curl -s -m 90 -X POST "$API/api/screen/strategy" -H "X-Cube-Token: $TOK" \
  -H "Content-Type: application/json" \
  -d '{"strategy_id":"ai_momentum_top","params":{}}' | head -c 400
echo

echo "-- 温度计首次计算（全历史回测，最长约 3 分钟，请耐心等待）"
curl -s -m 300 -X POST "$API/api/regime/run" -H "X-Cube-Token: $TOK" | head -c 1500
echo
echo "完成。浏览器里对立方量化页面按 Cmd+Shift+R 强制刷新。"
