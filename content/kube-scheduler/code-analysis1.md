# kube-scheduler 源码分析之入口函数

scheduler的源码主要存放在两个文件夹下：

`/cmd/kube-scheduler/`，是scheduler的入口函数，文件结构如下：

```shell
kube-scheduler
├── app          # 该目录下包含运行scheduler时所需要的配置对象和参数
│   ├── BUILD
│   ├── config           # 包含配置对象及上下文内容
│   │   ├── BUILD
│   │   └── config.go
│   ├── options         # 包含scheduler运行时需要的参数
│   │   ├── BUILD
│   │   ├── configfile.go
│   │   ├── deprecated.go
│   │   ├── deprecated_test.go
│   │   ├── insecure_serving.go
│   │   ├── insecure_serving_test.go
│   │   ├── options.go
│   │   └── options_test.go
│   ├── server.go       # 读取默认配置文件，并初始化
│   └── testing
│       ├── BUILD
│       └── testserver.go
├── BUILD
├── OWNERS
└── scheduler.go     # main入口函数
```

## 1. main 入口函数

> 代码在`/cmd/kube-scheduler/scheduler.go`

```go
func main() {
	rand.Seed(time.Now().UnixNano())

	command := app.NewSchedulerCommand()

	// TODO: once we switch everything over to Cobra commands, we can go back to calling
	// utilflag.InitFlags() (by removing its pflag.Parse() call). For now, we have to set the
	// normalize func and add the go flag set by hand.
	pflag.CommandLine.SetNormalizeFunc(cliflag.WordSepNormalizeFunc)
	// utilflag.InitFlags()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		os.Exit(1)
	}
}
```

