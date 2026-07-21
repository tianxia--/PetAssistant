#!/bin/zsh
# 开机自启开关:装/卸一个 LaunchAgent,登录时自动拉起二蛋。
#   ./autostart.sh        # 开启开机自启(默认)
#   ./autostart.sh off    # 关闭并移除
# 原理:登录时 launchd 执行 `open ErDanPet.app`,由 LaunchServices 在你的登录会话里启动二蛋
# (二蛋自己会拉起记忆服务)。用 open 而不是跑脚本,是为了绕开 ~/Desktop 的隐私保护——
# launchd 直接读 Desktop 里的脚本会被系统拦(报 can't open input file)。
# 退出二蛋后不会被强行拉回(无 KeepAlive)。
LABEL="io.erdan.pet"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$(cd "$(dirname "$0")" && pwd)/.build/ErDanPet.app"

if [ "$1" = "off" ] || [ "$1" = "uninstall" ]; then
  launchctl unload -w "$PLIST" 2>/dev/null
  rm -f "$PLIST"
  echo "已关闭开机自启并移除 $PLIST"
  exit 0
fi

if [ ! -d "$APP" ]; then echo "⚠️ 还没有 $APP,先跑一次 ./start_pet.sh 生成再来"; exit 1; fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/erdanpet-agent.log</string>
  <key>StandardErrorPath</key><string>/tmp/erdanpet-agent.log</string>
</dict>
</plist>
EOF
launchctl unload -w "$PLIST" 2>/dev/null
launchctl load -w "$PLIST" && echo "已开启开机自启:$PLIST" || echo "⚠️ 加载失败,看看 $PLIST"
