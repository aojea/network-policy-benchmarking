# Network Policy Scenario Library

This directory is the **reproducibility record** for the network policy topologies used across
the Cilium vs. Kindnet benchmark campaign.

The live test harness renders policies from Go templates in
[`../agentic-sandbox/manifests/`](../agentic-sandbox/manifests/), which means the *effective*
policy for any historical run is only recoverable from git history. The manifests in this
directory are **static, fully-rendered snapshots** of what each run actually applied, so results
in [`../../benchmark_results.md`](../../benchmark_results.md) can be reproduced or audited later.

> [!IMPORTANT]
> These files are documentation artifacts, not the live templates. To *run* a scenario, set
> `CL2_SANDBOX_PEER_MODE` (see [Selecting a scenario](#selecting-a-scenario-at-runtime) below).
> If you change the live templates, update the matching snapshot here.

---

## Why the topology is the independent variable

Cilium and Kindnet respond to policy *shape*, not just policy *count*:

* **Cilium** compiles each `podSelector` peer into per-endpoint eBPF maps (`cilium_policy_<ep_id>`).
  Cost scales with (number of selected endpoints) x (number of peer identities).
* **Kindnet** compiles each selector into a single node-global `nftables` hash set.
  Cost is invariant to peer cardinality.

So a policy that is trivially cheap in one topology can be catastrophic in another, even with an
identical number of `NetworkPolicy` objects. That is precisely what these scenarios isolate.

---

## Scenario index

| Scenario | Snapshot | Gateway ingress peer | Sandbox ingress peer | Sandbox egress peer | Endpoints expanding N |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **A. Baseline (Open Gateway)** | [`scenario-a-baseline-open-gateway.yaml`](scenario-a-baseline-open-gateway.yaml) | *(any source)* | `group: gateway` | `group: gateway` + DNS | **0** |
| **B. Microsegmentation (Hub & Spoke)** | [`scenario-b-microseg-hub-spoke.yaml`](scenario-b-microseg-hub-spoke.yaml) | `group: sandbox` | `group: gateway` | `group: gateway` + DNS | **2** (gateway pods only) |
| **C. Mesh (Bidirectional)** | [`scenario-c-mesh-bidirectional.yaml`](scenario-c-mesh-bidirectional.yaml) | `group: sandbox` | **`group: sandbox`** | **`group: sandbox`** + gateway + DNS | **All 35,000** |

### Cluster-wide BPF policy entry cost

For $N$ sandbox identities, $P$ sandbox pods, and 2 gateway pods:

| Scenario | Formula | At $N$ = 3,500 | At $N$ = 35,000 |
| :--- | :--- | :---: | :---: |
| **A. Baseline** | $P \times 3$ | ~105,000 | ~105,000 |
| **B. Hub & Spoke** | $(2 \times N) + (P \times 3)$ | ~112,000 | ~175,000 |
| **C. Mesh (bidirectional)** | $P \times 2N$ | **245,000,000** | **2,450,000,000** |

Scenario C is four orders of magnitude heavier than B at the same identity count. This is the
structural claim the mesh sweep is designed to test empirically.

---

## Scenario details

### A. Baseline (Open Gateway)

The original benchmark topology. The gateway accepts ingress from **any** source; sandboxes are
restricted to talking only to the gateway and CoreDNS.

* **No policy anywhere expands a large peer set.** Every endpoint's BPF policy map holds ~3 entries.
* Used for the QPS latency sweep (50 / 100 / 200 / 500 QPS) in
  [Section 1](../../benchmark_results.md) and the identity cardinality sweep in Section 2.
* This is *not* true microsegmentation - any compromised pod in the namespace could reach the gateway.

### B. Microsegmentation (Hub & Spoke)

Tightens the gateway to accept ingress **only** from `group: sandbox`. This is the "Option A"
topology.

* Creates an **asymmetric blast wall**: the 2 gateway pods must expand all $N$ sandbox identities,
  while the 719 worker nodes still expand only 1 identity (the gateway).
* Requires `bpf-policy-map-max: 65536` (default `16384` overflows past ~16k identities).
* Used for the 4-tier microsegmentation sweep in
  [Section 4.B](../../benchmark_results.md).
* **Result:** `schedule_to_run` stayed flat at 1.31s - 1.53s across all tiers, because worker
  nodes never paid the expansion tax.

### C. Mesh (Bidirectional)

Sandboxes accept ingress from, and send egress to, **other sandboxes**. This models a flat
multi-tenant peer-to-peer topology.

* **Every** sandbox endpoint on **every** node must expand all $N$ sandbox identities, in both
  directions.
* Per-endpoint entries ~ $2N$; per-node entries ~ $2N \times$ (pods per node).
* Each newly created identity must be inserted into the policy map of every co-located endpoint,
  producing sustained incremental churn:
  $\text{updates/sec/node} = (\text{pods per node}) \times (\text{new identities/sec})$
* Designed to test whether Cilium's per-endpoint model degrades where Kindnet's node-global
  `nftables` set is invariant.

> [!CAUTION]
> **Do not run Scenario C at 35,000 identities (1 pod/ReplicaSet).** Bidirectional mesh needs
> ~$2N$ = 70,000 entries per endpoint, which exceeds `bpf-policy-map-max: 65536` and fails with an
> uninformative map overflow rather than a measurable latency curve. Cap the mesh sweep at
> 3,500 identities (10 pods/ReplicaSet).

---

## Known ceilings that confound results

These limits are properties of Cilium, not of the topologies above, but they can masquerade as
topology failures. Keep sweeps clear of them so results stay interpretable.

| Ceiling | Value | Symptom | Mitigation |
| :--- | :--- | :--- | :--- |
| Per-endpoint policy map | `bpf-policy-map-max` (default 16,384; ours 65,536) | Silent packet drops / map overflow | Keep $2N$ under the limit |
| Cluster identity space | **65,280** (24-bit minus 8-bit ClusterMesh, minus 256 reserved) | `no more available IDs in configured space` | Purge `CiliumIdentity` CRD between tiers |
| CNI ADD concurrency | `RateLimit: 0.5/s`, `RateBurst: 4`, `ParallelRequests: 4` | `[PUT /endpoint/{id}][429] putEndpointIdTooManyRequests` | Use `replicaset` workload type, not raw `pod` |

> [!NOTE]
> The identity ceiling is **cumulative across runs**, not per-run. A sweep that creates 35,000
> identities per tier will exhaust the space after two tiers. The sweep scripts purge the
> `ciliumidentities.cilium.io` CRD between tiers for this reason.

---

## Selecting a scenario at runtime

The live template
[`global-sandbox-policy.yaml`](../agentic-sandbox/manifests/global-sandbox-policy.yaml) switches on
`CL2_SANDBOX_PEER_MODE`:

| Value | Effect | Corresponding scenario |
| :--- | :--- | :--- |
| `gateway` *(default)* | Sandbox ingress/egress peer is `group: gateway` | A or B |
| `mesh` | Sandbox ingress **and** egress peer is `group: sandbox` | C |

```bash
# Scenario B - hub & spoke microsegmentation sweep
./run-identity-sweep.sh

# Scenario C - bidirectional mesh sweep (tiers capped at 3,500 identities)
./run-mesh-sweep.sh
```

---

## Run-to-scenario mapping

| Artifact prefix | Scenario | Notes |
| :--- | :--- | :--- |
| `*_QPS{50,100,200,500}` | A | QPS latency sweep |
| `*_{7,700,3500,35000}identities_*ppr` | A | Identity cardinality sweep |
| `*_{7,700,3500,35000}identities_*ppr_microseg` | B | 4-tier microsegmentation sweep |
| `*_35000identities_rawpods_microseg` | B | Raw pod direct burst; hit CNI 429 + identity ceiling |
| `*_{7,700,3500}identities_*ppr_mesh` | C | Bidirectional mesh sweep |
