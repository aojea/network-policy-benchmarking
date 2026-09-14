# Agentic Sandbox Benchmark Suite (720-Node / 35,000 Pod Scale)

This repository contains the automation scripts, ClusterLoader2 manifests, and benchmark tooling for evaluating **end-to-end pod startup latency and throughput** across **Cilium (eBPF)** and **Kindnet (NetworkPolicies)** at massive scale.

---

## 1. Environment & Architecture

- **Worker Fleet**: 720 worker nodes (`n2-standard-4`, 4 vCPUs per node) $\approx$ 2,880 vCPUs.
- **Control Plane**: 1 master node (`c4-standard-96`, 96 vCPUs).
- **Scale Target**: 35,000 Concurrent Agentic Sandbox Pods (~50 pods/node).
- **Runtime Stack**: Containerd `2.2.4` + `runc 1.3.5` + NRI enabled + Kubelet `kubeAPIQPS: 50`.
- **State Store**: `gs://kops-maspinwall-state`.

---

## 2. Directory Structure & Core Scripts

| Script / File | Purpose |
| :--- | :--- |
| **`create-cilium.sh`** | Provisions the 720-node Cilium cluster (`agentic-cilium.k8s.local`). |
| **`create-netpol.sh`** | Provisions the 720-node Kindnet cluster (`agentic-netpol.k8s.local`) with NRI socket mounted into `kindnet-cni`. |
| **`patch_yaml.py`** | Python helper that injects NRI, containerd 2.2.4, runc 1.3.5, and Kubelet QPS settings into generated Kops manifests. |
| **`run-test.sh`** | Invokes ClusterLoader2 with Prometheus metric scraping enabled (`--prometheus-scrape-kubelets=true`). |
| **`run-qps-sweep.sh`** | Dynamically adjusts control-plane QPS/burst settings on `c4-standard-96` and runs benchmarks across QPS tiers (50, 100, 200, 500). |
| **`run-identity-sweep.sh`** | Sweeps identity cardinality across 4 tiers (7 to 35,000 identities) in hub & spoke microsegmentation. |
| **`run-mesh-sweep.sh`** | Executes bidirectional mesh topology sweep evaluating peer-to-peer BPF policy expansion. |
| **`run-full-cilium-sweep.sh`** | Automated end-to-end script: Tears down NetPol cluster $\rightarrow$ Provisions Cilium cluster $\rightarrow$ Executes QPS sweep. |
| **`run-full-netpol-sweep.sh`** | Automated end-to-end script: Tears down Cilium cluster $\rightarrow$ Provisions Kindnet cluster $\rightarrow$ Executes QPS sweep. |
| **`teardown-cluster.sh`** | Safely deletes the active Kops cluster and cleans up remaining cloud resources. |
| **`manifests/policy-scenarios/`** | Reproducibility snapshots and cost models for Scenarios A (Open Gateway), B (Hub & Spoke), and C (Mesh). |
| **`benchmark_results.md`** | **Source of Truth** document containing all empirical latency matrices, CPU utilization data, and architectural bottleneck analyses. |

---

## 3. How to Run Benchmarks

### Prerequisites
Ensure your shell environment has access to Kops, kubectl, and GCP credentials:
```bash
export KOPS_STATE_STORE="gs://kops-maspinwall-state"
export KUBECONFIG="${HOME}/.kube/config"
```

### Option A: Run Full Automated Cilium Benchmark
To tear down any active cluster, provision Cilium, and execute a full QPS sweep (50, 100, 200, 500 QPS):
```bash
./run-full-cilium-sweep.sh
```

### Option B: Run Full Automated Kindnet Benchmark
To tear down any active cluster, provision Kindnet (with NRI socket mounted), and execute a full QPS sweep:
```bash
./run-full-netpol-sweep.sh
```

### Option C: Run a Single Targeted QPS Test (e.g. 500 QPS)
1. Edit `run-qps-sweep.sh` to set the desired QPS array:
   ```bash
   QPS_VALUES=(500)
   ```
2. Execute the sweep:
   ```bash
   ./run-qps-sweep.sh
   ```

## 4. Artifacts & Directory Organization

All benchmark artifacts are organized to correspond directly with the **[benchmark_results.md](benchmark_results.md)** master report:

```
artifacts_pods/ (also symlinked at ~/artifacts_pods)
├── cilium/
│   ├── qps-50/                       # 50 QPS verified run
│   ├── qps-100/                      # 100 QPS verified run
│   ├── qps-200/                      # 200 QPS verified run
│   └── qps-500/
│       ├── verified-run/             # Primary 500 QPS benchmark run
│       └── repeat-run/               # Repeat validation run
├── kindnet/
│   ├── baseline-sweep/
│   │   ├── qps-50/                   # Baseline 50 QPS (Standard Informer)
│   │   ├── qps-100/                  # Baseline 100 QPS (Standard Informer)
│   │   ├── qps-200/                  # Baseline 200 QPS (Standard Informer)
│   │   └── qps-500/                  # Baseline 500 QPS (Standard Informer)
│   └── 500qps-optimizations/
│       ├── 1-nri-socket-mounted/                 # Step 1: Mounted /var/run/nri (9.78s P50)
│       ├── 2-nri-plus-apf-tuned-150shares/       # Step 2: Tuned APF 150 shares (6.47s P50)
│       ├── 3-nri-plus-high-kubelet-apf-200shares/# Step 3: APF 200 shares (46.53s P99)
│       ├── 4-reverted-default-apf/               # Step 4: Verification with default APF (20.20s P50)
│       └── 5-v1.0.1-plus-nri-plus-apf-exempt/    # Step 5: v1.0.1 + NRI + APF Exempt (2.35s P50 / 9.72s P99)
└── archive/
    ├── 2026-07-27-initial-runs/      # Initial test runs from 2026-07-27
    ├── intermediate-debug-runs/      # Intermediate test runs during tuning
    └── node_limited/                 # Initial node-limited experiments
```

Key JSON metric files within each run folder:
- **`PodStartupLatency_TotalPodStartupLatency_*.json`**: Contains `create_to_schedule`, `schedule_to_run`, and total `pod_startup` latency percentiles (P50, P90, P99).
- **`Phase1SchedulingThroughput-CreateToRun_*.json`**: Tracks end-to-end pod creation-to-running throughput.
- **`GenericPrometheusQuery Worker Node CPU Utilization_*.json`**: Contains node CPU utilization metrics and 1-minute sliding window instantaneous peak CPU spikes.
