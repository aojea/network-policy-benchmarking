# Scenario C: Bidirectional Peer-to-Peer Mesh Sweep

This directory contains the empirical ClusterLoader2 benchmark results for the bidirectional mesh sweep across 35,000 pods on 720 worker nodes at 500 QPS.

In this topology ([`scenario-c-mesh-bidirectional.yaml`](../../../manifests/policy-scenarios/scenario-c-mesh-bidirectional.yaml)), every sandbox pod allows ingress from and egress to `group: sandbox`, requiring each endpoint to expand all $N$ peer identities in both directions ($\sim 2N$ BPF policy map entries per container endpoint).

## Executed Tiers
* **`tier1-7-identities-5000ppr`**: 7 identities ($\sim 14$ BPF entries/endpoint). Completed with full metrics.
* **`tier2-700-identities-50ppr`**: 700 identities ($\sim 1,400$ BPF entries/endpoint). Completed with full metrics.
* **`tier3-3500-identities-10ppr`**: 3,500 identities ($\sim 7,000$ BPF entries/endpoint, $\sim 350,000$ BPF entries/node). Completed with full metrics.

## Omission of Tier 4 (35,000 Identities / 1 Pod per RS)
Tier 4 was **deliberately excluded and not executed**.

A bidirectional mesh at 35,000 unique identities requires:
$$\text{BPF Entries per Endpoint} \approx 2 \times 35{,}000 = 70{,}000$$

This exceeds Cilium's maximum configurable 16-bit policy map ceiling:
$$\texttt{bpf-policy-map-max: 65536}$$
*(and far exceeds Cilium's default limit of $\texttt{16384}$, which overflows past 8,192 mesh identities).*

Attempting to run 35,000 identities under this topology would trigger immediate eBPF map insertion failures and packet drops on every worker node rather than producing a measurable latency curve. As documented in [`run-mesh-sweep.sh`](../../../scripts/run-mesh-sweep.sh), the preflight guard actively skips any tier where $2N \ge \texttt{bpf-policy-map-max}$.
