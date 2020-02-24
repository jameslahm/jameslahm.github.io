---
title: 阿里云配置 
date: 2020-02-24 
description:  
tags: [‘linux’,'wsl'] 
author: Jameslahm 
key: aliyun-and-wsl-configuration
---

### 博客主题:pencil2:

上个周末把博客主题换了一下，之前也是`jekyll`主题的，但是可配置性不高，这次换一下博客主题也算是督促我好好学习、好好写写博客吧:joy:，毕竟之前博客搭好之后一直在划水。换博客主题时纠结了`vuepress`，不过想了想`vuepress`还是比较适合写文档，以后应该是这个主题写博客，`vuepress`写文档，希望不要划水:fist:。



### 阿里云配置:computer:

最近也刚刚续费了阿里云，今天在上面更换了`zsh`，在`jupyter`上加了`R kernel`，搭了`owncloud`的云盘。我手边现在也只有一个平板，多在阿里云上折腾折腾也是为了给我平板减压，比如加了`R kernel`，我就不用在我现在的平板上装`R Studio`了。

#### zsh

`zsh`的配置比较简单

- 安装

  ```shell
  # to see the shell using now
  echo $SHELL
  
  # to see all shells installed
  echo /etc/shells
  
  # if not installed 
  (sudo) apt-get install zsh
  
  chsh -s /bin/zsh
  ```

- 安装[*oh-my-zsh*](https://github.com/robbyrussell/oh-my-zsh)

  ```shell
  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ```

  安装成功之后，可以开始配置插件和选主题了:star:。我还是比较喜欢这个默认主题，比较清爽，当然可以通过~/.zshrc里面的[*ZSH_THEME*](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes) 来进行配置。

- 配置插件

  ```shell
  # 配置插件的方法大同小异
  # 我现在主要用了 zsh-syntax-highlight zsh-autosuggestions 这两个插件
  # 安装方法大同小异
  
  # e.g. zsh-syntax-highlight
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
  
  # ~/.zshrc 中配置plugins
  plugins=([plugins...] zsh-autosuggestions)
  
  # 其他插件与此类似
  
  # configurate autojump
  sudo apt-get install autojump
  # judge if .sh exists and execute
  echo "[[ -s ~/.autojump/etc/profile.d/autojump.sh ]] && . ~/.autojump/etc/profile.d/autojump.sh" >> ~/.zshrc
  # plugins=(... autojump)
  ```

#### owncloud

`owncloud`的配置比较简单，可以选择使用[官方`docker`镜像](https://doc.owncloud.com/server/admin_manual/installation/docker/)。

```shell
# Create a new project directory
mkdir owncloud-docker-server

cd owncloud-docker-server

# Copy docker-compose.yml from the GitHub repository
wget https://raw.githubusercontent.com/owncloud/docs/master/modules/admin_manual/examples/installation/docker/docker-compose.yml

# Create the environment configuration file
cat << EOF > .env
OWNCLOUD_VERSION=10.4
OWNCLOUD_DOMAIN=localhost
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin
HTTP_PORT=8080
EOF

# Build and start the container
docker-compose up -d

# see if run normally
docker-compose ps 
```

