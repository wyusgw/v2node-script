# v2node
A v2board backend base on moddified xray-core.
一个基于修改版xray内核的V2board节点服务端。

## 软件安装

### 一键安装

```
wget -N https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh && bash install.sh
```

## 多实例

同一台机器上，如果只是要接同一个面板下的多个节点，`config.json` 的 `Nodes` 本来就是数组，一个进程/一份配置里多加几笔即可，不需要用到下面的多实例功能。

多实例指的是在同一台机器上再跑一个完全独立的 v2node 进程（独立的配置文件、独立的 systemd 服务、可以分别 start/stop/restart，互不影响），适合接不同面板、或想让某个节点能单独重启而不影响其他节点的场景。共用的只有 `/usr/local/v2node/v2node` 主程序和 geoip/geosite 数据。

实例名作为可选参数直接跟在指令后面，省略实例名就是操作默认实例（第一次安装时生成的那个）：

```
v2node list                    # 列出已有实例及状态
v2node new <name>              # 新建一个实例（交互式收集面板信息）
v2node remove <name> [name...] # 移除一个或多个实例（不影响默认实例和其他实例）
v2node rename <old> <new>      # 重命名一个实例
v2node start [name]            # 启动实例，省略 name 操作默认实例
v2node stop [name]             # 停止实例
v2node restart [name]          # 重启实例
v2node status [name]           # 查看实例状态
v2node enable [name]           # 设置实例开机自启
v2node disable [name]          # 取消实例开机自启
v2node log [name] [-f]         # 查看实例日志，默认最后1000行，加 -f 持续跟随
v2node config [name]           # 编辑实例配置并自动重启
```

也可以运行 `v2node`（不带参数）进入交互菜单，选择「管理多实例」。
