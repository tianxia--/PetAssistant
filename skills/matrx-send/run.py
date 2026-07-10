#!/usr/bin/env python3
"""Matrx 群机器人 webhook 发送(自包含)。
stdin 收 JSON {"text":"..."} 或纯文本;webhook 地址读同目录 webhook.conf。
底层用 curl(兼容企业自签证书)。"""
import json
import os
import subprocess
import sys

DIR = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(DIR, "webhook.conf")


def load_url():
    if not os.path.exists(CONF):
        return None
    for line in open(CONF):
        line = line.split("#", 1)[0].strip()
        if line.startswith("MATRX_WEBHOOK_URL="):
            u = line.split("=", 1)[1].strip()
            if u:
                return u
    return None


def main():
    raw = sys.stdin.read()
    text = ""
    try:
        text = (json.loads(raw) or {}).get("text", "")
    except Exception:
        text = raw
    text = (text or "").strip()
    if not text:
        print("缺少 text,没发送"); return
    url = load_url()
    if not url:
        print("未配置 webhook 地址(skills/matrx-send/webhook.conf)"); return
    payload = json.dumps({"msg_type": "text", "content": {"text": text[:9990]}})
    try:
        p = subprocess.run(
            ["curl", "-sS", "-X", "POST", url,
             "-H", "Content-Type: application/json; charset=utf-8", "--data-binary", "@-"],
            input=payload.encode(), capture_output=True, timeout=40)
    except Exception as e:
        print(f"发送异常:{e}"); return
    out = p.stdout.decode(errors="replace")
    try:
        st = json.loads(out).get("responseHeader", {}).get("status")
        print("Matrx 发送成功" if st == 200 else f"Matrx 发送失败:{out[:200]}")
    except Exception:
        print(f"Matrx 响应异常:{out[:200]}")


if __name__ == "__main__":
    main()
