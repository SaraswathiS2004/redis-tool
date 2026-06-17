# redis-tool — Redis Cluster Lifecycle Tool (Ansible)

A small CLI tool (Bash) that uses **Ansible** to provision, operate and do a
**zero-downtime rolling upgrade** of a 6-node Redis Cluster (3 masters + 3 replicas).
The 6 nodes are Ubuntu containers that only run SSH — Ansible logs in over SSH and
installs/configures Redis. Your host is the Ansible control node.

```
submission/
├── redis-tool                # the CLI
├── prerequistecheck.sh       # checks container runtime (docker/podman) + ansible before anything runs
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/hosts.ini
│   └── playbooks/
│       ├── redis-cluster.yml # install + configure + start + form cluster
│       └── upgrade-node.yml  # install a version on ONE node (used by upgrade)
├── infra/
│   ├── containerfile         # Ubuntu 22.04 + SSH
│   └── compose.yml           # 6 nodes on a static 10.10.0.0/24 network
└── output/                   # captured terminal output
```

## 1. Bring up the infrastructure

The containers need our SSH **public key** so Ansible can log in without a password.
Generate the key once, then start the 6 nodes (works with Docker or Podman):

```bash
cd submission

# 1) make the ssh key (compose mounts the .pub into every node)
ssh-keygen -t rsa -N "" -f infra/ssh_keys/id_rsa

# 2) start the 6 nodes
docker compose -f infra/compose.yml up -d --build
# or with podman:
# podman-compose -f infra/compose.yml up -d --build
```

Nodes come up as `redis-node-1`..`redis-node-6` on `10.10.0.11`..`10.10.0.16`.
Check Ansible can reach them:

```bash
cd ansible && ansible -i inventory/hosts.ini redis_nodes -m ping ; cd ..
```

To stop everything: `docker compose -f infra/compose.yml down`.

## 2. Run the commands

```bash
# Phase 1 - provision Redis 7.0.15 and form the cluster
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1

# Phase 2 - seed deterministic data and verify it
./redis-tool data seed --keys 1000
./redis-tool data verify

# Phase 3 - readable cluster status
./redis-tool status

# Phase 4 - zero-downtime rolling upgrade
./redis-tool upgrade --target-version 7.2.6 --strategy rolling

# Phase 5 - full health check
./redis-tool verify --full
```

## 3. The rolling upgrade strategy (and why)

The goal is **no client downtime** — the cluster must stay `cluster_state:ok` the whole time.

1. **Pre-flight:** check the cluster is `ok`, the current version is different from the
   target, and `data verify` passes (a baseline so we can prove no data was lost).
2. **Replicas first, one at a time.** A replica serves no writes, so upgrading it is invisible
   to clients: install 7.2.6 → restart → wait for `master_link_status:up` and cluster `ok`.
3. **Masters next, one at a time, with failover.** A master owns slots, so we never stop a live
   master. Instead we run `CLUSTER FAILOVER` on its (already upgraded) replica, which becomes the
   new master. The old master is now a replica, so we upgrade it like any replica.
   Because the replica is upgraded *before* it is promoted, the node serving each slot is always up.
4. **Post-upgrade:** `data verify` again (1000/1000 still correct) and `status` (all nodes on 7.2.6).

The ordering and health-checks live in `redis-tool` (bash); Ansible (`upgrade-node.yml`) only does
the per-node work (install + restart). That keeps the Ansible simple and reusable.

## 4. Assumptions & trade-offs

- 6 fixed nodes (`10.10.0.11`..`.16`) defined in `compose.yml` and the inventory.
  `--masters`/`--replicas-per-master` are accepted but the layout is the canonical 3+3.
- `data seed`/`data verify`/`status` use `redis-cli` from the host (the assignment allows direct
  TCP). This needs the `10.10.0.x` network reachable from the host (rootful Docker).
- Health checks poll `cluster_state:ok` / `master_link_status:up` with a timeout — simple and
  enough for 6 nodes.
- Redis is built from source so we get the exact version (7.0.15 / 7.2.6). The cluster identity
  (`nodes.conf`) is kept on disk, so a restarted node rejoins with the same id.

## 5. Known limitations

- No automatic rollback if an upgrade step fails — it stops and leaves the cluster as-is.
- Scale out / scale in / rollback (stretch goals) are not implemented.

## Note on output/
The machine this was written on has no Docker/Ansible, so `output/*.txt` are placeholders that
list the command to run. Run the commands above on a host with Docker/Podman + Ansible 2.14+ and
`tee` into each file to capture real output.
