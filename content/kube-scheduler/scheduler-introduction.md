# scheduler-introduction

Scheduler 调度器作为 k8s 三大核心组件之一，运行于控制平面节点上，主要在集群中对资源进行调度。
根据其特定的调度算法和策略将 pod 调度到最优工作节点上，实现资源的合理分配。

Scheduler 作为一个单独的程序运行，时刻监听 apiserver， 获取 PodSpec.NodeName 为空的 pod、node 列表，将 pod 绑定到节点上。
这里可以把 Scheduler 当成一个黑盒，入参是带调度的 pod 和节点的信息，经过黑盒内部的调度算法和策略处理，输出最优的节点，并把pod调度到该节点上。

## scheduler 源码主线逻辑

入口程序：cmd/kube-scheduler/scheduler.go： main() 函数

1. 创建 NewSchedulerCommand对象，启动调度服务
2. cobra 初始化

启动程序：cmd/kube-scheduler/app/server.go： Run() 函数

1. 在scheduler调度前，基于给定的配置，进行准备工作，如准备 event clients、创建 scheduler 对象等

开始调度：pkg/scheduler/scheduler.go：Run() 函数

1. 调度程序，等待缓存同步、上下文完成
2. 在步骤1完成后，开始watch(监听)和scheduler

调度流程：pkg/scheduler/scheduler.go：schedulerOne() 函数

1. scheduleOne 是对单个pod的调度的完整工作流程
2. 这里注意scheculer对pod的调度是串行逻辑的

调度算法：pkg/scheduler/core/generic_scheduler.go：scheduler() 函数

1. 将pod调度到节点列表中的一个节点上，
2. 如果成功，返回节点的名称；如果失败，返回错误信息
3. 在这个函数中除去一些 check 和 filter plugins，主要包括三个步骤：

- `g.findNodesThatFit`，即 predicates 策略
- `g.prioritizeNodes`，将 predicates 选出的节点，计算出它们的 score
- `g.selectHost`，将 score （分数）最高的节点筛选出来，并返回此节点的 name

predicates 策略：pkg/scheduler/algorithm/predicates/predicates.go

priorities 策略：pkg/scheduler/algorithm/priorities/priorities.go

注意：在这里的scheduler参数、predicates策略、priorities策略，使用的都是default（默认的），在源码中分别是：genericScheduler struct{}、defaultPredicates()、defaultPriorities()
