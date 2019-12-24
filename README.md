# kube-explorer

本书旨在系统讲解 Kubernetes 核心组件原理，帮助读者快速入门 Kubernetes!

## kubernetes 简述

`Kubernetes` 早期的名字叫做 `Borg`,后来被谷歌开源之后叫做 `Kubernetes` 简称 `k8s`，是一个容器调度工具，它提供了强大的部署、运维、扩缩容能力。

## 组件列表

* [kube-apiserver](https://kube-explorer.gitbook.io/kube-explorer/index)      @hwdef
* [kube-controller-manager](https://kube-explorer.gitbook.io/kube-explorer/index-1)     @tanjunchen
* [kube-proxy](https://kube-explorer.gitbook.io/kube-explorer/index-4)      @SataQiu
* [kube-scheduler](https://kube-explorer.gitbook.io/kube-explorer/index-2)      @yuxiaobo96
* [kubeadm](https://kube-explorer.gitbook.io/kube-explorer/index-5)     @SataQiu
* [kubectl](https://kube-explorer.gitbook.io/kube-explorer/index-6)     @TomatoAres
* [kubelet](https://kube-explorer.gitbook.io/kube-explorer/index-3)     @xichengliudui

## 如何参与贡献

1: 在 Issues 列表创建 issue

* 点击上方 **`Issues`**
* 点击绿色按钮 **`new issue`**
* 输入标题以及描述
* 最后一步 `@` 每个目录的负责人。

2: 创建 Pull Request（拉取请求）

* 点击右上角 **`Fork`** 按钮，创建上游仓库副本
* 使用 git 命令克隆仓库副本 eg: git@github.com:xichengliudui/kube-explorer.git
* 创建新分支 eg: git checkout -b branch1
* 修改错误文件并保存
* git add --all
* git commit -m "fix xxx.md file"
* git push origin branch1
* 访问你的仓库副本，点击右边的 **`pull request`** 按钮
* 输入标题以及描述
* 最后一步 `@` 每个目录的负责人。
