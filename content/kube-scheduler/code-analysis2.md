# kube-scheduler源码分析二之schedulerOne调度逻辑

在本节主要讲述schedulerOne的基本调度流程，其中用到的预选调度策略、优选调度策略将在后几节介绍。

scheduler源码存放的另一个文件夹：

`/pkg/scheduler/`，包含scheduler的核心代码，执行scheduler的调度逻辑。文件机构如下：

```shell
scheduler
├── algorithm     # 包含scheduler的调度算法
│   ├── BUILD
│   ├── doc.go
│   ├── predicates     # 预选策略
│   ├── priorities     # 优选策略
│   ├── scheduler_interface.go     # 定义SchedulerExtender接口
│   └── types.go
├── algorithm_factory.go
├── algorithm_factory_test.go
├── algorithmprovider
│   ├── BUILD
│   ├── defaults     # 初始化默认算法，包括预选和优选策略
│   ├── plugins.go     # 通过feature gates 应用算法
│   ├── plugins_test.go
│   ├── registry.go     # 注册表：是所有可用的algorithm providers的集合
│   └── registry_test.go
├── api
│   ├── BUILD
│   └── well_known_labels.go     # 外部云供应商在node上设置taint
├── apis
│   ├── config     # kubescheduler调度逻辑所需要的配置
│   └── extender
├── BUILD
├── core     # scheduler的核心代码
│   ├── BUILD
│   ├── extender.go     # 用户配置extender的一系列函数
│   ├── extender_test.go
│   ├── generic_scheduler.go     # 包含调度器的调度逻辑，后面会详细介绍
│   └── generic_scheduler_test.go
├── eventhandlers.go
├── eventhandlers_test.go
├── factory.go
├── factory_test.go
├── framework     # framework框架
│   ├── BUILD
│   ├── plugins     # 包含一系列的plugins，用于校验和过滤
│   └── v1alpha1     # framework的架构设计，包括配置参数及调用plugins
├── internal     # scheduler调度时，使用到的内部资源或工具
│   ├── cache     # scheduler 缓存
│   ├── heap     # heap 主要作用于items
│   └── queue     # 队列，在pod调度前，在队列中排序，通过pop推出pod进行调度
├── listers     # 获取pod和node的信息及表单list
│   ├── BUILD
│   ├── fake
│   ├── listers.go
│   └── listers_test.go
├── metrics     # 一系列指标，与prometheus交互使用
│   ├── BUILD
│   ├── metric_recorder.go
│   ├── metric_recorder_test.go
│   └── metrics.go
├── nodeinfo     # 节点信息，包括节点上已有的pod、volume、taint、resource等
│   ├── BUILD
│   ├── host_ports.go
│   ├── host_ports_test.go
│   ├── node_info.go
│   ├── node_info_test.go
│   └── snapshot    # 为节点创建快照
├── OWNERS
├── scheduler.go     # sched.Run的入口函数及schedulerOne的调度逻辑
├── scheduler_test.go
├── testing     # 测试
│   ├── BUILD
│   ├── framework_helpers.go
│   ├── workload_prep.go
│   └── wrappers.go
├── util
│   ├── BUILD
│   ├── clock.go
│   ├── error_channel.go
│   ├── error_channel_test.go
│   ├── utils.go
│   └── utils_test.go
└── volumebinder     # 绑定 volume
    ├── BUILD
    └── volume_binder.go

```

## 1. sched.Run

> 代码在`pkg/scheduler/scheduler.go`

等待缓存同步后，开始scheduler调度逻辑，此处为具体调度逻辑的入口，代码如下：

```go
// Run begins watching and scheduling. It waits for cache to be synced, then starts scheduling and blocked until the context is done.
func (sched *Scheduler) Run(ctx context.Context) {
	if !cache.WaitForCacheSync(ctx.Done(), sched.scheduledPodsHasSynced) {
		return
	}

	wait.UntilWithContext(ctx, sched.scheduleOne, 0)
}
```

第3行，调用`cache.WaitForCacheSync`函数，遍历`cacheSyncs`并使用bool值来判断同步是否完成，代码在`staging/src/k8s.io/client-go/tools/cache/shared_informer.go`，如下：

```go
// WaitForCacheSync waits for caches to populate.  It returns true if it was successful, false
// if the controller should shutdown
// callers should prefer WaitForNamedCacheSync()
func WaitForCacheSync(stopCh <-chan struct{}, cacheSyncs ...InformerSynced) bool {
	err := wait.PollImmediateUntil(syncedPollPeriod,
		func() (bool, error) {
			for _, syncFunc := range cacheSyncs {
				if !syncFunc() {
					return false, nil
				}
			}
			return true, nil
		},
		stopCh)
	if err != nil {
		klog.V(2).Infof("stop requested")
		return false
	}

	klog.V(4).Infof("caches populated")
	return true
}
```

在同一文件下，`controller.WaitForNamedCacheSync`是对`cache.WaitForCacheSync`的一层封装，当`cache.WaitForCacheSync`函数同步失败时，找出不能同步缓存的cotroller名称，记录不同cotroller的缓存同步的日志。

`controller.WaitForNamedCacheSync`的代码如下：

