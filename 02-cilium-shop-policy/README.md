# 02-cilium-shop-policy

Hands-on practice with Cilium network policies. It runs in the cluster from [01-kind-cilium-setup](../01-kind-cilium-setup/README.md).

The app starts with no network policy, so every pod can reach every other pod. The policies are then added in stages: first by identity and port (L3/L4), then by HTTP method and path (L7), and finally by which outside domains `api` may call (egress by DNS name).

```text
namespace: shop

frontend ─┐                       ┌─▶ api (x2) ──▶ db
admin    ─┼── which calls are   ──┤   HTTP :80     Redis :6379
intruder ─┘   allowed?            └─
```

| Pod | Image | Role |
|---|---|---|
| `api` (2 replicas) + Service | `traefik/whoami:v1.12.0` | Backend API. It answers any path and echoes the request, so no real API code is needed |
| `db` + Service | `redis:8.8-alpine` | Database |
| `frontend` | `curlimages/curl:8.23.0` | Customer-facing site. Should only list products and place orders |
| `admin` | `curlimages/curl:8.23.0` | Back office. May use `/admin/*` |
| `intruder` | `curlimages/curl:8.23.0` | A compromised pod. Should reach nothing |

The three client pods only run `sleep`. Requests are sent with `kubectl exec ... -- curl`. Cilium identifies each pod by its `app` label, not by its IP.

## Files

