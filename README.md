# cilium-lab

A hands-on lab for learning Cilium on a local Kubernetes cluster: a 3-node kind cluster in a Hyper-V Ubuntu VM. It covers Cilium network policies (L3/L4, L7 HTTP, and DNS-based egress) and observing traffic with Hubble.

## Folders

| Folder | What it does | What it practices |
|---|---|---|
| [`01-kind-cilium-setup/`](01-kind-cilium-setup/README.md) | Scripts that build a 3-node kind cluster with Cilium and Hubble in a Hyper-V Ubuntu VM | Running Kubernetes nodes as containers with kind, replacing the default CNI with Cilium, enabling Hubble |
| [`02-cilium-shop-policy/`](02-cilium-shop-policy/README.md) | Deploys a small app (three client pods, an `api`, and a `db`), then adds Cilium network policies in stages and checks which calls are allowed or dropped | Default deny, identity-based L3/L4 rules, L7 HTTP rules enforced by Envoy, DNS-based egress (`toFQDNs`), observing allowed and dropped flows with Hubble |

Each folder's README has the steps to run it. Start with 01.

## Requirements

- Windows 11 Pro, Enterprise, or Education, because the VM runs on Hyper-V
- The VM in `01-kind-cilium-setup` uses 8 GB of memory, a 60 GB disk, and 4 or more vCPUs. Smaller sizes were not tried
- Tested versions are listed in [01-kind-cilium-setup](01-kind-cilium-setup/README.md)
