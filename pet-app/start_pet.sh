#!/bin/zsh
# 启动二蛋桌面宠物(已在运行则先退出旧实例)
cd ~/Desktop/PetAssistant/pet-app || exit 1
ROOT="$(cd .. && pwd)"

# 首次运行:从 .example 种子文件生成本地数据/配置(已存在则不动)
seed() { [ -f "$ROOT/$2" ] || { [ -f "$ROOT/$1" ] && cp "$ROOT/$1" "$ROOT/$2" && echo "初始化 $2"; }; }
seed pet-data/about-you.example.md            pet-data/about-you.md
seed pet-data/tasks.example.md                pet-data/tasks.md
seed pet-data/inbox.example.md                pet-data/inbox.md
seed skills/branch-report/data/repos.txt.example skills/branch-report/data/repos.txt
seed skills/tech-news/sources.txt.example     skills/tech-news/sources.txt
seed pet-config.example.json                  pet-config.json

pkill -x ErDanPet 2>/dev/null
pkill -f mem_service.py 2>/dev/null   # 顺带收掉旧的记忆服务,避免端口占用/堆叠
sleep 0.3
if [ ! -x .build/debug/ErDanPet ] && [ ! -x .build/release/ErDanPet ]; then
  swift build || exit 1
fi
BIN=.build/release/ErDanPet
[ -x "$BIN" ] || BIN=.build/debug/ErDanPet

# 打包成 ErDanPet.app 并用本地自签证书签名。
# 目的:让二蛋有稳定的 App 身份,macOS 才记得住你给的授权(如读 Matrx 通知),不再每次弹权限框。
# 自签证书免费、纯本地(存登录钥匙串),不需要 Apple 账号/联网/公证。
# 只有在 .app 缺失 / 二进制更新 / 未被本证书签过时才重新打包+签名,
# 否则直接复用已签好的 .app —— 避免每次启动都调 codesign(会弹钥匙串授权)。
CERT="ErDan Pet Self-Signed"
APP=".build/ErDanPet.app"
APPBIN="$APP/Contents/MacOS/ErDanPet"
if [ ! -f "$APPBIN" ] || [ "$BIN" -nt "$APPBIN" ] || ! codesign -dv "$APP" 2>&1 | grep -q "$CERT"; then
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$CERT"; then
    echo "首次:在登录钥匙串创建本地自签代码签名证书「$CERT」(免费、纯本地)"
    T=$(mktemp -d)
    cat > "$T/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$CERT
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$T/k.pem" -out "$T/c.pem" -config "$T/cfg" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -out "$T/id.p12" -inkey "$T/k.pem" -in "$T/c.pem" -passout pass:erdanpet 2>/dev/null
    security import "$T/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P erdanpet -T /usr/bin/codesign -A >/dev/null 2>&1
    rm -rf "$T"
  fi
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$BIN" "$APPBIN"
  cp Info.plist "$APP/Contents/Info.plist"
  HASH=$(security find-identity -p codesigning 2>/dev/null | grep "$CERT" | head -1 | awk '{print $2}')
  echo "签名 ErDanPet.app(若弹钥匙串授权,点『始终允许』一次即可,以后不再弹)"
  codesign --force --sign "${HASH:--}" --identifier io.erdan.pet "$APP"
fi
open "$APP"                              # 用 open 启动:授权归属才是"二蛋"自己,而不是启动它的终端
sleep 1
if pgrep -x ErDanPet >/dev/null; then echo "二蛋已启动(ErDanPet.app)"; else echo "⚠️ 启动失败,看 Console.app 里 ErDanPet 的日志"; fi