| File | What it does |
|---|---|
| `app.yaml` | Namespace `shop`, the five Deployments, and the `api` and `db` Services |
| `policy-db.yaml` | L3/L4: `db` accepts only `api` on TCP 6379 |
| `policy-api.yaml` | L3/L4: `api` accepts only `frontend` and `admin` on TCP 80 |
| `policy-api-l7.yaml` | L7: same policy name as `policy-api.yaml`, with HTTP rules added. Applying it replaces the L3/L4 version |
| `policy-api-egress.yaml` | Egress: `api` may only reach DNS, `example.com` on TCP 443 (stands in for a payment gateway), and `db` on TCP 6379 |
| `policy-api-egress-dns-strict.yaml` | Experiment: same policy name as `policy-api-egress.yaml`, but DNS lookups are limited to `example.com`. It breaks name resolution, see [the DNS experiment](#experiment-restrict-dns-lookups) |

Policies are kept apart from `app.yaml`, so `kubectl delete -f policy-*.yaml` removes a policy without deleting the app.

## Get the files in the VM

The repo is cloned in step 3 of [01-kind-cilium-setup](../01-kind-cilium-setup/README.md#3-clone-the-repo-in-the-vm). Run the rest in the VM, from this folder:

```bash
cd ~/cilium-lab/02-cilium-shop-policy
```

## Stage 0: Deploy the app with no policy

```bash
kubectl apply -f app.yaml
kubectl get pods -n shop -o wide          # 6 pods, all Running
kubectl get services -n shop
```

Every connection succeeds, including the ones that should not:

```bash
kubectl exec -n shop deploy/frontend -- curl -s http://api/products
kubectl exec -n shop deploy/intruder -- curl -s http://api/admin/users
kubectl exec -n shop deploy/intruder -- sh -c 'echo PING | curl -s --max-time 3 telnet://db:6379'   # +PONG
```

## Stage 1: L3/L4 policies

```bash
kubectl apply -f policy-db.yaml
kubectl apply -f policy-api.yaml
kubectl get ciliumnetworkpolicies -n shop  # both VALID = True
```

When a policy selects a pod and has `ingress` rules, ingress traffic not listed is denied.

| Test | Result |
|---|---|
| `intruder` → `db:6379` | Blocked: no `+PONG`, curl exits with code 28 (timeout) |
| `frontend` → `db:6379` | Blocked |
| `api` → `db:6379` | Allowed: `+PONG` |
| `intruder` → `api:80` | Blocked |
| `frontend` → `api/admin/users` | **Allowed.** L3/L4 rules cannot see the HTTP path. Stage 2 fixes this |

### Testing as `api`

The `whoami` image has no shell or curl, so `kubectl exec` into it fails with `"sh": executable file not found`. Add a temporary debug container to an `api` pod instead. It shares the pod's network, so Cilium sees its traffic as coming from `app=api`:

```bash
kubectl get pods -n shop -l app=api
kubectl debug -n shop -it <api-pod-name> --image=curlimages/curl:8.23.0 -- sh
# in the debug shell:
echo PING | curl -s --max-time 3 telnet://db:6379
exit
```

The ephemeral container cannot be removed from the pod. It stops after `exit`, and goes away when the pod is deleted. Each `kubectl debug` adds one more, and `kubectl get pods` does not count them. List them with:

```bash
kubectl get pod -n shop <api-pod-name> \
  -o jsonpath='{range .spec.ephemeralContainers[*]}{.name}{"\n"}{end}'
```

To start clean, delete the pod and let the Deployment create a new one: `kubectl delete pod -n shop <api-pod-name>`.

## Stage 2: L7 HTTP policy

```bash
kubectl apply -f policy-api-l7.yaml        # api-allow configured
```

Print only the HTTP status code:

```bash
c() { kubectl exec -n shop deploy/"$1" -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 3 "${@:2}"; }

c frontend http://api/products             # 200
c frontend -X POST http://api/orders       # 200
c frontend http://api/admin/users          # 403
c frontend http://api/products/123         # 403: path is a regex that must match the whole path
c admin    http://api/admin/users          # 200
c admin    http://api/products             # 200
c intruder http://api/products             # 000, exit code 28
```

A 403 and a timeout come from different places:

| Result | Blocked by | Why |
|---|---|---|
| `403 Access denied` | Envoy | The source and port are allowed, so eBPF hands the connection to Envoy. Envoy reads the request, finds no matching HTTP rule, and answers itself. `api` never sees the request |
| `000`, exit code 28 | eBPF | The source identity is not allowed, so the first TCP packet (SYN) is dropped in the kernel. Nothing answers |

Cilium runs one Envoy per node (`cilium-envoy` DaemonSet in `kube-system`), not a sidecar in each pod. Only traffic that matches an L7 rule goes through it.

## Stage 3: Egress by DNS name

`api` should only call the payment gateway. In this lab, `example.com` plays the gateway and `example.org` plays an attacker's server. Before this stage, `api` can reach both.

```bash
kubectl apply -f policy-api-egress.yaml
kubectl get ciliumnetworkpolicies -n shop  # 3 policies
```

The policy has three egress rules:

| Rule | Why it is needed |
|---|---|
| `toEndpoints` kube-dns in `kube-system`, port 53, with `rules.dns` | Without it, DNS lookups are blocked, because egress rules deny everything not listed. `rules.dns` sends DNS traffic through Cilium's DNS proxy, so Cilium can read the answers |
| `toFQDNs` `example.com`, TCP 443 | Allows HTTPS to the IPs that the DNS proxy saw for `example.com` |
| `toEndpoints` `app: db`, TCP 6379 | A connection needs both sides to allow it. `db` allows `api` on ingress, but `api` now also needs an egress rule |

Kube-dns lives in another namespace, so the rule names it with the label `k8s:io.kubernetes.pod.namespace: kube-system`. Cilium adds this label to every endpoint. It does not show in `kubectl get pods --show-labels`.

### How `toFQDNs` learns the IPs

```text
cilium-agent (user space)
  1. DNS proxy: is the query allowed by rules.dns? Forward it to CoreDNS and read the answer
  2. FQDN cache: record every answer (example.com and example.org)
  3. toFQDNs selects only example.com and writes its IPs into the eBPF policy
eBPF (kernel)
  api -> 104.20.23.154:443 (example.com)  allowed
  api -> 104.20.26.136:443 (example.org)  dropped, shown as "world"
```

The IPs above are what `example.com` and `example.org` resolved to on 2026-11-10. They can change.

### Test as `api`

```bash
API_POD=$(kubectl get pods -n shop -l app=api -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl get pod -n shop "$API_POD" -o jsonpath='{.spec.nodeName}')
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium --field-selector spec.nodeName="$NODE" -o name)

kubectl debug -n shop -it "$API_POD" --image=curlimages/curl:8.23.0 -- sh
# in the debug shell:
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://example.com   # 200
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://example.org   # 000 (timeout)
echo PING | curl -s --max-time 3 telnet://db:6379                            # +PONG
exit
```

Then, from the VM:

```bash
hubble observe -P -n shop --protocol dns --last 10       # DNS lines say "proxy"
hubble observe -P -n shop --verdict DROPPED --last 10    # example.org shows as "world"
kubectl exec -n kube-system "$CILIUM_POD" -- cilium-dbg fqdn cache list
```

The FQDN cache lists `example.org` too. The cache holds every answer the proxy saw. The policy only allows the IPs of names that match `toFQDNs`.

In the curl output, IPv6 attempts fail at once with `Network unreachable`. That is not the policy. The cluster is IPv4 only, so pods have no IPv6 route.

### Two pitfalls seen while building this policy

| Policy so far | Result |
|---|---|
| Only `toFQDNs` `example.com` | `Could not resolve host`. Hubble shows `EGRESS DENIED (UDP)` to CoreDNS port 53. Looking up the name is egress traffic too |
| DNS allowed on port 53, but without `rules.dns` | The name resolves, but the TCP connection times out, for `example.com` too. Cilium never saw the DNS answer, so `toFQDNs` has no IPs |

## Experiment: restrict DNS lookups

`matchPattern: "*"` lets `api` look up any name. That leaves DNS tunneling open, where data is hidden in lookups such as `<data>.attacker.example`. `policy-api-egress-dns-strict.yaml` allows lookups of `example.com` only.

```bash
kubectl apply -f policy-api-egress-dns-strict.yaml   # api-allow-egress configured
```

| Test in the `api` debug shell | Result |
|---|---|
| `curl https://example.com` | Fails after about 5 s with `Could not resolve host` |
| `echo PING \| curl telnet://db:6379` | Fails the same way |
| `curl https://example.com./` (trailing dot) | `200` |
| `nslookup example.org.` | `REFUSED` |

Hubble explains the first two:

```text
dns-request proxy DROPPED (DNS Query example.com.shop.svc.cluster.local. A)
dns-request proxy DROPPED (DNS Query db.shop.svc.cluster.local. A)
```

The pod's `/etc/resolv.conf` has `search shop.svc.cluster.local ...` and `options ndots:5`. A name with fewer than five dots is first tried with the search domains, so the first query is `example.com.shop.svc.cluster.local`, not `example.com`. That name is not allowed, the lookup fails, and `example.com` itself is never asked. A trailing dot marks the name as complete and skips the search domains.

The proxy answers a refused lookup with `REFUSED`, as `nslookup` shows. Hubble logs the request as `DROPPED`, because it was not forwarded to CoreDNS. curl still waits about 5 s and retries. It looks as if the musl resolver in this Alpine-based image does not accept `REFUSED`. That is inferred from the timing, not verified.

Strict DNS rules need cluster names (such as `db.shop.svc.cluster.local`) and the search-domain behavior handled, for example by lowering `ndots` in the pod's `dnsConfig`. This lab keeps `matchPattern: "*"` and relies on `toFQDNs` to limit connections, as Cilium's own examples do.

Restore the working policy:

```bash
kubectl apply -f policy-api-egress.yaml
```

## Observe with Hubble

```bash
hubble observe -P -n shop --verdict DROPPED --last 10   # L3/L4 drops (TCP SYN)
hubble observe -P -n shop --protocol http --last 10     # L7 requests and responses
hubble observe -P -n shop --protocol dns --last 10      # DNS through Cilium's DNS proxy
```

In the HTTP view, a denied request shows as `http-request DROPPED` followed by a `403 0ms` response. An allowed one takes a few milliseconds, because it really reaches `api`. Requests from `intruder` do not appear at all, because they never reach Envoy.

## Switch stages

```bash
kubectl delete -f policy-api-egress.yaml   # back to stage 2
kubectl apply  -f policy-api.yaml          # back to L3/L4 for api
kubectl delete -f policy-db.yaml -f policy-api.yaml   # back to stage 0
```

`policy-api.yaml` and `policy-api-l7.yaml` both define `api-allow`, so either file can delete it. The same goes for the two egress files and `api-allow-egress`.

## Clean up

```bash
kubectl delete namespace shop              # deletes the app and its policies
```

## Notes

- **Security identities.** Cilium maps each set of labels to a numeric identity. See them with `kubectl get ciliumendpoints -n shop`. Hubble prints the same numbers as `(ID:...)`.
- **Duplicate identities.** In this lab, the two `api` pods got different identities (3175 and 45811) with identical `security-labels`. Both were created in the same second by the Cilium agents on two different nodes. The [Cilium docs](https://docs.cilium.io/en/latest/network/kubernetes/identity-management-mode/) call this CID duplication. Policies still work, because they select by label, not by number.
- **Short Service names.** `http://api` works because each pod's `/etc/resolv.conf` has `search shop.svc.cluster.local ...`. The full name is `api.shop.svc.cluster.local`, and it resolves to the Service's ClusterIP, not a pod IP.
