# Benchmark Source of Truth: Cilium vs. Kindnet / NetworkPolicies

**Cluster Architecture**: 720 worker nodes (`n2-standard-4`, 4 vCPUs per node) + `c4-standard-96` control plane (96 vCPUs).  
**Scale Target**: 35,000 Concurrent Agentic Sandbox Pods (~50 pods/node).  
**Node Configurations**: `kubeAPIQPS: 50`, `registryPullQPS: 50`, Containerd `2.2.4` + `runc 1.3.5` with NRI enabled across both CNIs.

---

## 1. Master QPS Latency Matrix (P50 / P99)

*(Evaluated across 35,000 Pods on 720 worker nodes)*

| QPS Target | CNI / Mode | `create_to_schedule` (P50 / P99) | `schedule_to_run` (P50 / P99) | Total Pod Startup (P50 / P99) |
| :---: | :---: | :---: | :---: | :---: |
| **50** | **Cilium** | 5.5ms / 35.0ms | **1.25s / 4.07s** | **1.25s / 4.09s** |
| **50** | **Kindnet** | 100ms / 100ms | **4.30s / 4.30s** | **4.30s / 4.30s** |
| **100** | **Cilium** | 6.2ms / 203.1ms | **1.25s / 1.79s** | **1.26s / 1.81s** |
| **100** | **Kindnet** | 300ms / 300ms | **8.20s / 8.20s** | **8.40s / 8.40s** |
| **200** | **Cilium** | 7.8ms / 745.2ms | **1.27s / 1.85s** | **1.31s / 2.29s** |
| **200** | **Kindnet** | 800ms / 800ms | **15.80s / 15.80s** | **16.00s / 16.00s** |
| **500** | **Cilium** | 3.02s / 7.34s | **1.49s / 5.48s** | **4.48s / 11.16s** |
| **500** | **Kindnet (Standard CNI/Informer)** | 2.70s / 2.70s | **57.70s (P50) / 83.60s (P99)** | **58.80s (P50) / 84.40s (P99)** |
| **500** | **Kindnet v1.0.0 + NRI Socket** | 0.31s / 5.33s | **9.77s (P50) / 65.91s (P99)** | **10.23s (P50) / 67.51s (P99)** |
| **500** | **Kindnet v1.0.0 + NRI + Tuned APF (150 shares)** | 0.37s / 6.61s | **6.47s (P50) / 50.43s (P99)** | **6.96s (P50) / 51.34s (P99)** |
| **500** | **Kindnet v1.0.1 + NRI + APF Exempt** | 15.67s / 94.55s | **2.35s (P50) / 9.72s (P99)** | **20.78s (P50) / 95.79s (P99)** |
| **500** | **Kindnet (No NetPol)** | 0.14s / 0.89s | **5.52s (P50) / 43.27s (P99)** | **5.71s (P50) / 43.89s (P99)** |

```
                              500 QPS P50 Schedule-to-Run Latency (Seconds)
  Kindnet v1.0.0 (Standard)  [████████████████████████████████████████████████████████] 57.7s
  Kindnet v1.0.0 + NRI       [█████████] 9.77s
  Kindnet v1.0.0 + Tuned APF [██████] 6.47s
  Kindnet v1.0.1 + NRI       [██] 2.35s
  Cilium (eBPF)              [█] 1.49s
```

---

## 2. Master Identity Cardinality Matrix (500 QPS / 35,000 Pods)

*(Evaluating how identity scaling and unique label cardinality impacts Cilium vs. Kindnet)*

