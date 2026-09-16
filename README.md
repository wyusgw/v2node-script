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

```
v2node instance add <name>       # 新增一个实例（交互式收集面板信息）
v2node instance list             # 列出已有实例
v2node instance start <name>     # 启动指定实例
v2node instance stop <name>      # 停止指定实例
v2node instance restart <name>   # 重启指定实例
v2node instance status <name>    # 查看指定实例状态
v2node instance log <name>       # 查看指定实例日志
v2node instance enable <name>    # 设置指定实例开机自启
v2node instance disable <name>   # 取消指定实例开机自启
v2node instance config <name>    # 编辑指定实例配置并重启
v2node instance remove <name>    # 移除一个实例（不影响默认实例和其他实例）
```

默认实例（第一次安装时生成的那个）不受影响，仍然用原本的 `v2node start` / `v2node stop` 等命令管理。也可以运行 `v2node`（不带参数）进入交互菜单，选择「管理多实例」。
