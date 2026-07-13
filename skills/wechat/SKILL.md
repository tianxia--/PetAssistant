---
name: wechat
description: 微信收发消息(双向)。发消息:用户说'发到微信/微信提醒我/发我微信'时用 action=send。收消息:想看有没有新微信时用 action=receive(一次拉取)。需先登录(见下),没登录会提示。
entry: run.py
args: {"action":"send 或 receive","text":"action=send 时的消息正文"}
---
# 微信收发(iLink Bot 协议)

通过微信 iLink Bot 协议(`ilinkai.weixin.qq.com`)收发消息,纯 Python 标准库 + curl,不需要 Node。双向:能发、也能收。

## 用法(二蛋会用的)

- 发消息:`{"action":"send","text":"..."}` —— 给用户自己的微信发一条文本。
- 收消息:`{"action":"receive"}` —— 拉取一次新消息(长轮询,最多 ~35s),返回收到的文本。

## 登录(一次性,手动在终端做)

因为要扫二维码,登录请在终端手动跑一次:

```bash
cd ~/Desktop/PetAssistant
echo '{"action":"login"}' | python3 skills/wechat/run.py
```

会打印一个二维码链接,浏览器打开、手机微信扫码确认;成功后凭证存到 `skills/wechat/wechat.conf`(已 gitignore),之后发/收就能直接用了。

## 说明与注意

- 凭证:`wechat.conf`(token / userId / baseUrl);收消息游标:`updates.buf`。都不入库。
- **建议用微信小号登录**:iLink 是个人号的非官方 bot 通道,自动化有封号风险。
- `receive` 是「拉一次」,不是常驻监听。想让二蛋自动回微信需要常驻轮询循环(后续可做)。
- 只发给/收自己(登录的那个号)。发的内容支持普通文本。

> 协议移植参考:github.com/tianxia--/wechat-tech-bot(TS 版)。这里用 Python 重写了登录 / 发送 / 收取三个接口。
