# kubelet

> 本目录主要来讲解 kubelet，告诉大家什么是 kubelet 以及 kubelet 的工作原理。kubelet 源码位于 [kubelet](https://github.com/kubernetes/kubernetes/tree/master/pkg/kubelet)

# kubelet 简述

首先 kubelet 它是 Kubernetes 中最底层的组件。它负责每台机器上运行/创建/删除/更新容器。你可以将认为它是一个类似于进程级别的监控，就像 [supervisord](http://supervisord.org/)（主要关注于运行容器）。它始终要做的就是：用户给定一组要运行的容器并且确保它们都在运行。

