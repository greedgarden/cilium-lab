# 01-kind-cilium-setup

Scripts to build a local Kubernetes lab with Cilium and Hubble: a 3-node [kind](https://kind.sigs.k8s.io/) cluster (1 control plane, 2 workers) running inside one Ubuntu VM.

```text
Windows 11 host
└── Hyper-V VM: Ubuntu Server 24.04 (k8s-lab)
    └── Docker Engine
        ├── kind-control-plane  ┐
        ├── kind-worker         ├─ Kubernetes nodes, one container each
        └── kind-worker2        ┘
            └── Cilium (CNI) + Hubble
```

Tested on 2026-11-08 with Ubuntu 24.04.5 (kernel 6.8.0-149-generic), Docker 29.9.3, kubectl v1.37.2, kind v0.33.0 (node image v1.37.0), Cilium 1.20.4, cilium CLI v0.20.2, and hubble CLI v1.20.2.

## Files

| File | What it does |
|---|---|
| `01-install-docker.sh` | Installs Docker Engine from Docker's apt repository and adds you to the `docker` group |
| `02-install-tools.sh` | Installs pinned versions of `kubectl`, `kind`, `cilium`, and `hubble`, with checksum checks |
| `03-tune-sysctl.sh` | Raises the inotify limits that multi-node kind clusters need |
| `kind-config.yaml` | 1 control plane + 2 workers, with kind's default CNI disabled so Cilium can provide pod networking |
| `04-create-cluster.sh` | Creates the cluster, installs Cilium, and enables Hubble; skips steps that are already done |
| `99-teardown.sh` | Deletes the cluster and keeps everything else installed |

## 1. Create the VM (manual)

Use Hyper-V, because WSL2 already runs on it. Hyper-V needs Windows Pro, Enterprise, or Education.

1. In an administrator PowerShell, enable Hyper-V and reboot:

   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
   ```

2. Download the [Ubuntu Server 24.04 LTS ISO](https://ubuntu.com/download/server).
3. In Hyper-V Manager, choose **New > Virtual Machine**:

   | Setting | Value |
   |---|---|
   | Name | `k8s-lab` |
   | Generation | 2 |
   | Memory | 8192 MB, dynamic memory off |
   | Network | Default Switch |
   | Disk | 60 GB VHDX (dynamically expanding) |
   | Install from | the Ubuntu ISO |

4. Before the first boot, open the VM's **Settings**:
   - **Security**: set the Secure Boot template to **Microsoft UEFI Certificate Authority**. With the default Windows template, the ISO fails with `The signed image's hash is not allowed (DB)`.
   - **Processor**: 4 or more virtual processors.

5. Install Ubuntu Server with these choices:

   | Installer screen | Choice |
   |---|---|
   | Type of installation | Ubuntu Server (not minimized) |
   | Storage | Use an entire disk, **LVM off** |
   | Profile | server name `k8s-lab` |
   | Ubuntu Pro | Skip |
   | SSH | Install OpenSSH server |
   | Featured snaps | none (Docker comes from Docker's apt repository) |

6. At `Please remove the installation medium`, eject the ISO from the VM window (**Media > DVD Drive > Eject**) and press Enter. The `Failed unmounting cdrom.mount` message is harmless.

## 2. Connect with SSH

Connect from Windows PowerShell:

```powershell
ssh <user>@k8s-lab.mshome.net
```

The Default Switch resolves `k8s-lab.mshome.net` to the VM, so the name keeps working when the VM gets a new IP after a host reboot.

WSL2 cannot reach the VM by default, because WSL and the Default Switch are separate virtual networks. Use Windows PowerShell for SSH.

## 3. Clone the repo in the VM

In the VM:

```bash
git clone https://github.com/greedgarden/cilium-lab.git ~/cilium-lab
```

## 4. Run the scripts

Run them as a normal user, not root. The scripts call `sudo` when needed.

```bash
cd ~/cilium-lab/01-kind-cilium-setup
./01-install-docker.sh
exit                      # log out so the docker group takes effect
```

Log in again, then:

```bash
cd ~/cilium-lab/01-kind-cilium-setup
docker run hello-world    # must work without sudo
./02-install-tools.sh
./03-tune-sysctl.sh
./04-create-cluster.sh
```

The first `kind create cluster` downloads the node image and takes a few minutes.

## 5. Check the result

```bash
kubectl get nodes                      # 3 nodes, all Ready
kubectl get pods -n kube-system -o wide
cilium status
hubble observe -P --last 10            # -P port-forwards to Hubble Relay
```

Before Cilium is installed, all nodes show `NotReady`. That is expected: the default CNI is disabled, so there is no pod network yet.

## 6. Tear down

```bash
./99-teardown.sh
```

Run `./04-create-cluster.sh` to build a fresh cluster again.

## Notes

- **Why raise inotify limits.** Each kind node runs its own systemd, containerd, and kubelet, and all of them run as root in the VM, so they share root's inotify limits. In this setup, the cluster used 116 inotify instances after Cilium was installed. The kernel default is 128, so the default would leave almost no headroom. Watches were far below the limit (537 used).
- **Measure inotify usage.** Expand the glob as root, because a normal user cannot read other processes' `fdinfo`:

  ```bash
  sudo find /proc/*/fd -lname 'anon_inode:inotify' 2>/dev/null | wc -l                    # instances
  sudo sh -c 'cat /proc/[0-9]*/fdinfo/* 2>/dev/null' | grep -c '^inotify'                 # watches
  ```

- **One kernel for every node.** `kubectl get nodes -o wide` shows `Debian GNU/Linux 13 (trixie)` as `OS-IMAGE`, because that is the node image's userland, but `KERNEL-VERSION` is the VM's `6.8.0-149-generic`. Cilium's eBPF programs load into that shared kernel.
- **kube-proxy is still running.** This setup uses Cilium's default install. Cilium's kube-proxy replacement is not enabled.