```go
// WaitForNamedCacheSync is a wrapper around WaitForCacheSync that generates log messages
// indicating that the caller identified by name is waiting for syncs, followed by
// either a successful or failed sync.
func WaitForNamedCacheSync(controllerName string, stopCh <-chan struct{}, cacheSyncs ...InformerSynced) bool {
	klog.Infof("Waiting for caches to sync for %s", controllerName)

	if !WaitForCacheSync(stopCh, cacheSyncs...) {
		utilruntime.HandleError(fmt.Errorf("unable to sync caches for %s", controllerName))
		return false
	}

	klog.Infof("Caches are synced for %s ", controllerName)
	return true
}
```

第7行`sched.scheduleOne`，scheduler的调度逻辑，在标题2详细介绍。

~~第六行`sched.SchedulingQueue.Run()`，使用队列存储pod，并开启goroutines管理队列~~

~~第八行`sched.SchedulingQueue.Close()`，关闭SchedulerQueue，等待队列 pop items，goroutine正常退出。~~

~~这里与queue相关的函数和接口在`/pkg/scheduler/internal/queue/scheduling_queue.go`。~~

## 2. sched.scheduleOne

> 代码在`/pkg/scheduler/scheduler.go`

`scheduleOne()`函数是对pod调度的完整逻辑：

1. 先从队列中使用pop方式弹出需要调度的pod
2. 通过具体的调度策略（预选和优选策略）为该pod筛选出合适的节点
3. 如果上述调度策略失败，则执行抢占式调度逻辑，经过这一系列的操作后选出最佳节点。
4. 将pod设置为assumed状态（与选中的节点进行假性绑定），并执行reserve操作（在选中的节点上为该pod预留资源）
5. 在假性绑定后，继续调度其他的pod。这里注意：pod的调度是同步的，即同一时间只能调度一个pod;而在pod的绑定阶段是异步的,即同一时间可以同时绑定多个pod
6. 调用`sched.bind()`函数，执行真实绑定，将pod调度到选中的节点上，交给kubelet进行初始化和管理。
7. 绑定结果返回后，将通知cache该pod的绑定已经结束并将结果反馈给apiserver；如果绑定失败，从缓存中删除该pod，并触发unreserve机制，释放节点中为该pod预留的资源。

在这个调度逻辑中，还穿插着不同的plugins对pod与node进行过滤，包括QueueSortPlugin、scorePlugins、reservePlugins等。

schedulerOne的具体代码如下：

