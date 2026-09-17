# Scenario C: Kindnet Bidirectional Peer-to-Peer Mesh Sweep

This directory contains the empirical ClusterLoader2 benchmark results for Kindnet (`kube-network-policies` + `nftables`) executing the bidirectional mesh sweep across 35,000 pods on 720 worker nodes at 500 QPS.

In this topology ([`scenario-c-mesh-bidirectional.yaml`](../../../manifests/policy-scenarios/scenario-c-mesh-bidirectional.yaml)), every sandbox pod allows ingress from and egress to `group: sandbox`.

Under Kindnet and `kube-network-policies` (KNP), workload admission is decoupled from eager policy materialization. Rather than pre-compiling label selectors into per-endpoint kernel maps or selector-specific IP sets during container startup, KNP installs `nftables` steering rules that divert initial connection packets (`ct state new`) to a userspace evaluator via NFQUEUE. The userspace agent resolves source and destination IP addresses against Pod metadata (populated locally at container creation via containerd NRI hooks and across nodes via API informers), evaluates the `NetworkPolicy` label selectors, and issues an `NF_ACCEPT` verdict tagged with a conntrack label (`CTLabelAccept`). Subsequent packets match the conntrack label directly in the kernel fast path. As a result, container startup latency and node policy state remain independent of cluster-wide identity cardinality.

## Executed Tiers

* **`tier1-7-identities-5000ppr`**: 7 ReplicaSets with 5,000 pods each (7 unique label identities). Completed with 35,000/35,000 pods Running and 5 Phase 2 churn iterations.
* **`tier2-700-identities-50ppr`**: 700 ReplicaSets with 50 pods each (700 unique label identities). Completed with 35,000/35,000 pods Running. `schedule_to_run`: 3.27s P50 / 5.33s P99; total startup (`create_to_run`): 3.52s P50 / 5.55s P99.
* **`tier3-3500-identities-10ppr`**: 3,500 ReplicaSets with 10 pods each (3,500 unique label identities). Completed with 35,000/35,000 pods Running. `schedule_to_run`: 2.23s P50 / 2.79s P99; total startup (`create_to_run`): 2.34s P50 / 2.92s P99.
* **`tier4-35000-identities-rawpods`**: 35,000 raw pods (each with a globally unique `sandbox.id` label identity), injected directly at 500 QPS.
  - **Scale Achievement**: While Cilium is architecturally blocked from executing Tier 4 due to its 16-bit identity ceiling (65,280 identities) and per-endpoint map size overflow ($2 \times 35{,}000 = 70{,}000 > \texttt{bpf-policy-map-max: 65536}$), Kindnet admitted 100% of all 35,000 pods with 0 stranded pods and 0 CNI errors.
  - **Worker Queue Drain vs. Datapath Latency**: Injecting 35,000 unbuffered raw pods at 500 QPS resulted in the scheduler placing all pods across the 720 workers in under 50 seconds (~48 pods queued per worker node simultaneously). Tail pods waited in kubelet's sequential container runtime queue, resulting in 120.0s P50 / 421.4s P99 `schedule_to_run` (reflecting physical node worker queue drain under unbuffered shock, rather than kernel network policy overhead).
