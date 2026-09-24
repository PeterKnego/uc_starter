# Deploy to three machines

> Placeholder — the full guide is written with the project docs. Until then,
> follow [Run a cluster on real hosts](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/run-a-cluster.md)
> and [Encrypt traffic between nodes](https://github.com/PeterKnego/ultima_cluster/blob/v2.13.0/docs/how-to/encrypt-node-traffic.md).

`make package HOSTS=ip0,ip1,ip2` writes `dist/<app>-<version>-<arch>.tar.gz`:
`bin/`, `systemd/`, `hosts/<ip>/{node.toml,gateway.toml}` and this file as
`DEPLOY.md`. Each `node.toml` has `[crypto] enabled = true` with
`/etc/uc2/node.key` and `/etc/uc2/allowlist.toml`, and `[admin]` with
`/etc/uc2/admin/admin.key`; the node refuses to start until those exist.
