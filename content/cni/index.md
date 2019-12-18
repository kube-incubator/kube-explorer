## 我们在说之前不妨先了解一下什么是 CNI？CNI 又是做什么用的？我们该如何使用 CNI？

> *CNI (Container Network Interface), a Cloud Native Computing Foundation project, consists of a specification and libraries for writing 
plugins to configure network interfaces in Linux containers, along with a number of supported plugins. CNI concerns itself only with 
network connectivity of containers and removing allocated resources when the container is deleted. Because of this focus, CNI has a wide 
range of support and the specification is simple to implement*.

以上摘自 `https://github.com/containernetworking/cni/` 通俗的来说：CNI 全称叫做 `Container Network Interface` 即：**容器网络接口**，属于一个 
CNCF 项目，是一种**规范或标准和库**。用于**配置容器网络**，以及一些受支持的插件。CNI 特点就是只关心容器的网络连接，并在删除容器时删除分配的资源。正是由于这个原因，CNI 得到了广泛的支持，并且规范易于实现。
准确的来说想要实现 CNI 规范只需要实现以下接口中的内容，即：添加网络、删除网络。

```go
type CNI interface {
	AddNetworkList(ctx context.Context, net *NetworkConfigList, rt *RuntimeConf) (types.Result, error)
	CheckNetworkList(ctx context.Context, net *NetworkConfigList, rt *RuntimeConf) error
	DelNetworkList(ctx context.Context, net *NetworkConfigList, rt *RuntimeConf) error

	AddNetwork(ctx context.Context, net *NetworkConfig, rt *RuntimeConf) (types.Result, error)
	CheckNetwork(ctx context.Context, net *NetworkConfig, rt *RuntimeConf) error
	DelNetwork(ctx context.Context, net *NetworkConfig, rt *RuntimeConf) error
	GetNetworkCachedResult(net *NetworkConfig, rt *RuntimeConf) (types.Result, error)

	ValidateNetworkList(ctx context.Context, net *NetworkConfigList) ([]string, error)
	ValidateNetwork(ctx context.Context, net *NetworkConfig) ([]string, error)
}
```

**接下来我们将详细讲述 CNI**
