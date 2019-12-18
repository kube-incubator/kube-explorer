# kube-scheduler

## 概要

本节主要是对 Kubernetes 中的组件 kube-scheduler 进行介绍，包括 kube-scheduler 的主要功能和源码分析。
下面介绍一下，Kubernetes 的工作原理，及 kube-scheduler 在其中扮演的角色。

1. 首先，kubectl 发出命令，创建 ReplicaSet（或其他类 set），通过与 api-server 交互，并存储到 etcd 中

2. controller-manager 时刻 watch 各类 set，当检测到 ReplicaSet 时，创建相应的 pod，并通过 kube-apiserver 存储到 etcd 中，此时 pod 的 nodeName 为空

3. scheduler 在 k8s 集群中启到承上启下的作用：sheduler 时刻 watch 集群中的 node 和 pod，当它发现这个未调度的 pod，会对此 pod 进行多策略调度，把它绑定到合适的节点上，如 node1

4. 在 node1 上的 kubelet 对调度到本节点上的 pod 进行管理，执行其剩余的生命周期。

在这个过程中，sheduler 主要是对 nodeName 为空的 Pod 进行多策略调度，在调度过程中不仅需要关注 pod 本身的资源需求（如 memory、cpu、affinity等），还需要对 node 进行筛选，选出 source 最高的节点来部署这个 pod。
当然，也可以手动调度（不使用默认的调度器）如创建 pod 时直接指定 nodeName，或者自定义调度器。
在 pod 调度的过程中，还涉及到 node 上的 Taints（污点）参数，以及 pod 上的 Tolerations 参数的使用。

**注意**：这里所说的 scheduler 是指集群中默认的调度器：default-scheduler。

## 章节内容

1. 对 scheduler 详细介绍

2. 资源调度（Predicates 策略）

3. 关系调度（满足 Pod、Node 之间的关系）

4. 优先级调度（Priority策略）

5. 抢占式调度（Preemption 策略）

6. 外部调度（scheduler extender，类似 webhook）
