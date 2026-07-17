#!/usr/bin/env python3
"""检测 Matrx 是否有新消息 —— 只看本地推送缓存文件的修改时间(mtime),不读任何内容。

原理:Matrx 每来一条消息就会写它的本地库,`PushCache.sqlite*` 的 mtime 随之变动。
本地库是端到端加密的(读不了内容),但 mtime 是文件系统元数据,随便读,也够用:
我们只需要"有没有新活动"这一个信号。

输出(stdout, JSON):{"latest": <最新 mtime 的整数秒>, "count": <匹配到的文件数>}
App 侧记住上次的 latest,变大了就提醒。找不到文件时 latest=0。
"""
import glob
import json
import os

MX = os.path.expanduser(
    "~/Library/Containers/io.matrx.desktop/Data/Documents/MX")


def main():
    latest = 0
    count = 0
    # PushCache = 推送/来消息缓存;.sqlite-wal 是活跃写入文件,.sqlite 作兜底
    for pat in ("**/PushCache.sqlite-wal", "**/PushCache.sqlite"):
        for f in glob.glob(os.path.join(MX, pat), recursive=True):
            try:
                m = int(os.stat(f).st_mtime)
            except OSError:
                continue
            count += 1
            if m > latest:
                latest = m
    print(json.dumps({"latest": latest, "count": count}))


if __name__ == "__main__":
    main()
