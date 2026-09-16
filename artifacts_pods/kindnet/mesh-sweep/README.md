# Scenario C: Kindnet Bidirectional Peer-to-Peer Mesh Sweep

This directory contains the empirical ClusterLoader2 benchmark results for Kindnet (`kube-network-policies` + `nftables`) executing the bidirectional mesh sweep across 35,000 pods on 720 worker nodes at 500 QPS.

In this topology ([`scenario-c-mesh-bidirectional.yaml`](../../../manifests/policy-scenarios/scenario-c-mesh-bidirectional.yaml)), every sandbox pod allows ingress from and egress to `group: sandbox`.

Under Kindnet's architecture, this selector does not compile into per-endpoint policy maps. Instead, all sandboxes on each node evaluate against a single, node-global kernel hash set (`@set_sandboxes_group_sandbox`) containing the IP addresses of matching pods. As a result, datapath evaluation complexity remains strictly $O(1)$ at each node regardless of identity cardinality.

## Executed Tiers

* **`tier1-7-identities-5000ppr`**: 7 ReplicaSets with 5,000 pods each (7 unique label identities). Completed with 35,000/35,000 pods Running and 5 Phase 2 churn iterations.
* **`tier2-700-identities-50ppr`**: 700 ReplicaSets with 50 pods each (700 unique label identities). Completed with 35,000/35,000 pods Running. `schedule_to_run`: 3.27s P50 / 5.33s P99; total startup (`create_to_run`): 3.52s P50 / 5.55s P99.
* **`tier3-3500-identities-10ppr`**: 3,500 ReplicaSets with 10 pods each (3,500 unique label identities). Completed with 35,000/35,000 pods Running. `schedule_to_run`: 2.23s P50 / 2.79s P99; total startup (`create_to_run`): 2.34s P50 / 2.92s P99.
* **`tier4-35000-identities-rawpods`**: 35,000 raw pods (each with a globally unique `sandbox.id` label identity), injected directly at 500 QPS.
  - **Scale Achievement**: While Cilium is architecturally blocked from executing Tier 4 due to its 16-bit identity ceiling (65,280 identities) and per-endpoint map size overflow ($2 \times 35{,}000 = 70{,}000 > \texttt{bpf-policy-map-max: 65536}$), Kindnet admitted 100% of all 35,000 pods with 0 stranded pods and 0 CNI errors.
  - **Worker Queue Drain vs. Datapath Latency**: Injecting 35,000 unbuffered raw pods at 500 QPS resulted in the scheduler placing all pods across the 720 workers in under 50 seconds (~48 pods queued per worker node simultaneously). Tail pods waited in kubelet's sequential container runtime queue, resulting in 120.0s P50 / 421.4s P99 `schedule_to_run` (reflecting physical node worker queue drain under unbuffered shock, rather than kernel network policy overhead).