```go
// scheduleOne does the entire scheduling workflow for a single pod.  It is serialized on the scheduling algorithm's host fitting.
func (sched *Scheduler) scheduleOne(ctx context.Context) {
	fwk := sched.Framework

	podInfo := sched.NextPod()
	// pod could be nil when schedulerQueue is closed
	if podInfo == nil || podInfo.Pod == nil {
		return
	}
	pod := podInfo.Pod
	if pod.DeletionTimestamp != nil {
		sched.Recorder.Eventf(pod, nil, v1.EventTypeWarning, "FailedScheduling", "Scheduling", "skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		klog.V(3).Infof("Skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		return
	}

	klog.V(3).Infof("Attempting to schedule pod: %v/%v", pod.Namespace, pod.Name)

	// Synchronously attempt to find a fit for the pod.
	start := time.Now()
	state := framework.NewCycleState()
	state.SetRecordFrameworkMetrics(rand.Intn(100) < frameworkMetricsSamplePercent)
	schedulingCycleCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	scheduleResult, err := sched.Algorithm.Schedule(schedulingCycleCtx, state, pod)
	if err != nil {
		sched.recordSchedulingFailure(podInfo.DeepCopy(), err, v1.PodReasonUnschedulable, err.Error())
		// Schedule() may have failed because the pod would not fit on any host, so we try to
		// preempt, with the expectation that the next time the pod is tried for scheduling it
		// will fit due to the preemption. It is also possible that a different pod will schedule
		// into the resources that were preempted, but this is harmless.
		if fitError, ok := err.(*core.FitError); ok {
			if sched.DisablePreemption {
				klog.V(3).Infof("Pod priority feature is not enabled or preemption is disabled by scheduler configuration." +
					" No preemption is performed.")
			} else {
				preemptionStartTime := time.Now()
				sched.preempt(schedulingCycleCtx, state, fwk, pod, fitError)
				metrics.PreemptionAttempts.Inc()
				metrics.SchedulingAlgorithmPreemptionEvaluationDuration.Observe(metrics.SinceInSeconds(preemptionStartTime))
				metrics.DeprecatedSchedulingAlgorithmPreemptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
				metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
				metrics.DeprecatedSchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
			}
			// Pod did not fit anywhere, so it is counted as a failure. If preemption
			// succeeds, the pod should get counted as a success the next time we try to
			// schedule it. (hopefully)
			metrics.PodScheduleFailures.Inc()
		} else {
			klog.Errorf("error selecting node for pod: %v", err)
			metrics.PodScheduleErrors.Inc()
		}
		return
	}
	metrics.SchedulingAlgorithmLatency.Observe(metrics.SinceInSeconds(start))
	metrics.DeprecatedSchedulingAlgorithmLatency.Observe(metrics.SinceInMicroseconds(start))
	// Tell the cache to assume that a pod now is running on a given node, even though it hasn't been bound yet.
	// This allows us to keep scheduling without waiting on binding to occur.
	assumedPodInfo := podInfo.DeepCopy()
	assumedPod := assumedPodInfo.Pod

	// Assume volumes first before assuming the pod.
	//
	// If all volumes are completely bound, then allBound is true and binding will be skipped.
	//
	// Otherwise, binding of volumes is started after the pod is assumed, but before pod binding.
	//
	// This function modifies 'assumedPod' if volume binding is required.
	allBound, err := sched.VolumeBinder.Binder.AssumePodVolumes(assumedPod, scheduleResult.SuggestedHost)
	if err != nil {
		sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError,
			fmt.Sprintf("AssumePodVolumes failed: %v", err))
		metrics.PodScheduleErrors.Inc()
		return
	}

	// Run "reserve" plugins.
	if sts := fwk.RunReservePlugins(schedulingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost); !sts.IsSuccess() {
		sched.recordSchedulingFailure(assumedPodInfo, sts.AsError(), SchedulerError, sts.Message())
		metrics.PodScheduleErrors.Inc()
		return
	}

	// assume modifies `assumedPod` by setting NodeName=scheduleResult.SuggestedHost
	err = sched.assume(assumedPod, scheduleResult.SuggestedHost)
	if err != nil {
		// This is most probably result of a BUG in retrying logic.
		// We report an error here so that pod scheduling can be retried.
		// This relies on the fact that Error will check if the pod has been bound
		// to a node and if so will not add it back to the unscheduled pods queue
		// (otherwise this would cause an infinite loop).
		sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError, fmt.Sprintf("AssumePod failed: %v", err))
		metrics.PodScheduleErrors.Inc()
		// trigger un-reserve plugins to clean up state associated with the reserved Pod
		fwk.RunUnreservePlugins(schedulingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
		return
	}
	// bind the pod to its host asynchronously (we can do this b/c of the assumption step above).
	go func() {
		bindingCycleCtx, cancel := context.WithCancel(ctx)
		defer cancel()
		metrics.SchedulerGoroutines.WithLabelValues("binding").Inc()
		defer metrics.SchedulerGoroutines.WithLabelValues("binding").Dec()

		// Run "permit" plugins.
		permitStatus := fwk.RunPermitPlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
		if !permitStatus.IsSuccess() {
			var reason string
			if permitStatus.IsUnschedulable() {
				metrics.PodScheduleFailures.Inc()
				reason = v1.PodReasonUnschedulable
			} else {
				metrics.PodScheduleErrors.Inc()
				reason = SchedulerError
			}
			if forgetErr := sched.Cache().ForgetPod(assumedPod); forgetErr != nil {
				klog.Errorf("scheduler cache ForgetPod failed: %v", forgetErr)
			}
			// trigger un-reserve plugins to clean up state associated with the reserved Pod
			fwk.RunUnreservePlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
			sched.recordSchedulingFailure(assumedPodInfo, permitStatus.AsError(), reason, permitStatus.Message())
			return
		}

		// Bind volumes first before Pod
		if !allBound {
			err := sched.bindVolumes(assumedPod)
			if err != nil {
				sched.recordSchedulingFailure(assumedPodInfo, err, "VolumeBindingFailed", err.Error())
				metrics.PodScheduleErrors.Inc()
				// trigger un-reserve plugins to clean up state associated with the reserved Pod
				fwk.RunUnreservePlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
				return
			}
		}

		// Run "prebind" plugins.
		preBindStatus := fwk.RunPreBindPlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
		if !preBindStatus.IsSuccess() {
			var reason string
			metrics.PodScheduleErrors.Inc()
			reason = SchedulerError
			if forgetErr := sched.Cache().ForgetPod(assumedPod); forgetErr != nil {
				klog.Errorf("scheduler cache ForgetPod failed: %v", forgetErr)
			}
			// trigger un-reserve plugins to clean up state associated with the reserved Pod
			fwk.RunUnreservePlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
			sched.recordSchedulingFailure(assumedPodInfo, preBindStatus.AsError(), reason, preBindStatus.Message())
			return
		}

		err := sched.bind(bindingCycleCtx, assumedPod, scheduleResult.SuggestedHost, state)
		metrics.E2eSchedulingLatency.Observe(metrics.SinceInSeconds(start))
		metrics.DeprecatedE2eSchedulingLatency.Observe(metrics.SinceInMicroseconds(start))
		if err != nil {
			metrics.PodScheduleErrors.Inc()
			// trigger un-reserve plugins to clean up state associated with the reserved Pod
			fwk.RunUnreservePlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
			sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError, fmt.Sprintf("Binding rejected: %v", err))
		} else {
			// Calculating nodeResourceString can be heavy. Avoid it if klog verbosity is below 2.
			if klog.V(2) {
				klog.Infof("pod %v/%v is bound successfully on node %q, %d nodes evaluated, %d nodes were found feasible.", assumedPod.Namespace, assumedPod.Name, scheduleResult.SuggestedHost, scheduleResult.EvaluatedNodes, scheduleResult.FeasibleNodes)
			}

			metrics.PodScheduleSuccesses.Inc()
			metrics.PodSchedulingAttempts.Observe(float64(podInfo.Attempts))
			metrics.PodSchedulingDuration.Observe(metrics.SinceInSeconds(podInfo.InitialAttemptTimestamp))

			// Run "postbind" plugins.
			fwk.RunPostBindPlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
		}
	}()
}
```

