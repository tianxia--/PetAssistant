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
seed pet-config.example.json                  pet-config.json

pkill -x ErDanPet 2>/dev/null
pkill -f mem_service.py 2>/dev/null   # 顺带收掉旧的记忆服务,避免端口占用/堆叠
sleep 0.3
if [ ! -x .build/debug/ErDanPet ] && [ ! -x .build/release/ErDanPet ]; then
  swift build || exit 1
fi
BIN=.build/release/ErDanPet
[ -x "$BIN" ] || BIN=.build/debug/ErDanPet
nohup "$BIN" >/tmp/erdanpet.log 2>&1 &
echo "二蛋已启动 (pid $!),日志: /tmp/erdanpet.log"
