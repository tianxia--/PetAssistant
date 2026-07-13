"""微信 iLink Bot 协议(Python 移植自 wechat-tech-bot 的 client.ts)。
纯标准库 + curl(走系统信任链,兼容企业自签/代理证书)。
提供:扫码登录、发消息、收消息(长轮询)。"""
import base64
import json
import os
import subprocess
import time
import uuid

API_BASE = "https://ilinkai.weixin.qq.com"
APP_ID = "bot"
CHANNEL_VERSION = "2.4.3"
DEFAULT_BOT_TYPE = "3"
BOT_AGENT = "PetAssistant/ErDan"


def _client_version(v=CHANNEL_VERSION):
    p = [int(x) if x.isdigit() else 0 for x in (v.split(".") + [0, 0, 0])[:3]]
    return ((p[0] & 0xFF) << 16) | ((p[1] & 0xFF) << 8) | (p[2] & 0xFF)


def _random_uin():
    n = int.from_bytes(os.urandom(4), "big")
    return base64.b64encode(str(n).encode()).decode()


def _common_headers():
    return {"iLink-App-Id": APP_ID, "iLink-App-ClientVersion": str(_client_version())}


def _headers(token=None):
    h = {"Content-Type": "application/json", "AuthorizationType": "ilink_bot_token",
         "X-WECHAT-UIN": _random_uin(), **_common_headers()}
    if token:
        h["Authorization"] = "Bearer " + token.strip()
    return h


def _base_info():
    return {"channel_version": CHANNEL_VERSION, "bot_agent": BOT_AGENT}


def _curl(method, url, headers, body=None, timeout=15):
    cmd = ["curl", "-sS", "--max-time", str(timeout), "-X", method]
    for k, v in headers.items():
        cmd += ["-H", f"{k}: {v}"]
    if body is not None:
        cmd += ["--data-binary", json.dumps(body)]
    cmd.append(url)
    p = subprocess.run(cmd, capture_output=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode("utf-8", "replace").strip() or f"curl 退出码 {p.returncode}")
    text = p.stdout.decode("utf-8", "replace")
    if not text:
        return {}
    try:
        return json.loads(text)
    except Exception:
        snippet = " ".join(text.split())[:120]
        raise RuntimeError(f"服务器返回非 JSON(可能被公司代理/防火墙拦截了 ilinkai.weixin.qq.com):{snippet}")


def _post(base, endpoint, body, token=None, timeout=15, label="request"):
    url = (base.rstrip("/") + "/") + endpoint
    data = _curl("POST", url, _headers(token), body, timeout)
    ec = int(data.get("errcode", 0) or 0)
    if ec != 0:
        raise RuntimeError(f"{label} errcode={ec}: {data.get('errmsg') or data.get('message') or '未知错误'}")
    return data


def _get(base, endpoint, timeout, label="request"):
    url = (base.rstrip("/") + "/") + endpoint
    return _curl("GET", url, _common_headers(), None, timeout)


# ---- 登录 ----
def fetch_qr():
    data = _post(API_BASE, f"ilink/bot/get_bot_qrcode?bot_type={DEFAULT_BOT_TYPE}",
                 {"local_token_list": []}, label="fetchQR")
    qrcode = (data.get("qrcode") or "").strip()
    qr_url = (data.get("qrcode_img_content") or data.get("qrcodeUrl") or "").strip()
    if not qrcode or not qr_url:
        raise RuntimeError(data.get("message") or "二维码响应不完整")
    return qrcode, qr_url


def wait_login(qrcode, timeout_s=300):
    base = API_BASE
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            st = _get(base, f"ilink/bot/get_qrcode_status?qrcode={qrcode}", 35, "pollQR")
        except Exception:
            st = {"status": "wait"}
        state = (st.get("status") or "").strip()
        if state in ("wait", "scaned"):
            pass
        elif state == "expired":
            return {"connected": False, "message": "二维码已过期,请重新登录"}
        elif state in ("need_verifycode", "verify_code_blocked"):
            return {"connected": False, "message": "微信要求验证码,请稍后重试"}
        elif state == "binded_redirect":
            return {"connected": False, "message": "已连接过此 Bot,无需重复连接"}
        elif state == "scaned_but_redirect":
            host = (st.get("redirect_host") or "").strip()
            if host:
                base = "https://" + host
        elif state == "confirmed":
            token = (st.get("bot_token") or "").strip()
            user_id = (st.get("ilink_user_id") or "").strip()
            base_url = (st.get("baseurl") or API_BASE).strip()
            if not token or not user_id:
                return {"connected": False, "message": "登录失败:服务器未返回完整信息"}
            return {"connected": True, "token": token, "userId": user_id, "baseUrl": base_url}
        time.sleep(2)
    return {"connected": False, "message": "登录超时"}


# ---- 收发 ----
def notify_start(acc):
    _post(acc["baseUrl"], "ilink/bot/msg/notifystart", {"base_info": _base_info()},
          token=acc["token"], timeout=10, label="notifyStart")


def send_message(acc, text):
    if not text.strip():
        return {"ok": False, "message": "消息为空"}
    mid = "erdan-" + uuid.uuid4().hex
    resp = _post(acc["baseUrl"], "ilink/bot/sendmessage", {
        "msg": {"from_user_id": "", "to_user_id": acc["userId"], "client_id": mid,
                "message_type": 2, "message_state": 2,
                "item_list": [{"type": 1, "text_item": {"text": text}}]},
        "base_info": _base_info()},
        token=acc["token"], timeout=15, label="sendMessage")
    if int(resp.get("ret", 0) or 0) != 0:
        return {"ok": False, "message": f"ret={resp.get('ret')}"}
    return {"ok": True, "messageId": mid}


def get_updates(acc, buf=""):
    resp = _post(acc["baseUrl"], "ilink/bot/getupdates",
                 {"get_updates_buf": buf, "base_info": _base_info()},
                 token=acc["token"], timeout=35, label="getUpdates")
    msgs = resp.get("msgs") if isinstance(resp.get("msgs"), list) else []
    next_buf = resp.get("get_updates_buf") if isinstance(resp.get("get_updates_buf"), str) else buf
    return msgs, next_buf