`scheduleOne()`函数中使用了很多plugins，这里不做详细介绍。下面是对该函数的的重要代码进行分析：

## 3. sched.Framework

第3行，`fwk := sched.Framework`是声明一些与scheduler相关的plugins作为扩展点

## 4. NextPod

第5行，`sched.NextPod()`，pod通过queue的方式进行存储，NextPod用来取出下一个待调度的pod。pod的调度队列也是一个核心知识点，将在后续介绍。

```go
podInfo := sched.NextPod()
	// pod could be nil when schedulerQueue is closed
	if podInfo == nil || podInfo.Pod == nil {
		return
	}
	pod := podInfo.Pod
	if pod.DeletionTimestamp != nil {
		sched.Recorder.Eventf(pod, nil, v1.EventTypeWarning, "FailedScheduling", "Scheduling", "skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		klog.V(3).Infof("Skip schedule deleting pod: %v/%v", pod.Namespace, pod.Name)
		return
	}
```

其中：在第7行，`pod.DeletionTimestamp`，检查要调度的pod的时间戳，如果pod的`DeletionTimestamp`不为空，则直接返回，因为这个pod已经被下达了删除命令，不需要进行调度。

### 5. 设定预选的节点数量

在第19行，代码如下：

```go
// Synchronously attempt to find a fit for the pod.
	start := time.Now()
	state := framework.NewCycleState()
	state.SetRecordFrameworkMetrics(rand.Intn(100) < frameworkMetricsSamplePercent)
	schedulingCycleCtx, cancel := context.WithCancel(ctx)
	defer cancel()
```

在开始调度pod之前，先设置筛选出节点的容量，这种做法是为了避免：当集群内的节点过多时，将所有节点过滤一遍，浪费资源和时间。可以看到代码里使用的percent（百分比）的概念，进入到`frameworkMetricsSamplePercent`常量后，可以发现：

```go
// Percentage of framework metrics to be sampled.
	frameworkMetricsSamplePercent = 10
```

这里将节点的筛选百分比设置成百分之十，有以下几种情况：

1. 当节点数过多并超过100时，只筛选这些节点总数的百分之十作为最后筛选出的节点。
2. 当节点数小于100时，则将所有节点筛选一遍

## 6. sched.Algorithm.Schedule

第25行，此处是scheduelr两个调度策略（预选和优选策略）的核心逻辑。

> 代码在`/pkg/scheduler/core/generic_scheduler.go`

`sched.Algorithm.Schedule（）`函数的具体代码实现如下：

```go
// Schedule tries to schedule the given pod to one of the nodes in the node list.
// If it succeeds, it will return the name of the node.
// If it fails, it will return a FitError error with reasons.
func (g *genericScheduler) Schedule(ctx context.Context, state *framework.CycleState, pod *v1.Pod) (result ScheduleResult, err error) {
	trace := utiltrace.New("Scheduling", utiltrace.Field{Key: "namespace", Value: pod.Namespace}, utiltrace.Field{Key: "name", Value: pod.Name})
	defer trace.LogIfLong(100 * time.Millisecond)

	if err := podPassesBasicChecks(pod, g.pvcLister); err != nil {
		return result, err
	}
	trace.Step("Basic checks done")

	if err := g.snapshot(); err != nil {
		return result, err
	}
	trace.Step("Snapshoting scheduler cache and node infos done")

	if len(g.nodeInfoSnapshot.NodeInfoList) == 0 {
		return result, ErrNoNodesAvailable
	}

	// Run "prefilter" plugins.
	preFilterStatus := g.framework.RunPreFilterPlugins(ctx, state, pod)
	if !preFilterStatus.IsSuccess() {
		return result, preFilterStatus.AsError()
	}
	trace.Step("Running prefilter plugins done")

	startPredicateEvalTime := time.Now()
	filteredNodes, failedPredicateMap, filteredNodesStatuses, err := g.findNodesThatFit(ctx, state, pod)
	if err != nil {
		return result, err
	}
	trace.Step("Computing predicates done")

	// Run "postfilter" plugins.
	postfilterStatus := g.framework.RunPostFilterPlugins(ctx, state, pod, filteredNodes, filteredNodesStatuses)
	if !postfilterStatus.IsSuccess() {
		return result, postfilterStatus.AsError()
	}

	if len(filteredNodes) == 0 {
		return result, &FitError{
			Pod:                   pod,
			NumAllNodes:           len(g.nodeInfoSnapshot.NodeInfoList),
			FailedPredicates:      failedPredicateMap,
			FilteredNodesStatuses: filteredNodesStatuses,
		}
	}
	trace.Step("Running postfilter plugins done")
	metrics.SchedulingAlgorithmPredicateEvaluationDuration.Observe(metrics.SinceInSeconds(startPredicateEvalTime))
	metrics.DeprecatedSchedulingAlgorithmPredicateEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPredicateEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PredicateEvaluation).Observe(metrics.SinceInSeconds(startPredicateEvalTime))
	metrics.DeprecatedSchedulingLatency.WithLabelValues(metrics.PredicateEvaluation).Observe(metrics.SinceInSeconds(startPredicateEvalTime))

	startPriorityEvalTime := time.Now()
	// When only one node after predicate, just use it.
	if len(filteredNodes) == 1 {
		metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInSeconds(startPriorityEvalTime))
		metrics.DeprecatedSchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
		return ScheduleResult{
			SuggestedHost:  filteredNodes[0].Name,
			EvaluatedNodes: 1 + len(failedPredicateMap) + len(filteredNodesStatuses),
			FeasibleNodes:  1,
		}, nil
	}

	metaPrioritiesInterface := g.priorityMetaProducer(pod, filteredNodes, g.nodeInfoSnapshot)
	priorityList, err := g.prioritizeNodes(ctx, state, pod, metaPrioritiesInterface, filteredNodes)
	if err != nil {
		return result, err
	}

	metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInSeconds(startPriorityEvalTime))
	metrics.DeprecatedSchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
	metrics.SchedulingLatency.WithLabelValues(metrics.PriorityEvaluation).Observe(metrics.SinceInSeconds(startPriorityEvalTime))
	metrics.DeprecatedSchedulingLatency.WithLabelValues(metrics.PriorityEvaluation).Observe(metrics.SinceInSeconds(startPriorityEvalTime))

	host, err := g.selectHost(priorityList)
	trace.Step("Prioritizing done")

	return ScheduleResult{
		SuggestedHost:  host,
		EvaluatedNodes: len(filteredNodes) + len(failedPredicateMap) + len(filteredNodesStatuses),
		FeasibleNodes:  len(filteredNodes),
	}, err
}
```

