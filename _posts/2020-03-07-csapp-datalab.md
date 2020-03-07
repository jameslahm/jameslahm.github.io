---
title:  CSAPP DATALAB
date:   2020-03-07 14:54:20 +0800
description: CSAPP DATALAB
# Add post description (optional)
tags: [CSAPP]
author: Jameslahm # Add name author (optional)
key: csapp-datalab
mathjax: true
---

### Report For Puzzles

#### Bit Manipulations

1. `bitAnd`:

   Similar to $A \cap B=-(-A \cup -B)$, $\sim (\sim x | \sim y)=x\&y$

2. `getByte`:

   To extract byte n from x, first shift x to the right by $n<<3$, thus making the wanted byte reside in the last byte in x. Then x & 0xff is the wanted byte.

3. `logicalShift`:

   To logically shift x to the right, first get $\sim ((1<<31>>n)<<1)$ to be as the mask. Then, arithmetically shift x and x & make is the wanted result.

4. `bitCount`:

   First, divide x into two by two. In the two bits, it's can be easily evidenced that the sum of high order bit and low order bit equals the count of number of 1's in the two bits. Thus, using 0x55555555 as mask, each two-digit value in (x&mask + (x>>1)&mask) represents the number of 1's in the two digits. Recursively, divide the result four b four, eight by eight and sixteen by sixteen. To eliminate the ops, in eight-digit dividing and sixteen-digit dividing, it's reasonable to omit the mask. And at last, because the final result can't exceed $2^5$，thus x&0x3f is the final number of 1's in x.

5. `bang`:

   In `bang` function, only need to distinguish 0 and others. Only in 0|(~0+1), the first bit is 0. Thus, extract the first bit using x|(~x+1) >>31 and bitwise not it. At last, bitwise and 1 is the final result.



#### Two's Complement Arithmetic

1. `tmin`:

   1<<31 is the TMIN

2. `fitBits`:

   discuss in two situations using x's sign bit. When x is positive, if all bits in x>>(n+~0) equal 0, then n bits can represent x, vice versa. When x is negative, if all bits in ~ x>>(n+~0) equal 0, then n bits can represent x.

   >n+~0=n-1

3. `divpwr2`:

   discuss in two situations using x's sign bit. When x is positive, x>>n is the final result. When x is negative, using x+(1<<n)+~0 to shift to the right for rounding toward zero.

4. `negate`:

   ~x+1=-x

5. `isPositive`:

   !(x&(1<<31)) = 1 when x is positive. Besides, taking account of zero, using the result Bitwise and !!x to get the right result.

6. `isLessOrEqual`:

   Tacking account of overflow, discuss in two's situation using x and y's sign. When x's sign and y's sign is the same, if (y+~x+1) is positive, x is Less Or Equal y. When x's sign and y's sign is different, if x is negative, the x is Less Or Equal y.

7. `ilog2`:

   First divide x into sixteen by sixteen, using a=!!(x>>16) to see whether there exists 1 in the first sixteen bits. If exists, then x=x>>(1<<4) to shift the 1 to the right sixteen bits, vice versa. Then recursively, divide x into eight by eight to see whether the 1 reside in the second eight block from the right by b=!!(x>>8). If exists, then shift x to the right by (1<<3). Then, divide into four, two, one... At Last, (a<<4)+(b<<3)+(c<<2)+(d<<1)+e is the final result.



#### Floating-Point Operations

1. `float_neg`:

   discuss in two's situation by whether uf==NaN. When us equals NaN, return uf. Otherwise, uf ^ 0x80000000 is the final result.

   >using (((uf >> 23) & 0xff) == 0xff) && (uf & 0x7fffff) != 0 to distinguish whether uf equals NaN

2. `float_i2f`:

   The transformation is divided into three steps.

   - use sign to store x's sign And transform x into positive.
   - shift x to left to get the highest order bit of x as the exponential
   - use x & 0x01ff to distinguish whether x needs to add 1 to round and use flag to store

   Then the final result is sign + exponential + x's mantissa + flag

3. `float_twice`:

   discuss uf into two situations by whether uf is denormalized number and NaN. First, if (uf & 0x7f800000) == 0, then shift uf's mantissa to the left by 1. Then if uf is not denormalized and is not NaN, uf = uf + 0x00800000 represents the twice of uf. Otherwise, return uf.



### Experimental expreience

Through this experiment, I have a better command of Bit-level encoding rules of TINT, UINT numbers and float numbers. Actually, the lab is hard for me, so I struggle a lot in this lab and spend a lot of time. However, I acquire a lot from this lab in the meantime. I learn a lot about how integers and floats can be expressed in bit-level and how to accomplish various kinds of operations using just bit-level operations. It's really worth it.
