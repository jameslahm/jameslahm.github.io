---
title:  SSL/TLS Introduction
date:   2020-03-29 15:45:20 +0800
description: SSL-TLS detailed introduction
# Add post description (optional)
tags: [Network]
author: Jameslahm # Add name author (optional)
key: ssl-tls
---



#### 作用

HTTPS 建立于SSL/TLS之上，用于保证通信数据的加密



#### 握手过程

- `Client Hello`

  客户端发送，包含`random1`以及客户端支持的加密套件[^1]组合等信息

- `Server Hello`

  服务端发送，包含后续使用的加密套件及`random2`

- `Certificate`

  服务器发送，包含证书信息

- `Certificate Verify`

  客户端使用内置CA公钥解密证书指纹信息及指纹算法，验证通过后，发送`PreMaster Key`[^2]，

  同时客户端与服务端生成会话密钥

- `Change Cipher Spec`

  客户端/服务端发送，通知后续使用密钥加密

- `Encrypted Handshake Message`

  客户端/服务端发送，将握手消息生成摘要进行加密，供服务端/客户端验证



#### 会话复用

服务端可以在握手过程中给客户端发送`Session ID`，后续握手时可直接复用



[^1]: 加密套件：包含握手过程中使用的加密算法，后续会话密钥使用的加密算法以及生成数字签名使用的哈希算法
[^2]: `PreMaster Key`是指客户端生成随机数并用CA中服务器公钥进行加密

