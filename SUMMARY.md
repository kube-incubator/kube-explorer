# Summary

* [引言](README.md)

* [kube-apiserver](content/kube-apiserver/index.md)

* [kube-controller-manager](content/kube-controller-manager/index.md)

* [kube-scheduler](content/kube-scheduler/index.md)

  - [scheduler 详细介绍](content/kube-scheduler/scheduler-introduction.md)

  - [入口函数-main](content/kube-scheduler/code-analysis1.md)

  - [调度逻辑-schedulerOne](content/kube-scheduler/code-analysis2.md)

  - [预选策略-findNodesThatFitPod](content/kube-scheduler/code-analysis3.md)

  - [优选策略-prioritizeNodes](content/kube-scheduler/code-analysis4.md)

  - [抢占策略-preempt](content/kube-scheduler/code-analysis5.md)

  - [informer 机制](content/kube-scheduler/informer.md)

  - [schedulingQueue 机制](content/kube-scheduler/schedulingQueue.md)
  
  - [Extension Points](content/kube-scheduler/Extension-points.md)

* [kubelet](content/kubelet/index.md)

* [kube-proxy](content/kube-proxy/index.md)

* [kubeadm](content/kubeadm/index.md)

* [kubectl](content/kubectl/index.md)
