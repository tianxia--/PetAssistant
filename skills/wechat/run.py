#!/usr/bin/env python3
"""微信收发(自包含,纯标准库 + curl)。stdin 收 JSON:
  {"action":"send","text":"..."}   给自己的微信发一条文本
  {"action":"receive"}              收取新消息(一次长轮询,返回文本)
  {"action":"login"}                扫码登录(建议在终端手动跑:见 SKILL.md)
凭证存本目录 wechat.conf(已 gitignore),收消息游标存 updates.buf。"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ilink  # noqa: E402

DIR = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(DIR, "wechat.conf")
BUF = os.path.join(DIR, "updates.buf")


def load_acc():
    if not os.path.exists(CONF):
        return None
    with open(CONF, encoding="utf-8") as f:
        c = json.load(f)
    if c.get("token") and c.get("userId"):
        return {"token": c["token"], "userId": c["userId"], "baseUrl": c.get("baseUrl") or ilink.API_BASE}
    return None


def do_login():
    qrcode, qr_url = ilink.fetch_qr()
    print("用手机微信扫码登录(在浏览器打开下面链接看二维码):\n" + qr_url + "\n\n等待扫码确认...", flush=True)
    res = ilink.wait_login(qrcode)
    if not res.get("connected"):
        print("登录失败:" + res.get("message", "未知")); return
    with open(CONF, "w", encoding="utf-8") as f:
        json.dump({"token": res["token"], "userId": res["userId"], "baseUrl": res["baseUrl"]}, f, ensure_ascii=False, indent=2)
    print("✅ 微信登录成功,凭证已保存。现在可以收发消息了。")


def do_send(text):
    acc = load_acc()
    if not acc:
        print("还没登录微信。先在终端跑:python3 skills/wechat/run.py 里的 login(见 SKILL.md)。"); return
    try:
        ilink.notify_start(acc)
    except Exception:
        pass
    r = ilink.send_message(acc, text)
    print("✅ 已发到微信。" if r.get("ok") else "发送失败:" + r.get("message", "未知"))


def _extract(msgs):
    out = []
    for m in msgs:
        who = m.get("from_user_id") or m.get("from_username") or ""
        texts = []
        for it in (m.get("item_list") or []):
            ti = it.get("text_item") or {}
            if ti.get("text"):
                texts.append(ti["text"])
        body = " ".join(texts).strip()
        if body:
            out.append(f"- {('[' + who + '] ') if who else ''}{body}")
    return out


def do_receive():
    acc = load_acc()
    if not acc:
        print("还没登录微信。先在终端登录(见 SKILL.md)。"); return
    buf = ""
    if os.path.exists(BUF):
        buf = open(BUF, encoding="utf-8").read().strip()
    try:
        ilink.notify_start(acc)
    except Exception:
        pass
    msgs, next_buf = ilink.get_updates(acc, buf)
    if next_buf:
        with open(BUF, "w", encoding="utf-8") as f:
            f.write(next_buf)
    lines = _extract(msgs)
    print("收到新消息:\n" + "\n".join(lines) if lines else "(暂无新消息)")


def main():
    try:
        args = json.load(sys.stdin)
    except Exception:
        args = {}
    action = (args.get("action") or "").lower()
    try:
        if action == "login":
            do_login()
        elif action == "send":
            do_send(args.get("text") or "")
        elif action == "receive":
            do_receive()
        else:
            print("未知 action。用 {\"action\":\"send\",\"text\":\"...\"} 或 {\"action\":\"receive\"}。")
    except Exception as e:
        print("微信操作失败:" + str(e))


if __name__ == "__main__":
    main()
