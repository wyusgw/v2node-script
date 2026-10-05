# v2node
A v2board backend based on a modified xray-core.

## Installation

### One-click install

```
wget -N https://raw.githubusercontent.com/wyusgw/v2node-script/refs/heads/main/script/install.sh && bash install.sh
```

## Multiple instances

If you only need several nodes of the same panel on one machine, the `Nodes` entry of `config.json` is already an array: add more entries to one process / one config. You do not need the multi-instance feature below.

A multi-instance setup runs another fully independent v2node process on the same machine (its own config file and systemd service, started/stopped/restarted separately without affecting the others). It suits connecting to different panels, or restarting one node without touching the others. Only the `/usr/local/v2node/v2node` binary and the geoip/geosite data are shared.

The instance name is an optional argument after the command. Without it the default instance (the one created on the first install) is used:

```
v2node list                    # list the instances and their status
v2node new <name>              # create an instance (collects the panel info interactively)
v2node remove <name> [name...] # remove one or more instances (the default instance and others are not affected)
v2node rename <old> <new>      # rename an instance
v2node start [name]            # start an instance, no name = default instance
v2node stop [name]             # stop an instance
v2node restart [name]          # restart an instance
v2node status [name]           # show the instance status
v2node enable [name]           # enable autostart for an instance
v2node disable [name]          # disable autostart for an instance
v2node log [name] [-f]         # show the instance logs, last 1000 lines by default, -f to follow
v2node config [name]           # edit the instance config and restart it
```

You can also run `v2node` without arguments to open the interactive menu and choose "Manage instance".

## Install channel

The stable channel (the official release on GitHub Releases) is used by default. You can switch to the beta channel: it is the rolling build of the `dev` branch of the v2node repository (rebuilt on every push to `dev` and published over the `beta` tag). It may be unstable and is only recommended for test environments.

```
v2node channel            # show the current channel
v2node channel stable     # switch back to stable
v2node channel beta       # switch to beta
v2node update             # reinstall/update using the current channel
```

The interactive menu has a matching "Switch the install channel" entry. `install.sh` also accepts `--channel stable|beta`; when omitted, the last choice is reused (stable on the first run).