接下来对`Scheduler()`函数中的重要代码进行分析

### 6.1 podPassesBasicChecks

第8行，podPassesBasicChecks对pod进行一些基本检查，目前只对pvc（PersistentVolumeClaim）进行检查。

```go
if err := podPassesBasicChecks(pod, g.pvcLister); err != nil {
		return result, err
	}
	trace.Step("Basic checks done")
```

`podPassesBasicChecks()`函数的具体实现如下：

```go
// podPassesBasicChecks makes sanity checks on the pod if it can be scheduled.
func podPassesBasicChecks(pod *v1.Pod, pvcLister corelisters.PersistentVolumeClaimLister) error {
	// Check PVCs used by the pod
	namespace := pod.Namespace
	manifest := &(pod.Spec)
	for i := range manifest.Volumes {
		volume := &manifest.Volumes[i]
		if volume.PersistentVolumeClaim == nil {
			// Volume is not a PVC, ignore
			continue
		}
		pvcName := volume.PersistentVolumeClaim.ClaimName
		pvc, err := pvcLister.PersistentVolumeClaims(namespace).Get(pvcName)
		if err != nil {
			// The error has already enough context ("persistentvolumeclaim "myclaim" not found")
			return err
		}

		if pvc.DeletionTimestamp != nil {
			return fmt.Errorf("persistentvolumeclaim %q is being deleted", pvc.Name)
		}
	}

	return nil
}

```

### 6.2 snapshot

第13行，`snapshot()`将遍历cache中的所有node，更新node的信息，包括：cache NodeInfo and NodeTree order。此snapshot作用于所有预选和优选函数

```go
if err := g.snapshot(); err != nil {
		return result, err
	}
	trace.Step("Snapshoting scheduler cache and node infos done")
```

`snapshot()`函数的具体实现如下：

```go
// snapshot snapshots scheduler cache and node infos for all fit and priority
// functions.
func (g *genericScheduler) snapshot() error {
	// Used for all fit and priority funcs.
	return g.cache.UpdateNodeInfoSnapshot(g.nodeInfoSnapshot)
}
```

### 6.4 NodeInfoList

第18行，对node的列表长度进行判断，检查是否有可用的节点。

```go
if len(g.nodeInfoSnapshot.NodeInfoList) == 0 {
		return result, ErrNoNodesAvailable
	}
```

### 6.5 findNodesThatFit

> 具体`findNodesThatFit`的代码细节将在后续的独立文章中分析

第30行，`g.findNodesThatFit()`函数是预选策略的调度逻辑。

```go
startPredicateEvalTime := time.Now()
	filteredNodes, failedPredicateMap, filteredNodesStatuses, err := g.findNodesThatFit(ctx, state, pod)
	if err != nil {
		return result, err
	}
	trace.Step("Computing predicates done")
```

### 6.6 prioritizeNodes

> 具体`prioritizeNodes`的代码细节将在后续的独立文章中分析

第56行，`g.priorityMetaProducer()`函数是优选策略的调度逻辑，优选策略是对预选出的节点进行二次筛选，

