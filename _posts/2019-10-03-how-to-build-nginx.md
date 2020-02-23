---
title:  How to build nginx
date:   2019-10-03 13:32:20 +0800
description: How to build nginx with the source code
# Add post description (optional)
tags: [Nginx, Build]
author: Jameslahm # Add name author (optional)
key: how-to-build-nginx
---
First, download the source code
```
wget http://nginx.org/download/nginx-1.9.9.tar.gz
```
Attention:here, you can choose the version of nginx according to your need

Then, unzip the file
```
tar -zxvf nginx-1.9.9.tar.gz
```

You wil find a new dir named "nginx-1.9.9" in your current dir

Then, compile and install
```
cd nginx-1.9.9 #change current dir

# configure
./configure --with=http_ssl_module --prefix=/usr/local/nginx

# the prefix `/usr/local/nginx` means the install path where you want to place nginx. Thus, you are free to choose this, but usually the prefix is `/usr/local/nginx`

# complie and install
make 
make install
```

Do some test
```
cd /usr/local/nginx/bin

# start nginx
nginx
```
if normal, Congratulations!

Hold on, there are some questions you may encounter

- **openssl compile error**
  
  This is beacuse the verison of openssl is not compatible. Nginx prefers openssl with the version 1.1 below. if that happened, try to compile nginx with openssl source code
  ```
  wget http://www.openssl.org/source/openssl-1.0.2d.tar.gz
  tar -zxcf openssl-1.0.2d.tar.gz
  ```
  Then when compile nginx,
  ```
  ./configure --with=http_ssl_module --prefix=/usr/local/nginx --with-openssl=path/to/openssl-source
  # please replace `path/to/openssl-source` with your real path
  ```

If there any question, I'm pleased to see that in the comment area and reply you

