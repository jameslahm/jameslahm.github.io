---
title:  CSAPP BUFLAB
date:   2020-04-12 16:54:20 +0800
description: CSAPP BUFLAB
# Add post description (optional)
tags: [CSAPP]
author: Jameslahm # Add name author (optional)
key: csapp-buflab
---

#### Level 0 Candle

首先在反汇编代码中找到smoke函数的地址为`0x08048b04`，接着在反汇编代码中找到getbuf函数，发现其缓冲区大小为`0x28`即40个字节，则构造48个字节输入，最后四个字节使用smoke函数地址覆盖原返回地址即可。



#### Level 1 Sparkler

首先在反汇编代码中找到fizz函数的地址为`0x08048b2e`，发现其调用参数地址为`0x8(%ebp)`，则只需构造56个字节，其中最后四个字节使用`cookie`值覆盖，第45至48字节使用fizz函数地址覆盖即可。



#### Level 2 Firecracker

首先在反汇编代码中找到bang函数的地址为`0x08048b82`，并发现`global_value`的地址为`0x804e10c`或者`0x804e104`，通过进入gdb调试，设置断点打印两个地址上变量的值可以发现`global_value`的地址为`0x0804e10c`，则可以通过在缓冲区开始位置输入执行改变`global_value`并跳入bang函数的代码，接着使用缓冲区首地址覆盖返回地址即可

```bash
// 首先更改global_value的值
movl $0x1f47b579,0x0804e10c
// 将bang函数地址push
push $0x08048b82
// 跳入bang函数并执行
ret
```

同时使用gdb调试，在getbuf函数设置断点，查看`%eax`的值获得缓冲区首地址为`0x556838f8`。则构造48个字节，其中开始位置放入汇编代码转为的十六进制指令，最后四个字节使用缓冲区首地址覆盖原地址即可。



#### Level 3 Dynamite

首先找到test函数中getbuf函数正常返回的下一条指令地址为`0x08048bf3`，同时使用gdb调试可得进入getbuf函数之前的`%ebp`值为`0x55683950`，则可以通过在缓冲区开始位置输入改变`%eax`（getbuf返回值）并跳入原下一条指令地址的代码，并在存放旧`%ebp`的位置使用原来的`%ebp`值覆盖，返回地址仍使用缓冲区首地址覆盖即可。

```bash
// 更改返回值
movl $0x1f47b579,%eax
// 将下一条指令地址push
push $0x08048bf3
// 跳入执行原下一条指令
ret
```

构造48个字节，将汇编代码转为十六进制指令放在开始位置，并在最后四个字节使用缓冲区首地址覆盖，倒数第二个四个字节使用原`%ebp`值覆盖即可。



#### Level 4 Nitroglycerin

首先在反汇编代码中找到getbufn函数，发现其缓冲区大小为520个字节，即需要构造528个字节。其中缓冲区中需要放入更改`%eax`的值、恢复正确`%ebp`的值并跳回原下一条指令地址的代码，返回地址则需要使用代码的地址进行覆盖。通过testn函数可以发现原`%ebp`的地址与`%esp`的地址相差28个字节，原下一条指令地址为`0x08048c67` 则代码为

```bash
// 更改返回值
movl $0x1f47b579,%eax
// 使用%esp值恢复%ebp值
leal 0x28(%esp),%ebp
// 将下一条指令地址push
push $0x08048c67
// 跳入执行下一条指令
ret
```

接着需要使用正确的代码地址覆盖原来的返回地址，由于栈地址是不确定的，因此可以先确定大概地址，然后使用`nop `指令将`PC`滑动到输入的代码指令地址。通过gdb调试，发现getbufn函数中5次缓冲区首地址最大为`0x55683748`，则可使用该最大地址进行覆盖，可保证最终能执行输入的代码指令。构造528个字节，前面均输入90，最后输入代码指令以及覆盖地址即可。