```go
startPriorityEvalTime := time.Now()
	// When only one node after predicate, just use it.
	if len(filteredNodes) == 1 {
		metrics.SchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInSeconds(startPriorityEvalTime))
		metrics.DeprecatedSchedulingAlgorithmPriorityEvaluationDuration.Observe(metrics.SinceInMicroseconds(startPriorityEvalTime))
		return ScheduleResult{
			SuggestedHost:  filteredNodes[0].Name,
			EvaluatedNodes: 1 + len(failedPredicateMap) + len(filteredNodesStatuses),
			FeasibleNodes:  1,
		}, nil
	}

	metaPrioritiesInterface := g.priorityMetaProducer(pod, filteredNodes, g.nodeInfoSnapshot)
	priorityList, err := g.prioritizeNodes(ctx, state, pod, metaPrioritiesInterface, filteredNodes)
	if err != nil {
		return result, err
	}
```

其中：

第3行，对预选出的节点进行判断：当节点的个数为1时，直接使用这个节点，就不需要再进行优选策略了，这是检验的正常逻辑。

第14行，这里返回的值是`priorityList`，表明优选策略选出的是包含多个最佳节点的列表，而不是选出唯一的一个节点，优选策略是通过score的计算来对节点进行过滤的。

### 6.7 selectHost

第79行，`g.selectHost()`函数的参数为`priorityList`，即优选策略选出的最佳节点的列表。selectHost从这个列表出选出分数最高的节点，作为最后pod绑定的节点。当有多个节点的分数相同时，在k8s中定义了一个更详细的选择算法，这里就不叙述了。

```go
host, err := g.selectHost(priorityList)
	trace.Step("Prioritizing done")
```

`selectHost()`函数的具体实现为：

```go
// selectHost takes a prioritized list of nodes and then picks one
// in a reservoir sampling manner from the nodes that had the highest score.
func (g *genericScheduler) selectHost(nodeScoreList framework.NodeScoreList) (string, error) {
	if len(nodeScoreList) == 0 {
		return "", fmt.Errorf("empty priorityList")
	}
	maxScore := nodeScoreList[0].Score
	selected := nodeScoreList[0].Name
	cntOfMaxScore := 1
	for _, ns := range nodeScoreList[1:] {
		if ns.Score > maxScore {
			maxScore = ns.Score
			selected = ns.Name
			cntOfMaxScore = 1
		} else if ns.Score == maxScore {
			cntOfMaxScore++
			if rand.Intn(cntOfMaxScore) == 0 {
				// Replace the candidate with probability of 1/cntOfMaxScore
				selected = ns.Name
			}
		}
	}
	return selected, nil
}
```

这个函数的逻辑就是对节点的分数进行比较，最后选出节点分数最高的那个节点，返回结果。

## 7.sched.preempt

> 具体的`sched.preempt`的代码细节将在后续的文章单独分析

第37行，`sched.preempt()`函数是抢占逻辑的实现。当预选和优选策略均失败时，就会进行抢占式调度，将某个节点上的低优先级的pod驱逐，将优先级更高的pod调度到这个节点上。

```go
	if err != nil {
		sched.recordSchedulingFailure(podInfo.DeepCopy(), err, v1.PodReasonUnschedulable, err.Error())
		// Schedule() may have failed because the pod would not fit on any host, so we try to
		// preempt, with the expectation that the next time the pod is tried for scheduling it
		// will fit due to the preemption. It is also possible that a different pod will schedule
		// into the resources that were preempted, but this is harmless.
		if fitError, ok := err.(*core.FitError); ok {
			if sched.DisablePreemption {
				klog.V(3).Infof("Pod priority feature is not enabled or preemption is disabled by scheduler configuration." +
					" No preemption is performed.")
			} else {
				preemptionStartTime := time.Now()
				sched.preempt(schedulingCycleCtx, state, fwk, pod, fitError)
				metrics.PreemptionAttempts.Inc()
				metrics.SchedulingAlgorithmPreemptionEvaluationDuration.Observe(metrics.SinceInSeconds(preemptionStartTime))
				metrics.DeprecatedSchedulingAlgorithmPreemptionEvaluationDuration.Observe(metrics.SinceInMicroseconds(preemptionStartTime))
				metrics.SchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
				metrics.DeprecatedSchedulingLatency.WithLabelValues(metrics.PreemptionEvaluation).Observe(metrics.SinceInSeconds(preemptionStartTime))
			}
			// Pod did not fit anywhere, so it is counted as a failure. If preemption
			// succeeds, the pod should get counted as a success the next time we try to
			// schedule it. (hopefully)
			metrics.PodScheduleFailures.Inc()
		} else {
			klog.Errorf("error selecting node for pod: %v", err)
			metrics.PodScheduleErrors.Inc()
		}
		return
```

## 8. sched.assume

第85行，`sched.assume()`函数对pod假性绑定，是pod在bind行为真正发生前的状态，与bind操作异步，从而让调度器不用等待耗时的bind操作返回结果，提升调度器的效率。在assume pod执行时，还穿插着assume pod volumes、bind volumes等逻辑。

此处的代码如下：