这里使用命令行框架cobra，创建scheduler的命令对象并对命令参数进行校验。
scheduler组件代码通过cobra生成根命令和子命令来执行命令，使用 `cmd.Flags()`设置命令参数，通过调用 `command.Execute()`检验命令参数并执行。有关cobra的更多信息，请参阅[cobra](https://github.com/spf13/cobra)。

核心代码：

```go
// 1.1 使用默认的参数和配置初始化scheduler结构体
command := app.NewSchedulerCommand()
// 执行Execute，这是cobra提供的执行命令的方法（在scheduler组件的调度逻辑完成后，最后执行）
if err := command.Execute(); err != nil {
		os.Exit(1)
	}
```

## 1.1 NewSchedulerCommand()

> 代码在`/cmd/kube-scheduler/app/server.go`

NewSchedulerCommand用来初始化scheduler配置并创建SchedulerCommand对象

```go
// NewSchedulerCommand creates a *cobra.Command object with default parameters and registryOptions
func NewSchedulerCommand(registryOptions ...Option) *cobra.Command {
	opts, err := options.NewOptions()
	if err != nil {
		klog.Fatalf("unable to initialize command options: %v", err)
	}

// 为scheduler创建 cobra.Command对象，即根命令
	cmd := &cobra.Command{
		Use: "kube-scheduler",
		Long: `The Kubernetes scheduler is a policy-rich, topology-aware,
workload-specific function that significantly impacts availability, performance,
and capacity. The scheduler needs to take into account individual and collective
resource requirements, quality of service requirements, hardware/software/policy
constraints, affinity and anti-affinity specifications, data locality, inter-workload
interference, deadlines, and so on. Workload-specific requirements will be exposed
through the API as necessary.`,
		Run: func(cmd *cobra.Command, args []string) {
			if err := runCommand(cmd, args, opts, registryOptions...); err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}
		},
	}
	fs := cmd.Flags()
	namedFlagSets := opts.Flags()
	verflag.AddFlags(namedFlagSets.FlagSet("global"))
	globalflag.AddGlobalFlags(namedFlagSets.FlagSet("global"), cmd.Name())
	for _, f := range namedFlagSets.FlagSets {
		fs.AddFlagSet(f)
	}

	usageFmt := "Usage:\n  %s\n"
	cols, _, _ := term.TerminalSize(cmd.OutOrStdout())
	cmd.SetUsageFunc(func(cmd *cobra.Command) error {
		fmt.Fprintf(cmd.OutOrStderr(), usageFmt, cmd.UseLine())
		cliflag.PrintSections(cmd.OutOrStderr(), namedFlagSets, cols)
		return nil
	})
	cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		fmt.Fprintf(cmd.OutOrStdout(), "%s\n\n"+usageFmt, cmd.Long, cmd.UseLine())
		cliflag.PrintSections(cmd.OutOrStdout(), namedFlagSets, cols)
	})
	cmd.MarkFlagFilename("config", "yaml", "yml", "json")

	return cmd
}
```

核心代码

```go
// 1.1.1 NewOptions 构建并初始化scheduler需要的参数
opts, err := options.NewOptions()
// 1.1.2 完成配置的初始化，最后调用 Run()函数，
err := runCommand
```

## 1.1.1 NewOptions

> 代码在`/cmd/kube-scheduler/app/options/options.go`

NewOptions用来配置SchedulerServer需要的参数和配置，核心参数为`KubeSchedulerConfiguration`结构体（代码在`/pkg/scheduler/apis/config/types.go` ）

NewOptions的代码：

```go
// NewOptions returns default scheduler app options.
func NewOptions() (*Options, error) {
	cfg, err := newDefaultComponentConfig()
	if err != nil {
		return nil, err
	}

	hhost, hport, err := splitHostIntPort(cfg.HealthzBindAddress)
	if err != nil {
		return nil, err
	}

	o := &Options{
		ComponentConfig: *cfg,
		SecureServing:   apiserveroptions.NewSecureServingOptions().WithLoopback(),
		CombinedInsecureServing: &CombinedInsecureServingOptions{
			Healthz: (&apiserveroptions.DeprecatedInsecureServingOptions{
				BindNetwork: "tcp",
			}).WithLoopback(),
			Metrics: (&apiserveroptions.DeprecatedInsecureServingOptions{
				BindNetwork: "tcp",
			}).WithLoopback(),
			BindPort:    hport,
			BindAddress: hhost,
		},
		Authentication: apiserveroptions.NewDelegatingAuthenticationOptions(),
		Authorization:  apiserveroptions.NewDelegatingAuthorizationOptions(),
		Deprecated: &DeprecatedOptions{
			UseLegacyPolicyConfig:    false,
			PolicyConfigMapNamespace: metav1.NamespaceSystem,
		},
	}

	o.Authentication.TolerateInClusterLookupFailure = true
	o.Authentication.RemoteKubeConfigFileOptional = true
	o.Authorization.RemoteKubeConfigFileOptional = true
	o.Authorization.AlwaysAllowPaths = []string{"/healthz"}

	// Set the PairName but leave certificate directory blank to generate in-memory by default
	o.SecureServing.ServerCert.CertDirectory = ""
	o.SecureServing.ServerCert.PairName = "kube-scheduler"
	o.SecureServing.BindPort = ports.KubeSchedulerPort

	return o, nil
}
```

在第3行中的`newDefaultComponentConfig()`点进去就会发现调用的是`KubeSchedulerConfiguration`结构体

## 1.1.2 runCommand

> 代码在`/cmd/kube-scheduler/app/server.go`

代码如下：

```go
// runCommand runs the scheduler.
func runCommand(cmd *cobra.Command, args []string, opts *options.Options, registryOptions ...Option) error {
	verflag.PrintAndExitIfRequested()
	utilflag.PrintFlags(cmd.Flags())

	if len(args) != 0 {
		fmt.Fprint(os.Stderr, "arguments are not supported\n")
	}

	if errs := opts.Validate(); len(errs) > 0 {
		return utilerrors.NewAggregate(errs)
	}

	if len(opts.WriteConfigTo) > 0 {
		c := &schedulerserverconfig.Config{}
		if err := opts.ApplyTo(c); err != nil {
			return err
		}
		if err := options.WriteConfigFile(opts.WriteConfigTo, &c.ComponentConfig); err != nil {
			return err
		}
		klog.Infof("Wrote configuration to: %s\n", opts.WriteConfigTo)
		return nil
	}

	c, err := opts.Config()
	if err != nil {
		return err
	}

	// Get the completed config
	cc := c.Complete()

	// Apply algorithms based on feature gates.
	// TODO: make configurable?
	algorithmprovider.ApplyFeatureGates()

	// Configz registration.
	if cz, err := configz.New("componentconfig"); err == nil {
		cz.Set(cc.ComponentConfig)
	} else {
		return fmt.Errorf("unable to register configz: %s", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	return Run(ctx, cc, registryOptions...)
}
```

第10行，`errs := opts.Validate()`校验标题1.1.1中提到的options参数

代码如下：

```go
/ Validate validates all the required options.
func (o *Options) Validate() []error {
	var errs []error

	if err := validation.ValidateKubeSchedulerConfiguration(&o.ComponentConfig).ToAggregate(); err != nil {
		errs = append(errs, err.Errors()...)
	}
	errs = append(errs, o.SecureServing.Validate()...)
	errs = append(errs, o.CombinedInsecureServing.Validate()...)
	errs = append(errs, o.Authentication.Validate()...)
	errs = append(errs, o.Authorization.Validate()...)
	errs = append(errs, o.Deprecated.Validate()...)

	return errs
}
```

第26行，`c, err := opts.Config()`初始化scheduler的config对象

config的具体代码如下：

```go
// Config return a scheduler config object
func (o *Options) Config() (*schedulerappconfig.Config, error) {
	if o.SecureServing != nil {
		if err := o.SecureServing.MaybeDefaultWithSelfSignedCerts("localhost", nil, []net.IP{net.ParseIP("127.0.0.1")}); err != nil {
			return nil, fmt.Errorf("error creating self-signed certificates: %v", err)
		}
	}

	c := &schedulerappconfig.Config{}
	if err := o.ApplyTo(c); err != nil {
		return nil, err
	}

	// Prepare kube clients.
	client, leaderElectionClient, eventClient, err := createClients(c.ComponentConfig.ClientConnection, o.Master, c.ComponentConfig.LeaderElection.RenewDeadline.Duration)
	if err != nil {
		return nil, err
	}

	coreBroadcaster := record.NewBroadcaster()
	coreRecorder := coreBroadcaster.NewRecorder(scheme.Scheme, corev1.EventSource{Component: c.ComponentConfig.SchedulerName})

	// Set up leader election if enabled.
	var leaderElectionConfig *leaderelection.LeaderElectionConfig
	if c.ComponentConfig.LeaderElection.LeaderElect {
		leaderElectionConfig, err = makeLeaderElectionConfig(c.ComponentConfig.LeaderElection, leaderElectionClient, coreRecorder)
		if err != nil {
			return nil, err
		}
	}

	c.Client = client
	c.InformerFactory = informers.NewSharedInformerFactory(client, 0)
	c.PodInformer = scheduler.NewPodInformer(client, 0)
	c.EventClient = eventClient.EventsV1beta1()
	c.CoreEventClient = eventClient.CoreV1()
	c.CoreBroadcaster = coreBroadcaster
	c.LeaderElection = leaderElectionConfig

	return c, nil
}
```

其中主要执行以下操作：

- 第15行：构建kube clients：client、leaderElectionClient、eventClient
- 第20行：创建event broadcaster
- 第24行：设置leader election（如果开启），用来对多个scheduler进行选举
- 第33行：创建informer对象，主要包括`NewSharedInformerFactory`和`NewPodInformer`函数

第36行，`algorithmprovider.ApplyFeatureGates()`提供默认的算法，后面详细介绍

第45行和第46行：

```go
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
```

由`WithCancel()`函数返回的ctx是`context.Background()`的子context，之后在协程中select，如果stopCh可以读取，则调用`cancel()`函数。这个`cancel()`函数在`WithCancel()`中返回，作用是把context所有的children关闭并移除。

`WithCancel()`函数的代码：

```go
// WithCancel returns a copy of parent with a new Done channel. The returned
// context's Done channel is closed when the returned cancel function is called
// or when the parent context's Done channel is closed, whichever happens first.
//
// Canceling this context releases resources associated with it, so code should
// call cancel as soon as the operations running in this Context complete.
func WithCancel(parent Context) (ctx Context, cancel CancelFunc) {
	c := newCancelCtx(parent)
	propagateCancel(parent, &c)
	return &c, func() { c.cancel(true, Canceled) }
}
```

其中：第10行调用`cancel()`函数，具体代码如下

```go
// cancel closes c.done, cancels each of c's children, and, if
// removeFromParent is true, removes c from its parent's children.
func (c *cancelCtx) cancel(removeFromParent bool, err error) {
	if err == nil {
		panic("context: internal error: missing cancel error")
	}
	c.mu.Lock()
	if c.err != nil {
		c.mu.Unlock()
		return // already canceled
	}
	c.err = err
	if c.done == nil {
		c.done = closedchan
	} else {
		close(c.done)
	}
	for child := range c.children {
		// NOTE: acquiring the child's lock while holding parent's lock.
		child.cancel(false, err)
	}
	c.children = nil
	c.mu.Unlock()

	if removeFromParent {
		removeChild(c.Context, c)
	}
}  
```

第48行：

1. `return Run(ctx, cc, registryOptions...)`调用了`Run`函数（启动程序）
2. 接着此`Run`函数调用了`sched.Run(ctx)`（在下一节代码的106行）
3. `sched.Run(ctx)这个函数`会不停的在协程中运行`schedulerOne`，对pod执行一轮一轮的调度，直到接收到stopChannel。与此同时，用ctx.Done()阻塞住run的运行，直到ctx.Done()可以读取，run才会返回。一旦run()结束，调度器也停止运作。

这3个小步骤是scheduler源码中主要函数的调用流程，下面对 Run 函数详细介绍

## 2. Run

> 代码在`/cmd/kube-scheduler/app/server.go`

在scheduler调度逻辑开始之前，Run函数将与scheduler相关的配置先运行起来

具体代码如下：

```go
// Run executes the scheduler based on the given configuration. It only returns on error or when context is done.
func Run(ctx context.Context, cc schedulerserverconfig.CompletedConfig, outOfTreeRegistryOptions ...Option) error {
	// To help debugging, immediately log version
	klog.V(1).Infof("Starting Kubernetes Scheduler version %+v", version.Get())

	outOfTreeRegistry := make(framework.Registry)
	for _, option := range outOfTreeRegistryOptions {
		if err := option(outOfTreeRegistry); err != nil {
			return err
		}
	}

	// Prepare event clients.
	if _, err := cc.Client.Discovery().ServerResourcesForGroupVersion(eventsv1beta1.SchemeGroupVersion.String()); err == nil {
		cc.Broadcaster = events.NewBroadcaster(&events.EventSinkImpl{Interface: cc.EventClient.Events("")})
		cc.Recorder = cc.Broadcaster.NewRecorder(scheme.Scheme, cc.ComponentConfig.SchedulerName)
	} else {
		recorder := cc.CoreBroadcaster.NewRecorder(scheme.Scheme, v1.EventSource{Component: cc.ComponentConfig.SchedulerName})
		cc.Recorder = record.NewEventRecorderAdapter(recorder)
	}

	// Create the scheduler.
	sched, err := scheduler.New(cc.Client,
		cc.InformerFactory,
		cc.PodInformer,
		cc.Recorder,
		ctx.Done(),
		scheduler.WithName(cc.ComponentConfig.SchedulerName),
		scheduler.WithAlgorithmSource(cc.ComponentConfig.AlgorithmSource),
		scheduler.WithHardPodAffinitySymmetricWeight(cc.ComponentConfig.HardPodAffinitySymmetricWeight),
		scheduler.WithPreemptionDisabled(cc.ComponentConfig.DisablePreemption),
		scheduler.WithPercentageOfNodesToScore(cc.ComponentConfig.PercentageOfNodesToScore),
		scheduler.WithBindTimeoutSeconds(cc.ComponentConfig.BindTimeoutSeconds),
		scheduler.WithFrameworkOutOfTreeRegistry(outOfTreeRegistry),
		scheduler.WithFrameworkPlugins(cc.ComponentConfig.Plugins),
		scheduler.WithFrameworkPluginConfig(cc.ComponentConfig.PluginConfig),
		scheduler.WithPodMaxBackoffSeconds(cc.ComponentConfig.PodMaxBackoffSeconds),
		scheduler.WithPodInitialBackoffSeconds(cc.ComponentConfig.PodInitialBackoffSeconds),
	)
	if err != nil {
		return err
	}

	// Prepare the event broadcaster.
	if cc.Broadcaster != nil && cc.EventClient != nil {
		cc.Broadcaster.StartRecordingToSink(ctx.Done())
	}
	if cc.CoreBroadcaster != nil && cc.CoreEventClient != nil {
		cc.CoreBroadcaster.StartRecordingToSink(&corev1.EventSinkImpl{Interface: cc.CoreEventClient.Events("")})
	}
	// Setup healthz checks.
	var checks []healthz.HealthChecker
	if cc.ComponentConfig.LeaderElection.LeaderElect {
		checks = append(checks, cc.LeaderElection.WatchDog)
	}

	// Start up the healthz server.
	if cc.InsecureServing != nil {
		separateMetrics := cc.InsecureMetricsServing != nil
		handler := buildHandlerChain(newHealthzHandler(&cc.ComponentConfig, separateMetrics, checks...), nil, nil)
		if err := cc.InsecureServing.Serve(handler, 0, ctx.Done()); err != nil {
			return fmt.Errorf("failed to start healthz server: %v", err)
		}
	}
	if cc.InsecureMetricsServing != nil {
		handler := buildHandlerChain(newMetricsHandler(&cc.ComponentConfig), nil, nil)
		if err := cc.InsecureMetricsServing.Serve(handler, 0, ctx.Done()); err != nil {
			return fmt.Errorf("failed to start metrics server: %v", err)
		}
	}
	if cc.SecureServing != nil {
		handler := buildHandlerChain(newHealthzHandler(&cc.ComponentConfig, false, checks...), cc.Authentication.Authenticator, cc.Authorization.Authorizer)
		// TODO: handle stoppedCh returned by c.SecureServing.Serve
		if _, err := cc.SecureServing.Serve(handler, 0, ctx.Done()); err != nil {
			// fail early for secure handlers, removing the old error loop from above
			return fmt.Errorf("failed to start secure server: %v", err)
		}
	}

	// Start all informers.
	go cc.PodInformer.Informer().Run(ctx.Done())
	cc.InformerFactory.Start(ctx.Done())

	// Wait for all caches to sync before scheduling.
	cc.InformerFactory.WaitForCacheSync(ctx.Done())

	// If leader election is enabled, runCommand via LeaderElector until done and exit.
	if cc.LeaderElection != nil {
		cc.LeaderElection.Callbacks = leaderelection.LeaderCallbacks{
			OnStartedLeading: sched.Run,
			OnStoppedLeading: func() {
				klog.Fatalf("leaderelection lost")
			},
		}
		leaderElector, err := leaderelection.NewLeaderElector(*cc.LeaderElection)
		if err != nil {
			return fmt.Errorf("couldn't create leader elector: %v", err)
		}

		leaderElector.Run(ctx)

		return fmt.Errorf("lost lease")
	}

	// Leader election is disabled, so runCommand inline until done.
	sched.Run(ctx)
	return fmt.Errorf("finished without leader elect")
}
```

主要功能如下：

- 运行event broadcaster、healthz checks、healthz server、metrics server(根据config构建一个metrics server)
- 创建scheduler结构体
- 启动所有的informer，并在调度前等待etcd中的资源数据同步到本地的store中
- 如果 leader election开启，并有多个scheduler，则进行选举，直到选举结束或退出(一般系统默认scheduler：default-scheduler)
- 运行`sched.Run`函数，执行scheduler的调度逻辑

核心源码介绍：

## 2.1 outOfTreeRegistry

第6行，创建Registry(注册表)，其中包含所有可用的plugins，并控制这些plugin的启动和初始化。这里的Registry相当于一个注册中心，只有在Registry中注册了的plugins（策略），才能在之后的scheduler调度逻辑中启动并生效。

```go
outOfTreeRegistry := make(framework.Registry)
	for _, option := range outOfTreeRegistryOptions {
		if err := option(outOfTreeRegistry); err != nil {
			return err
		}
	}
```

## 2.1.1 Registry

> 代码在`/pkg/scheduler/framework/v1alpha1/registry.go`

代码如下：

```go
// PluginFactory is a function that builds a plugin.
type PluginFactory = func(configuration *runtime.Unknown, f FrameworkHandle) (Plugin, error)

// DecodeInto decodes configuration whose type is *runtime.Unknown to the interface into.
func DecodeInto(configuration *runtime.Unknown, into interface{}) error {
	if configuration == nil || configuration.Raw == nil {
		return nil
	}

	switch configuration.ContentType {
	// If ContentType is empty, it means ContentTypeJSON by default.
	case runtime.ContentTypeJSON, "":
		return json.Unmarshal(configuration.Raw, into)
	case runtime.ContentTypeYAML:
		return yaml.Unmarshal(configuration.Raw, into)
	default:
		return fmt.Errorf("not supported content type %s", configuration.ContentType)
	}
}

// Registry is a collection of all available plugins. The framework uses a
// registry to enable and initialize configured plugins.
// All plugins must be in the registry before initializing the framework.
type Registry map[string]PluginFactory

// Register adds a new plugin to the registry. If a plugin with the same name
// exists, it returns an error.
func (r Registry) Register(name string, factory PluginFactory) error {
	if _, ok := r[name]; ok {
		return fmt.Errorf("a plugin named %v already exists", name)
	}
	r[name] = factory
	return nil
}

// Unregister removes an existing plugin from the registry. If no plugin with
// the provided name exists, it returns an error.
func (r Registry) Unregister(name string) error {
	if _, ok := r[name]; !ok {
		return fmt.Errorf("no plugin named %v exists", name)
	}
	delete(r, name)
	return nil
}

// Merge merges the provided registry to the current one.
func (r Registry) Merge(in Registry) error {
	for name, factory := range in {
		if err := r.Register(name, factory); err != nil {
			return err
		}
	}
	return nil
}
```

注释讲解很清晰，不再赘述。

## 2.2 scheduler.New

第22行，创建scheduler结构体，其中包含scheduler调度逻辑执行过程中需要的所有参数和配置。

```go
	// Create the scheduler.
	sched, err := scheduler.New(cc.Client,
		cc.InformerFactory,
		cc.PodInformer,
		cc.Recorder,
		ctx.Done(),
		scheduler.WithName(cc.ComponentConfig.SchedulerName),
		scheduler.WithAlgorithmSource(cc.ComponentConfig.AlgorithmSource),
		scheduler.WithHardPodAffinitySymmetricWeight(cc.ComponentConfig.HardPodAffinitySymmetricWeight),
		scheduler.WithPreemptionDisabled(cc.ComponentConfig.DisablePreemption),
		scheduler.WithPercentageOfNodesToScore(cc.ComponentConfig.PercentageOfNodesToScore),
		scheduler.WithBindTimeoutSeconds(cc.ComponentConfig.BindTimeoutSeconds),
		scheduler.WithFrameworkOutOfTreeRegistry(outOfTreeRegistry),
		scheduler.WithFrameworkPlugins(cc.ComponentConfig.Plugins),
		scheduler.WithFrameworkPluginConfig(cc.ComponentConfig.PluginConfig),
		scheduler.WithPodMaxBackoffSeconds(cc.ComponentConfig.PodMaxBackoffSeconds),
		scheduler.WithPodInitialBackoffSeconds(cc.ComponentConfig.PodInitialBackoffSeconds),
	)
```

其中：

- 第3行，`cc.InformerFactory`调用的是`SharedInformerFactory`接口：Shared 指的是在多个 Informer 中共享一个本地 cache。

- 第4行，`cc.PodInformer`调用的是`PodInformer`接口：基于SharedInformer的监听pod，并根据index来管理pod（当事件类型为add时，将其保存到本地缓存store中，并创建索引；当事件类型为delete时，则在本地缓存中删除此对象）

- 第5行，`cc.Recorder`调用的是`EventRecorder`接口：用来record events

- 第6行，`ctx.Done()`调用的是`Context`接口：使用一个 Done channel

- 从第7行开始到最后，调用的是`cc.ComponentConfig`中的参数，即是`KubeSchedulerConfiguration`结构体：用来配置scheduler

## 2.3 InformerFactory.Start

第80行，启动所有informers，包括PodInformer、InformerFactory，主要涉及到informer，请参阅[informer机制](https://github.com/kube-incubator/kube-explorer/blob/master/content/kube-scheduler/informer.md)

```go
	// Start all informers.
	go cc.PodInformer.Informer().Run(ctx.Done())
	cc.InformerFactory.Start(ctx.Done())
```

## 2.4 WaitForCacheSync

第84行，在调度逻辑执行前，需等到所有的caches同步

```go
	// Wait for all caches to sync before scheduling.
	cc.InformerFactory.WaitForCacheSync(ctx.Done())
```

在这一步，涉及到reflector(反射器)、apiserver、etcd、store等的关系，一并在[informer机制](https://github.com/kube-incubator/kube-explorer/blob/master/content/kube-scheduler/informer.md)中讲解

## 2.5 sched.Run

第106行，等待cache同步完成后，开始执行调度逻辑。

```go
	sched.Run(ctx)
```

Run函数的具体代码如下：

> 代码在`/pkg/scheduler/scheduler.go`

```go
// Run begins watching and scheduling. It waits for cache to be synced, then starts scheduling and blocked until the context is done.
func (sched *Scheduler) Run(ctx context.Context) {
	if !cache.WaitForCacheSync(ctx.Done(), sched.scheduledPodsHasSynced) {
		return
	}

	wait.UntilWithContext(ctx, sched.scheduleOne, 0)
}
```

以上是从入口函数开始，到执行schedulerOne逻辑之前的源码分析，sched.Run的源码分析在下一节。