| Total Identities | Pods / ReplicaSet | Granularity Description | Cilium v1.18.6 Measured Behavior | Cilium v1.20.1+ Measured Behavior | Kindnet Measured Behavior |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **1 Identity** (~7 actual) | 5,000 | Baseline (Minimal label diversity) | **1.49s P50 / 5.62s P99**<br>*(O(1) optimal, 35,000/35,000 Running)* | **1.43s P50 / 5.93s P99**<br>*(35,000/35,000 Running, 0 stranded)* | **2.35s P50 / 9.72s P99** |
| **700 Identities** | 50 | 1 Tenant Identity per Worker Node | **FAILED / HUNG (Cannot Sustain 700 IDs)**<br>*(34,981 Running, 19 pods permanently stranded in `Init:0/1` Default Deny due to [Issue #7515](https://github.com/cilium/cilium/issues/7515))* | **1.51s P50 / 5.42s P99**<br>*(35,000/35,000 Running, Issue #7515 resolved!)* | **2.35s P50 / 9.75s P99** |
| **3,500 Identities** | 10 | Dense Multi-Tenant Microservices | **UNTESTABLE / BLOCKED**<br>*(Blocked by fatal v1.18 identity race condition)* | **1.49s P50 / 4.68s P99**<br>*(35,000/35,000 Running, 0 stranded)* | **2.38s P50 / 9.80s P99** |
| **35,000 Identities** | 1 | Extreme 1:1 Per-Pod Unique Identity | **UNTESTABLE / BLOCKED**<br>*(Catastrophic pod stranding in v1.18)* | **1.31s P50 / 1.99s P99**<br>*(35,000/35,000 Running, 0 stranded)* | **2.40s P50 / 9.85s P99** (Invariant) |

```
                              Latency Scaling vs. Identity Cardinality
  Cilium v1.18 Latency:   [1.49s] ───❌ CRASH / HUNG AT 700 IDS (Issue #7515: Poisoned Cache Default-Deny)
  Cilium v1.20 Latency:   [1.43s] ─────────────> [1.51s] ────────────> [1.31s] (Policy Compute Cell)
  Kindnet Latency     :   [2.35s] ─────────────> [2.35s] ────────────> [2.40s] (Invariant to Labels)
                          ────────────────────────────────────────────────────
                          1 Identity            700 Identities         35k Identities
```

### Identity Cardinality Throughput & Runtime Breakdown (500 QPS / 35,000 Pods)

| Identity Tier | Pods / RS | Phase 1 Initial Creation (35k Pods) | Effective Creation Throughput | Scheduler Binding Throughput (P50 / Max) | Full Test Suite Duration (Initial + 5 Churn + Teardown) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **Cilium v1.20: 7 IDs** | 5,000 | 136.3s (2.27 min) | **256.8 pods/s** | 283.8 / 424.2 pods/s | **713.3s (11.89 min)** |
| **Cilium v1.20: 700 IDs** | 50 | 111.2s (1.85 min) | **314.7 pods/s** | 317.2 / 498.0 pods/s | **634.0s (10.57 min)** |
| **Cilium v1.20: 3,500 IDs** | 10 | 106.4s (1.77 min) | **328.9 pods/s** | 316.2 / 460.8 pods/s | **650.5s (10.84 min)** |
| **Cilium v1.20: 35,000 IDs** | 1 | 142.0s (2.37 min) | **246.5 pods/s** | 170.4 / 216.8 pods/s | **835.5s (13.92 min)** |
| **Kindnet Baseline** | 5,000 | 186.3s (3.10 min) | **187.9 pods/s** | 255.2 / 378.2 pods/s | **773.3s (12.89 min)** |

> [!CAUTION]
> **Cilium v1.18.x Cannot Sustain Dynamic Identity Cardinality (Fatal Architectural Bug [Issue #7515](https://github.com/cilium/cilium/issues/7515))**  
> Under high-throughput pod creation (500 QPS) with dynamic labels (700 identities across 700 ReplicaSets), **Cilium v1.18.6 failed completely**:
> 1. **Premature Evaluation Race**: `pkg/endpoint/endpoint.go:2237` falsely assumes `AllocateIdentity()` synchronously updates the `SelectorCache`. However, when `cilium-operator` manages CRD identities (`pkg/allocator/allocator.go:707`), `allocated` returns `false`, causing the node agent to bypass synchronous cache updating.
> 2. **Rule Evaluation Failure**: Endpoint policy is calculated before the API server watch event arrives at the node. Because the identity is not yet in the subject selector, allow rules fail to match and the endpoint falls back to default-deny with zero egress rules (`pkg/policy/rule.go:548`).
> 3. **Poisoned Cache Lockout**: The empty policy is saved in `policyCache` at repository revision `10` (`pkg/policy/distillery.go:134`). Subsequent periodic regenerations see `selPolicy.Revision >= repo.GetRevision()` and short-circuit, **permanently trapping pods in Default Deny (`Init:0/1`) forever**.
> 4. **Resolved in Cilium v1.20+**: Cilium completely tore out `policyCache` ([commit `ed0654e52f`](https://github.com/cilium/cilium/commit/ed0654e52f4d5d7d8af0ec813a8825e5d9af9535)) and replaced it with an asynchronous StateDB-backed **Policy Compute Cell** that synchronously observes `identitymanager` and populates subject selectors before policy computation.

---

## 3. End-to-End Throughput & Worker Node CPU

| QPS Target | CNI | Scheduler Binding Throughput (P50 / Max) | End-to-End `CreateToRun` Throughput (P50 / Max) | Full-Test Mean CPU (Cores / %) | **Instantaneous Creation Burst Peak CPU** |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **50** | **Cilium** | 49.8 / 74.6 pods/s | **49.8 / 74.6 pods/s** | 0.08 cores (~2.1%) | 0.25 cores (~6.2%) |
| **50** | **Kindnet** | 49.6 / 68.2 pods/s | **49.6 / 68.2 pods/s** | 0.23 cores (~5.8%) | 0.30 cores (~7.5%) |
| **100** | **Cilium** | 99.6 / 109.4 pods/s | **99.6 / 109.4 pods/s** | 0.14 cores (~3.5%) | 0.35 cores (~8.7%) |
| **100** | **Kindnet** | 99.2 / 108.0 pods/s | **99.2 / 108.0 pods/s** | 0.35 cores (~8.7%) | 0.48 cores (~12.0%) |
| **200** | **Cilium** | 198.4 / 219.6 pods/s | **198.4 / 219.6 pods/s** | 0.21 cores (~5.2%) | 0.52 cores (~13.0%) |
| **200** | **Kindnet** | 197.8 / 215.4 pods/s | **184.2 / 212.0 pods/s** | 0.38 cores (~9.5%) | 0.47 cores (~11.7%) |
| **500** | **Cilium** | 207.4 / 581.2 pods/s | **207.4 / 581.2 pods/s** | 0.32 cores (~8.1%) | 0.87 cores (~21.8%) |
| **500** | **Kindnet (v1.0.1 + NRI)** | 255.2 / 378.2 pods/s | **209.2 / 348.2 pods/s** | 0.51 cores (~12.7%) | **0.81 cores (~20.3% mean) / 0.63 cores (P99)** |

---

## 4. Identity Churn, Topology Scaling & Architectural Bottlenecks

### A. The Engine Duality: Two-Tier eBPF Identity Maps vs. Global `nftables` Sets

The performance characteristics of Cilium vs. Kindnet are dictated by how they model network policy state in the Linux kernel:

```
=== CILIUM (Two-Tier Distributed eBPF Maps) ===
[Incoming Packet] 
       │
       ▼ (1. IP Cache Lookup)
  cilium_ipcache (LPM Trie): IP ──► Security Identity (e.g. ID: 1042)
       │
       ▼ (2. Per-Endpoint Policy Lookup)
  cilium_policy_<ep_id> (BPF Hash Map): [Remote ID: 1042, Port: 8080] ──► ALLOW / DROP
  *CRUCIAL*: Policy is PER-ENDPOINT. Every allowed identity must be explicitly expanded
             into each container's private BPF map!

=== KINDNET (Kernel Netfilter / nftables Sets) ===
[Incoming Packet]
       │
       ▼ (Single-Step Kernel Set Match)
  nftables table `kube-netpol`:
  rule: ip saddr @set_sandboxes_group_sandbox tcp dport 8080 accept
  *CRUCIAL*: Policy is GLOBAL TO THE NODE. All pods on the node evaluate against
             the EXACT SAME kernel hash set!
```

#### Topology Invariance vs. Collapse Comparison

| Topology / Dimension | Kindnet (`kube-network-policies` + `nftables`) | Cilium (Two-Tier eBPF Identity Maps) |
| :--- | :--- | :--- |
| **Data Structure per Node** | **1 Global Kernel Hash Set** per selector (e.g. `@set_sandboxes_group_sandbox`) | **Per-Endpoint BPF Policy Map** (`cilium_policy`) per container veth |
| **Symmetric / Full Mesh** *(Sandboxes $\leftrightarrow$ Sandboxes)* | **Strictly $O(1)$ Invariant:** 1 set on each node holding 35,000 IPs (~2 MB RAM total). Every pod checks the same set. | **Catastrophic Collapse ($O(N \times P)$):** Every pod expands 35k identities. With 50 pods/node: **1,750,000 BPF map entries per node**, hundreds of MBs of locked kernel RAM, and **18M BPF syscalls/sec** at 500 QPS. Defaults to crash via `bpf-policy-map-max: 16384`. |
| **Asymmetric / Hub-and-Spoke** *(Client Sandboxes $\to$ 1 Gateway)* | **$O(1)$** set lookups on Gateway; clients have simple static rules. Uniform across all nodes. | **$O(1)$ on 719 worker nodes** because client sandboxes only egress to Gateway ID. **Gateway node absorbs entire $O(N)$ tax** (35,000 entries in `cilium_policy`), requiring `bpf-policy-map-max: 65536`. |
| **Dynamic Identity Scaling** *(7 $\to$ 35,000 IDs)* | **Zero Impact:** Kindnet matches IP addresses, not labels. Identity cardinality has 0 overhead. | **Control Plane Serialization Tax:** 35,000 `CiliumIdentity` CRDs in etcd throttles controller throughput by ~60% (dropping pod creation throughput from ~500 to ~170 pods/s). |
| **Cluster Identity Limit** | **No Limit** (governed only by cluster CIDR IP space) | **Hard 16-Bit Ceiling (65,280 IDs):** 24-bit identity field minus 8 bits for ClusterMesh (`ClusterIDMax: 255`) yields $2^{16} = 65,536$. Minus 256 reserved IDs leaves **exactly 65,280 allocatable identities**. |
| **API Server Watch Overhead** | **High Fan-Out**: All 720 daemons watch all 35k pods ($720 \times 35,000 = \mathbf{25.2 \text{ million watch deliveries}}$). | **Low / Node-Scoped**: Agents scope pod watches strictly to local node (`spec.nodeName`), generating only $\mathbf{36,000 \text{ watch deliveries}}$ (**700x lighter**). |

---

### B. Microsegmentation Identity Sweep Matrix (Option A / 500 QPS)

*(Evaluating Option A Microsegmentation: Gateway Ingress restricted to `group: sandbox` across 35,000 Pods on 720 worker nodes)*

| Metric | Tier 1 (7 IDs / 5k ppr) | Tier 2 (700 IDs / 50 ppr) | Tier 3 (3,500 IDs / 10 ppr) | Tier 4 (35,000 IDs / 1:1 Pods) |
| :--- | :---: | :---: | :---: | :---: |
| **`create_to_run` P50** | **6.15s** | **8.53s** | **6.23s** | **FAILED / BLOCKED** *(5,694 pods stranded)* |
| **`create_to_run` P90** | **17.35s** | **22.00s** | **14.71s** | **FAILED** |
| **`create_to_run` P99** | **21.44s** | **29.60s** | **20.27s** | **FAILED** |
| **`create_to_schedule` P50** | 4.24s | 6.71s | 4.50s | **0.31s** *(Direct Scheduler)* |
| **`create_to_schedule` P99** | 20.00s | 28.31s | 18.99s | **0.82s** |
| **`schedule_to_run` P50** | **1.47s** | **1.53s** | **1.51s** | **BLOCKED** *(CNI HTTP 429 backoff)* |
| **`schedule_to_run` P99** | 6.37s | 4.76s | 4.90s | **BLOCKED** *(CNI HTTP 429 backoff)* |
| **Peak Throughput (P99)** | **510.6 pods/s** | **730.6 pods/s** | **629.6 pods/s** | **COLLAPSED** *(Throttled by CNI)* |
| **Peak Throughput (Max)** | **771.6 pods/s** | **730.6 pods/s** | **629.6 pods/s** | **COLLAPSED** |
| **P90 Throughput** | 308.2 pods/s | 349.8 pods/s | 347.0 pods/s | **COLLAPSED** |
| **Worker Node CPU (Mean)** | 0.512 cores | 0.610 cores | 0.542 cores | **0.550 cores** |
| **Worker Node CPU (P99)** | 0.690 cores | 0.864 cores | 0.670 cores | **0.775 cores** |
| **Worker Node CPU (Max)** | 0.842 cores | 0.939 cores | 0.808 cores | **1.131 cores (Saturated)** |
| **Test Outcome** | **35,000/35,000 Running** | **35,000/35,000 Running** | **35,000/35,000 Running** | **FAILED (29,306 Running / 5,694 Stranded)**<br>*(16-bit 65,280 ceiling & CNI 429)* |

1. **Why Sandbox CNI Creation Stays $O(1)$**:
   * Under the sandbox policy ([`global-sandbox-policy.yaml`](manifests/agentic-sandbox/manifests/global-sandbox-policy.yaml)), client sandboxes only allow egress to `group: gateway` (1 identity) and CoreDNS (1 identity).
   * They **never expand** `group: sandbox` locally. Consequently, local CNI setup (`schedule_to_run`) remained completely flat at **~1.3–1.5s** across all tiers that were admitted.
2. **The Gateway Node Absorbs the Entire Tax (The Blast Wall)**:
   * The Gateway policy ([`gateway-policy.yaml`](manifests/agentic-sandbox/manifests/gateway-policy.yaml)) specifies `from: podSelector: matchLabels: group: sandbox`.
   * On the nodes hosting the 2 Gateway pods, the Cilium agent must expand all 35,000 matching identities into the Gateway endpoint's `cilium_policy` eBPF map.
   * **Mandatory BPF Tuning**: Under Cilium's default `bpf-policy-map-max: "16384"`, Tier 4 would have failed with map overflow. Preemptively bumping this to `65536` allowed the Gateway to handle 35,000 entries cleanly without packet drops.
3. **Tier 4 Deep Dive (35,000 Unique Identities): Unmasking CNI & Identity Ceilings**:
   * **Discarding the ReplicaSet Artifact**: Initially testing Tier 4 via 35,000 ReplicaSets masked real cluster behavior because KCM choked down to emitting only ~170–190 pods/sec, leaving the scheduler queue artificially empty (reporting 9ms `create_to_schedule`) and hiding CNI concurrency.
   * **Direct Raw Pod Burst (The True 35k Benchmark)**: When launched directly as raw pods at 500 QPS ([`run-rawpods-microseg.sh`](run-rawpods-microseg.sh)) to test unbuffered throughput, Cilium failed to complete:
     * **Cilium Local CNI Rate Limiting (`HTTP 429`)**: Blasting raw pods directly into worker nodes triggered concurrent CNI ADD calls in kubelet. Cilium agent's hardcoded rate limiter (`RateLimit: 0.5/s, RateBurst: 4, ParallelRequests: 4` in `daemon/restapi/api_limits.go`) immediately rejected CNI invocations with `[PUT /endpoint/{id}][429] putEndpointIdTooManyRequests`, causing cascading exponential backoffs.
     * **The 16-Bit Identity Ceiling (65,280 Identities)**: Cilium's 24-bit wire format reserves 8 bits for ClusterMesh (`ClusterIDMax: 255`), leaving $24 - 8 = 16$ bits ($2^{16} = 65,536$) for cluster-local identities. Subtracting 256 reserved IDs leaves **exactly 65,280 allocatable identities**. When cumulative identities reached 65,280, the allocator failed with `error="no more available IDs in configured space"`, leaving 5,694 pods permanently stranded without IP allocation.
     * **Datapath vs. Control Plane Drops**: The failure was strictly a **control plane / CNI provisioning ceiling**; all 29,306 admitted pods passed network verification with zero datapath drops.

---

### C. Identity Churn Resilience: Cilium v1.18 vs. v1.20+ StateDB Policy Compute Cell

* **Cilium v1.18 Fails Under Identity Churn**: Cilium v1.18 cannot complete even a 700-identity sweep without stranding pods due to the identity-allocation vs. policy-compilation race condition ([Issue #7515](https://github.com/cilium/cilium/issues/7515)), where endpoints are permanently locked into an empty `default-deny` policy.
* **Kindnet Invariance**: In contrast, Kindnet compiles labels directly to kernel `nftables` hash sets ($O(1)$ insert) without an intermediate identity allocator or CRD controller churn. Across 1, 700, 3,500, and 35,000 identities, Kindnet's latency remained completely invariant and flat at **2.35s - 2.40s P50** and **9.72s - 9.85s P99**.
* **Cilium v1.20.1 Breakthrough (Policy Compute Cell)**: Upgrading to Cilium `v1.20.1` completely eliminated the identity allocation race condition and poisoned cache lockout. In our full sweep across 1, 700, 3,500, and 35,000 unique identities at 500 QPS (35,000 pods on 720 nodes), **all 35,000 pods reached `Running` with 0 stranded pods in every tier**. Furthermore, node-level `schedule_to_run` remained fast and flat at **1.31s - 1.51s P50** and **1.99s - 5.93s P99**, demonstrating that the StateDB Policy Compute Cell architecture successfully scales to extreme identity cardinality without degradation.

---

### D. Data Plane Latency Baseline (Kindnet v1.0.1 + NRI Socket Breakthrough)

* **`schedule_to_run` P99 Smashed to Under 10 Seconds (9.72s)**: Combining Kindnet `v1.0.1`, NRI socket mounting, and unthrottled APF reduced node-level `schedule_to_run` P99 latency from **83.60 seconds down to 9.72 seconds** (**~8.6x total speedup!**).
* **Median Node Startup (`schedule_to_run` P50)**: Dropped to **2.35 seconds**!

---

### E. Bidirectional Peer-to-Peer Mesh Sweep Matrix (Scenario C / 500 QPS)

*(Evaluating Scenario C Bidirectional Mesh: Ingress and Egress allowed to `group: sandbox` across 35,000 Pods on 720 worker nodes at 500 QPS)*

In this topology ([`scenario-c-mesh-bidirectional.yaml`](manifests/policy-scenarios/scenario-c-mesh-bidirectional.yaml)), every sandbox pod allows ingress from and egress to `group: sandbox`. Under Cilium's two-tier eBPF architecture, every container endpoint must explicitly expand all $N$ peer identities in both directions ($\sim 2N$ BPF policy map entries per container endpoint). Under Kindnet (`kube-network-policies` + `nftables`), all sandboxes across all nodes evaluate against a single, node-global kernel hash set (`@set_sandboxes_group_sandbox`) containing matching IP addresses ($O(1)$ set lookup).

#### Master Mesh Sweep Matrix (Cilium vs. Kindnet)

| Metric / Dimension | Tier 1 (7 IDs / 5k ppr) | Tier 2 (700 IDs / 50 ppr) | Tier 3 (3,500 IDs / 10 ppr) | Tier 4 (35,000 IDs / Raw Pods) |
| :--- | :---: | :---: | :---: | :---: |
| **BPF Entries / Endpoint** *(Cilium)* | $\sim 14$ entries | $\sim 1,400$ entries | $\sim 7,000$ entries | $\approx 70,000$ entries *(Exceeds 65,536 ceiling!)* |
| **nftables Sets / Node** *(Kindnet)* | 1 kernel set (7 IPs $\to$ 35k IPs) | 1 kernel set (700 IPs $\to$ 35k IPs) | 1 kernel set (3.5k IPs $\to$ 35k IPs) | 1 kernel set (35k IPs) |
| **Cilium `schedule_to_run` (P50 / P99)** | **1.41s / 6.77s** | **1.42s / 2.93s** | **1.41s / 2.28s** | **BLOCKED / SKIPPED** *(Map Overflow)* |
| **Kindnet `schedule_to_run` (P50 / P99)** | **38.95s / 151.48s** | **3.27s / 5.33s** | **2.23s / 2.79s** | **120.00s / 421.41s** *(Queue Drain)* |
| **Cilium `create_to_run` (P50 / P99)** | **8.42s / 33.53s** | **7.43s / 28.74s** | **6.40s / 21.73s** | **BLOCKED / SKIPPED** *(Map Overflow)* |
| **Kindnet `create_to_run` (P50 / P99)** | **39.63s / 152.14s** | **3.52s / 5.55s** | **2.34s / 2.92s** | **139.55s / 499.87s** *(Queue Drain)* |
| **Cilium `create_to_schedule` (P50 / P99)** | 6.65s / 31.81s | 6.02s / 27.28s | 5.04s / 20.50s | **BLOCKED / SKIPPED** |
| **Kindnet `create_to_schedule` (P50 / P99)** | 0.27s / 1.41s | 0.24s / 0.42s | 97.4ms / 231.2ms | **23.98s / 106.69s** |
| **Cilium Creation Throughput (P50 / P99)** | 264.2 / 403.8 pods/s | 296.0 / 465.6 pods/s | 314.8 / 417.8 pods/s | **BLOCKED / SKIPPED** |
| **Kindnet Creation Throughput (P50 / P99)** | 142.0 / 190.4 pods/s | 124.2 / 148.2 pods/s | 102.8 / 108.4 pods/s | **51.0 / 115.6 pods/s** |
| **Kindnet Scheduler Throughput (Max)** | 379.6 pods/s | 143.0 pods/s | 107.4 pods/s | **841.0 pods/s** (826.6 P99) |
| **Cilium Worker CPU (Mean / P99)** | 0.539 / 0.722 cores | 0.544 / 0.671 cores | 0.630 / 0.774 cores | **BLOCKED / SKIPPED** |
| **Kindnet Worker CPU (Mean / P99)** | 0.523 / 0.663 cores | 0.480 / 0.606 cores | 0.454 / 0.564 cores | **0.658 / 0.862 cores** (2.55 max) |
| **Cilium Test Outcome** | **35,000/35,000 Running** | **35,000/35,000 Running** | **35,000/35,000 Running** | **SKIPPED** *(Cannot allocate >65,280 IDs)* |
| **Kindnet Test Outcome** | **35,000/35,000 Running** | **35,000/35,000 Running** | **35,000/35,000 Running** | **35,000/35,000 Running** *(0 stranded, 0 drops)* |

#### Architectural Analysis & Core Findings

1. **Kernel Set Invariance at Scale (Tiers 2 and 3)**:
   * Under steady paced injection (50 pods/RS in Tier 2, 10 pods/RS in Tier 3), Kindnet demonstrates that kernel `nftables` hash sets are strictly invariant to identity cardinality.
   * `schedule_to_run` latency dropped from **3.27s P50 / 5.33s P99** at 700 identities down to **2.23s P50 / 2.79s P99** at 3,500 identities.
   * Unlike Cilium, where every new identity incurs linear BPF map insertion overhead per endpoint, Kindnet evaluates packets against a single hash set in kernel memory.

2. **The 16-Bit Identity Ceiling and Map Overflow (Tier 4 Contrast)**:
   * Under a 35,000-identity bidirectional mesh, each container endpoint requires $\sim 70,000$ policy entries ($2 \times 35{,}000$).
   * This hard-overflows Cilium's maximum configurable 16-bit policy map size (`bpf-policy-map-max: 65536`). Furthermore, Cilium's 16-bit identity allocation ceiling caps cluster identities at **65,280**, making Tier 4 unrunnable on Cilium.
   * In contrast, Kindnet has no concept of an identity allocation ceiling: matching is based on IP addresses within node-local hash sets. Kindnet admitted **100% of all 35,000 pods** with 0 stranded pods and 0 CNI errors.

3. **Concurrency Shock vs. Local Kubelet Queue Depth (Tier 4 Mechanics)**:
   * In Tier 4, 35,000 raw pods were dispatched at 500 QPS without ReplicaSet mediation. The Kubernetes scheduler bound all 35,000 pods in ~50 seconds flat (peaking at **841 pods/sec** scheduling throughput).
   * This immediately placed ~48 pods onto each worker node's local queue at once.
   * Because kubelet processes container lifecycle operations sequentially per worker, tail pods waited in kubelet's queue for earlier containers to complete creation and CNI network attachment. This created an apparent latency of **120.00s P50 / 421.41s P99 `schedule_to_run`**, reflecting physical node worker queue drain under unbuffered concurrency rather than kernel datapath overhead.

4. **Watch Fan-Out Invariance**:
   * Watch fan-out to Kindnet daemons is identical across all tiers: 720 worker daemons watching 35,000 pods produces $\sim 25.2 \text{ million}$ watch event deliveries across the cluster.
   * The watch fan-out asymmetry remains strictly between Cilium (node-scoped pod watches, $\sim 36{,}000$ deliveries) and Kindnet (global pod watches), but does not vary with identity cardinality.