```go
// Tell the cache to assume that a pod now is running on a given node, even though it hasn't been bound yet.
	// This allows us to keep scheduling without waiting on binding to occur.
	assumedPodInfo := podInfo.DeepCopy()
	assumedPod := assumedPodInfo.Pod

	// Assume volumes first before assuming the pod.
	//
	// If all volumes are completely bound, then allBound is true and binding will be skipped.
	//
	// Otherwise, binding of volumes is started after the pod is assumed, but before pod binding.
	//
	// This function modifies 'assumedPod' if volume binding is required.
	allBound, err := sched.VolumeBinder.Binder.AssumePodVolumes(assumedPod, scheduleResult.SuggestedHost)
	if err != nil {
		sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError,
			fmt.Sprintf("AssumePodVolumes failed: %v", err))
		metrics.PodScheduleErrors.Inc()
		return
	}

	// Run "reserve" plugins.
	if sts := fwk.RunReservePlugins(schedulingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost); !sts.IsSuccess() {
		sched.recordSchedulingFailure(assumedPodInfo, sts.AsError(), SchedulerError, sts.Message())
		metrics.PodScheduleErrors.Inc()
		return
	}

	// assume modifies `assumedPod` by setting NodeName=scheduleResult.SuggestedHost
	err = sched.assume(assumedPod, scheduleResult.SuggestedHost)
	if err != nil {
		// This is most probably result of a BUG in retrying logic.
		// We report an error here so that pod scheduling can be retried.
		// This relies on the fact that Error will check if the pod has been bound
		// to a node and if so will not add it back to the unscheduled pods queue
		// (otherwise this would cause an infinite loop).
		sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError, fmt.Sprintf("AssumePod failed: %v", err))
		metrics.PodScheduleErrors.Inc()
		// trigger un-reserve plugins to clean up state associated with the reserved Pod
		fwk.RunUnreservePlugins(schedulingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
		return
	}
	// bind the pod to its host asynchronously (we can do this b/c of the assumption step above).
	go func() {
		bindingCycleCtx, cancel := context.WithCancel(ctx)
		defer cancel()
		metrics.SchedulerGoroutines.WithLabelValues("binding").Inc()
		defer metrics.SchedulerGoroutines.WithLabelValues("binding").Dec()
```

其中具体的代码分析如下：

### 8.1 assumedPodInfo

第3行，`assumedPodInfo`将pod和它假性绑定的nodeName存入到scheduler cache 中，方便继续执行调度逻辑。

### 8.2 AssumePodVolumes

第13行，`sched.VolumeBinder.Binder.AssumePodVolumes()`函数是在pod假性绑定前，对pod上的volumes先进行假性绑定。注释写的很清楚：volumes的绑定发生在pod假性绑定之后，pod真实bind之前。代码如下：

```go
	// Assume volumes first before assuming the pod.
	//
	// If all volumes are completely bound, then allBound is true and binding will be skipped.
	//
	// Otherwise, binding of volumes is started after the pod is assumed, but before pod binding.
	//
	// This function modifies 'assumedPod' if volume binding is required.
	allBound, err := sched.VolumeBinder.Binder.AssumePodVolumes(assumedPod, scheduleResult.SuggestedHost)
	if err != nil {
		sched.recordSchedulingFailure(assumedPodInfo, err, SchedulerError,
			fmt.Sprintf("AssumePodVolumes failed: %v", err))
		metrics.PodScheduleErrors.Inc()
		return
	}
```

具体来说，这里总共与四种状态，assume volumes(假性绑定volumes)、assume pod(假性绑定pod)、bind volumes(真实绑定volumes)、bind pod(真实绑定pod)。这四个状态的执行顺序为：

assume volumes -> assume pod -> bind volumes -> bind pod

### 8.3 RunReservePlugins

第21行，`fwk.RunReservePlugins()`函数运行reserve插件，使pod将要绑定的节点为该pod预留出它所需要的资源。该事件发生在调度器将pod绑定到节点之前，目的是避免调度器在等待 pod 与节点绑定的过程中调度新的 Pod 到节点上(因为绑定pod到节点上是异步操作)，发生实际使用资源超出可用资源的情况。

### 8.4 assume

第29行，`sched.assume()`对pod假性绑定，将scheduler cache中pod的nodeName设置成scheduleResult.SuggestedHost（最后调度结果：节点的host）。

`sched.assume()`函数的具体代码实现：

```go
// assume signals to the cache that a pod is already in the cache, so that binding can be asynchronous.
// assume modifies `assumed`.
func (sched *Scheduler) assume(assumed *v1.Pod, host string) error {
	// Optimistically assume that the binding will succeed and send it to apiserver
	// in the background.
	// If the binding fails, scheduler will release resources allocated to assumed pod
	// immediately.
	assumed.Spec.NodeName = host

	if err := sched.SchedulerCache.AssumePod(assumed); err != nil {
		klog.Errorf("scheduler cache AssumePod failed: %v", err)
		return err
	}
	// if "assumed" is a nominated pod, we should remove it from internal cache
	if sched.SchedulingQueue != nil {
		sched.SchedulingQueue.DeleteNominatedPodIfExists(assumed)
	}

	return nil
}
```

