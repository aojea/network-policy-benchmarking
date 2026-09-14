# Agentic Sandbox Range - Run 3 HPT Benchmark Parameters

## Environment Variables / CL2 Config
*   `CLUSTER_NAME="agentic-scenario-maspinwall"` (1,005 nodes, us-central1-c, project `gke-maspinwall-dev-2`)
*   `CL2_WORKLOAD_TYPE="replicaset"`
*   `CL2_MAX_SANDBOXES=50000`
*   `CL2_BURST=5000`
*   `CL2_TEST_NUM_NODES=1000`
*   `CL2_QPS=100` # Target scheduling rate
*   `CL2_CHURN_ITERATIONS=3` # Total 5,000 pods per churn wave
*   `CL2_NETWORK_POLICY_TYPE="Global"`
*   `CL2_USE_HT_SCHEDULER=true` (forces pod spec `schedulerName: gke.io/high-throughput-scheduler`)
*   `--k8s-clients-number=20`

## GKE Control Plane Tuning (kap cluster edit --psed)
MPA authorization token validated the following control plane parameter overrides:
*   `components.controller_manager.qps: 300`
*   `components.scheduler.qps: 300`
*   `components.scheduler.enable_high_throughput_profile: true`
*   `components.apiserver.event_ttl_sec: 300`