如果假性绑定成功，将结果发送给apiserver；如果假性绑定失败，scheduler将立即释放分配给假定pod的资源

。在代码中还有一处校验，如果假定的pod是 nominated pod，将从内部缓存中删除它，nominated pod 的使用涉及到preemt（抢占策略）的逻辑，就不在这赘述了。

在假性绑定成功之后，进行pod的异步绑定操作。

## 9. sched.bindVolumes

第125行，验证所有的volumes是否绑定成功，volumes的绑定发生在pod真实绑定之前。

```go
// Bind volumes first before Pod
		if !allBound {
			err := sched.bindVolumes(assumedPod)
			if err != nil {
				sched.recordSchedulingFailure(assumedPodInfo, err, "VolumeBindingFailed", err.Error())
				metrics.PodScheduleErrors.Inc()
				// trigger un-reserve plugins to clean up state associated with the reserved Pod
				fwk.RunUnreservePlugins(bindingCycleCtx, state, assumedPod, scheduleResult.SuggestedHost)
				return
			}
		}
```

`bindVolumes()`函数的具体代码实现如下：

```go
// bindVolumes will make the API update with the assumed bindings and wait until
// the PV controller has completely finished the binding operation.
//
// If binding errors, times out or gets undone, then an error will be returned to
// retry scheduling.
func (sched *Scheduler) bindVolumes(assumed *v1.Pod) error {
	klog.V(5).Infof("Trying to bind volumes for pod \"%v/%v\"", assumed.Namespace, assumed.Name)
	err := sched.VolumeBinder.Binder.BindPodVolumes(assumed)
	if err != nil {
		klog.V(1).Infof("Failed to bind volumes for pod \"%v/%v\": %v", assumed.Namespace, assumed.Name, err)

		// Unassume the Pod and retry scheduling
		if forgetErr := sched.SchedulerCache.ForgetPod(assumed); forgetErr != nil {
			klog.Errorf("scheduler cache ForgetPod failed: %v", forgetErr)
		}

		return err
	}

	klog.V(5).Infof("Success binding volumes for pod \"%v/%v\"", assumed.Namespace, assumed.Name)
	return nil
}
```

## 10. sched.bind

第152行，`bind()`函数将assumed pod真实绑定到node上。

```go
		err := sched.bind(bindingCycleCtx, assumedPod, scheduleResult.SuggestedHost, state)
```

`bind()`函数的具体代码实现：

```go
// bind binds a pod to a given node defined in a binding object.  We expect this to run asynchronously, so we
// handle binding metrics internally.
func (sched *Scheduler) bind(ctx context.Context, assumed *v1.Pod, targetNode string, state *framework.CycleState) error {
	bindingStart := time.Now()
	bindStatus := sched.Framework.RunBindPlugins(ctx, state, assumed, targetNode)
	var err error
	if !bindStatus.IsSuccess() {
		if bindStatus.Code() == framework.Skip {
			// All bind plugins chose to skip binding of this pod, call original binding function.
			// If binding succeeds then PodScheduled condition will be updated in apiserver so that
			// it's atomic with setting host.
			err = sched.GetBinder(assumed).Bind(&v1.Binding{
				ObjectMeta: metav1.ObjectMeta{Namespace: assumed.Namespace, Name: assumed.Name, UID: assumed.UID},
				Target: v1.ObjectReference{
					Kind: "Node",
					Name: targetNode,
				},
			})
		} else {
			err = fmt.Errorf("Bind failure, code: %d: %v", bindStatus.Code(), bindStatus.Message())
		}
	}
	if finErr := sched.SchedulerCache.FinishBinding(assumed); finErr != nil {
		klog.Errorf("scheduler cache FinishBinding failed: %v", finErr)
	}
	if err != nil {
		klog.V(1).Infof("Failed to bind pod: %v/%v", assumed.Namespace, assumed.Name)
		if err := sched.SchedulerCache.ForgetPod(assumed); err != nil {
			klog.Errorf("scheduler cache ForgetPod failed: %v", err)
		}
		return err
	}

	metrics.BindingLatency.Observe(metrics.SinceInSeconds(bindingStart))
	metrics.DeprecatedBindingLatency.Observe(metrics.SinceInMicroseconds(bindingStart))
	metrics.SchedulingLatency.WithLabelValues(metrics.Binding).Observe(metrics.SinceInSeconds(bindingStart))
	metrics.DeprecatedSchedulingLatency.WithLabelValues(metrics.Binding).Observe(metrics.SinceInSeconds(bindingStart))
	sched.Recorder.Eventf(assumed, nil, v1.EventTypeNormal, "Scheduled", "Binding", "Successfully assigned %v/%v to %v", assumed.Namespace, assumed.Name, targetNode)
	return nil
}
```

其中：

第12行，如果绑定成功，调用`sched.GetBinder()`函数，像apiserver发送bind请求。apiserver将处理这个请求，发送到节点上的kubelete。由kubelet进行后续的操作，并返回结果。

第28行，如果绑定失败，调用`sched.SchedulerCache.ForgetPod()`函数，从cache中移除该assumed pod。

在绑定失败后，会触发unserver事件，将node上为该pod预留的资源释放掉。