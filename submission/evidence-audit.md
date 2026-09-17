# Evidence Audit

Research notes for the authors, not manuscript prose. Audited 2026-09-16.

## Snapshot Boundary

- Earlier local snapshot: 1,704 artifact files, 1,210 parsed JSON files, 52 startup
  reports. See [inventory.json](inventory.json) and
  [extracted-results.md](extracted-results.md).
- Fetched repository: `michaelasp/network-policy-benchmarking`, commit
  `e8af592c3f3bb2b2c713d4bc745fdaf0f294f3e6`: 1,809 artifact files,
  1,285 parsed JSON files, 81,308 metric values, 55 startup reports in 62
  configured/report directories. See [upstream/inventory.json](upstream/inventory.json)
  and [upstream/extracted-results.md](upstream/extracted-results.md).
- Three new startup-report contents, verified by SHA-256 comparison with the
  local JSON inventory: Cilium mesh tiers 1, 2, and 3. Reorganized copies of
  earlier runs are not independent repetitions. Do not sum the two inventories.
- The current checkout is `f998224`; the numerical inventory remains pinned to
  `e8af592`. The two subsequent commits add evidence notes, not metric reports.
  The extracted report uses workspace-relative links. The earlier extraction
  is historical.
- The corrected upstream inventory includes three diagnostic-only mesh attempts
  omitted by the original configuration/report-based run detection. Seven
  attempts have no startup report: four configuration/metadata-only attempts
  and three hook-only mesh attempts. Their post-test logs contain commands but
  no captured profiles or allocator failure messages. Missing outcome evidence
  is not proof of failure or success.
- No parse/schema errors were reported. This validates extraction, not experiment
  design, provenance, completeness, or metric semantics.
- Follow-up commit `0442dce` adds the
  [raw-Pod outcome record](../artifacts_pods/cilium/microsegmentation/tier4-35000-identities-rawpods/README.md).
  Commit `f998224` adds the
  [mesh sweep explanation](../artifacts_pods/cilium/mesh-sweep/README.md).
  These notes resolve the raw-Pod completion outcome and why mesh tier 4 has
  no results; neither adds latency reports to the pinned JSON inventory.

## New Mesh Evidence

Source directories: `artifacts_pods/cilium/mesh-sweep/tier{1,2,3}-*`.
All target 35,000 Pods; each records five churn rounds. Identity counts below
are intended label configurations, not measured Cilium identity counts.

| Intended identities | Pods per ReplicaSet | After scheduling P50 (s) | After scheduling P99 (s) | End-to-end P99 (s) | Initial setup + wait (s) | JUnit failures |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 7 | 5,000 | 1.412 | 6.767 | 33.534 | 192.109 | 0 |
| 700 | 50 | 1.424 | 2.934 | 28.739 | 137.947 | 0 |
| 3,500 | 10 | 1.413 | 2.279 | 21.730 | 109.718 | 0 |

Interpretation limits:

- These observations do not support increasing startup latency with increasing
  identity cardinality. They also do not establish identity-independent scaling:
  controller fan-out and per-object burst size change with each tier.
- The 35,000-identity mesh tier was deliberately excluded and never executed,
  as documented in `f998224`; it is not a failed or lost-metrics mesh run.
  There is still no matched Kindnet identity/mesh sweep. Do not draw a KNP curve
  from the isolated tuning run.
- A configured mesh policy is not a generated all-to-all traffic workload.
  Startup measurements do not measure connections/s, policy-ready time, or
  packet-filtering throughput.
- Passing JUnit establishes the recorded test cases passed; it is not a
  measurement of permitted and forbidden connectivity at each transition.

## Figure 2 And Reported Failures

The authors identify
[figures/fig2_identity_cardinality_sweep.png](../figures/fig2_identity_cardinality_sweep.png)
and the [mesh sweep notes](../artifacts_pods/cilium/mesh-sweep/README.md) as
the intended scaling evidence. The new notes clarify that the figure combines
an observed raw-Pod failure with an analytically excluded mesh configuration.
Those are distinct from worsening latency across completed identity tiers.
Preserve both findings, with their evidence types explicit.

| Figure element | Traceability at this snapshot | Treatment |
| --- | --- | --- |
| Blue 5.93, 5.42, 4.68, 1.99 s bars | Match open-gateway identity-sweep P99s, not the mesh P99s above; legend mentions hub-and-spoke | Correct scenario labels before use |
| Green 9.72 s bar | Matches the final Kindnet tuning bundle after scheduling | Identify its actual run and bundled settings |
| Green 9.75, 9.80, 9.85 s tier bars | Present in the narrative summary; matching Kindnet identity/mesh runs not located | Author-reported until source runs are supplied |
| Red HTTP 429 / 65k cap bar | Raw-Pod failure documented in `0442dce`; mesh tier 4 explicitly not executed in `f998224` | Split into aborted raw-Pod completion counts and predicted mesh capacity exclusion; neither has a numeric P99 |

The other chart,
[figures/fig2_topological_scaling_p99.png](../figures/fig2_topological_scaling_p99.png),
reports 94.3 s overflow and describes KNP as node-global kernel sets. Neither
that number nor that mechanism follows from the inspected mesh reports and
NFQUEUE implementation. Keep the original images intact as author input; do
not reuse them unchanged as verified paper figures.

### Analytical Mesh Capacity Exclusion

The [mesh README](../artifacts_pods/cilium/mesh-sweep/README.md) states that
tier 4 was deliberately excluded. This is corroborated by
[scripts/run-mesh-sweep.sh](../scripts/run-mesh-sweep.sh): `MESH_SWEEPS` is
`(5000 50 10)`, omitting one Pod per ReplicaSet. Its additional guard reads
`bpf-policy-map-max` from the Cilium ConfigMap, falls back to 16,384 if unset,
and skips a listed tier when its estimated entry demand reaches the limit.
This is source evidence of the experiment design, not a captured skip message
from an attempted tier-4 execution.

The [scenario policy](../manifests/policy-scenarios/scenario-c-mesh-bidirectional.yaml)
allows sandbox peers on TCP port 80 in both directions. Under the assumed
per-endpoint materialization of one entry per peer identity per direction,
the sandbox contribution to map demand is approximately:

$$
E_{\mathrm{endpoint}} \approx 2I,\qquad
E_{\mathrm{node}} \approx 2IP_{\mathrm{local}}.
$$

Here $I$ is distinct selected peer identities, not Pod count, and
$P_{\mathrm{local}}$ is local endpoints. Gateway, DNS, reserved identities,
and other policy entries consume additional space. At $I=35{,}000$ the
sandbox estimate alone is 70,000 entries per endpoint, above both 16,384 and
65,536. At $I=3{,}500$ and 50 local endpoints it is about 350,000 entries
per node. These are derived counts, not measured map occupancy or byte sizes.

- This adds a useful **topology-dependent capacity argument**, even when
  latency stays low in all executed tiers. Scalability includes admissible
  state size, not only the slope of a latency curve.
- The guard rejects $I=8{,}192$ for a 16,384-entry limit and $I=32{,}768$
  for a 65,536-entry limit even before extra entries. These are thresholds
  of this conservative `>=` guard, not measured exact overflow points.
- Pin the Cilium version and verify its configurable maximum and policy
  representation before calling 65,536 a hard ceiling. A script's setting
  does not establish a universal 16-bit limit of eBPF maps.
- Do not conflate the reported **65,536 policy entries per endpoint** with
  the **65,280 allocatable security identities per cluster** in the raw-Pod
  diagnosis. Bidirectional entries multiply materialized permissions, not
  the number of allocated identities.
- NFQUEUE avoids this particular eager per-endpoint permission expansion in
  the inspected design. It retains metadata and conntrack costs and pays
  userspace decision work on queued traffic. This motivates the architectural
  comparison but does not yet measure a Kindnet mesh capacity advantage.

For the paper figure, show executed-tier latency separately from a capacity
panel with the derived demand and versioned limit. Label tier 4 "not run:
predicted map-capacity excess". Do not claim observed insertion failures or
packet drops in a configuration that was never executed.

### Documented Raw-Pod Failure

The [raw-Pod outcome record](../artifacts_pods/cilium/microsegmentation/tier4-35000-identities-rawpods/README.md)
belongs to the direct-burst microsegmentation experiment,
not the three completed mesh tiers. It documents an aborted experiment with
**29,306 Running and 5,694 permanently stranded Pods**, and explicitly states
that **no final latency results were generated**. Its diagnosis identifies:

- Concurrent CNI ADD calls encountering the local Cilium REST API HTTP 429 limit.
- Cumulative identity allocation during creation/churn reaching the 65,280
  allocatable cluster-local identity limit, with the reported error
  `no more available IDs in configured space`.

Use this as a documented experiment outcome and retain the authors' diagnosis.
For causal attribution, request the underlying logs, allocated-identity history,
effective limiter configuration, and image provenance. Do not require a rerun
just because the aborted test produced no percentile file. Failure is a valid
outcome and should remain visible. It does not establish a measured 94.3-second
P99, nor establish that every 35,000-identity topology fails.

Three distinct mechanisms need separate evidence:

- **Identity-space exhaustion:** capture allocated identities over time,
  identity garbage-collection behavior, and the allocator error. A run with
  35,000 live Pods can involve more historical identities, but that must be
  measured. Bidirectional policy entries do not themselves double the number
  of security identities. The documented cluster-local identity range is a
  configuration/representation limit, not proof this experiment reached it.
- **Endpoint/CNI rate limiting:** identify the component returning HTTP 429,
  effective limiter settings, attempted endpoint rate, and retries. This can
  limit a burst without demonstrating selector fan-out as the cause.
- **Policy-map expansion:** capture actual policy-map occupancy, map limit,
  selector fan-out, update durations, and any insertion error. Distinguish this
  from the identity allocator's numeric namespace.

Cheapest next step: verify the mesh capacity calculation against the tested
Cilium version and an existing lower-tier map dump, and recover diagnostics
behind the raw-Pod failure and the Kindnet tier run directories. No 35k-mesh
run needs to be recovered: the notes explicitly establish it was not executed.
No cluster rerun is needed merely to establish provenance. Retain completed
tiers, analytical exclusions, and aborted runs as separate evidence categories.

## Existing Identity Evidence

Cilium September 10 sweep, QPS tier labeled 500, 35,000 desired Pods.
Source families in the fetched snapshot: `cilium/identity-sweep` and
`cilium/microsegmentation`. All eight reported suites have zero JUnit failures.

| Intended identities | Open-gateway after-scheduling P99 (s) | Hub-and-spoke after-scheduling P99 (s) |
| ---: | ---: | ---: |
| 7 | 5.930 | 6.370 |
| 700 | 5.416 | 4.759 |
| 3,500 | 4.685 | 4.899 |
| 35,000 | 1.990 | 2.033 |

- This is counterevidence to a simple claim that many identities alone cause
  Cilium startup collapse. The 35,000 tier completes with low observed latency.
- Label cardinality, identity allocation rate, peer-set density, endpoint count,
  and attempted new connections are different independent variables.
- Saved configurations, not the current generator, define these runs. They use
  the default scheduler and replace 5,000 Pods per churn round. Confirm whether
  the replacements reuse label sets before calling this fresh-identity churn.
- The aborted raw-Pod run uses a raw-Pod template; do not conflate it with the
  successful one-Pod-per-ReplicaSet run. Its 29,306 Running / 5,694 stranded
  outcome is now documented in `0442dce`; a final latency report does not exist.

## QPS And Tuning Evidence

Primary saved Cilium QPS runs and Kindnet baseline runs, July 28-29.
These are observed implementation/configuration results, not isolated NFQUEUE
versus eBPF microbenchmarks. Verify exact binaries and effective flags.

| QPS tier | Cilium after-scheduling P50/P99 (s) | Kindnet baseline after-scheduling P50/P99 (s) | Cilium / Kindnet end-to-end P99 (s) |
| ---: | ---: | ---: | ---: |
| 50 | 1.246 / 4.065 | 1.152 / 4.833 | 4.089 / 4.855 |
| 100 | 1.251 / 1.788 | 1.621 / 7.143 | 1.814 / 7.378 |
| 200 | 1.267 / 1.845 | 8.854 / 59.347 | 2.285 / 59.485 |
| 500 | 1.490 / 5.482 | 7.922 / 57.068 | 11.160 / 57.629 |

- QPS 50 and 100 have two JUnit failures each in both families. All four are
  `WaitForRunningPods - WaitForOldPodsDeleted-Final ... context deadline
  exceeded` while 5,024-19,999 churn Pods were still terminating: a teardown
  deletion timeout, not a startup failure. Startup percentiles are complete;
  deletion latency at those tiers is unmeasured.
- Cilium's separate QPS-500 repeat has after-scheduling P99 4.257 s and
  end-to-end P99 12.404 s. Keep the two runs visible, not selectively choose one.
- Kindnet's final tuning bundle, named `5-v1.0.1-plus-nri-plus-apf-exempt`, has
  after-scheduling P50/P99 2.345/9.718 s, but end-to-end P99 **95.790 s** and
  create-to-schedule P99 **94.555 s**. Improved post-scheduling behavior does not
  imply improved end-to-end tail latency.
- Earlier tuning steps have after-scheduling P99 65.913, 50.434, 46.526, and
  102.591 s respectively. Version, runtime integration, and API fairness settings
  are changed together. This is a tuning chronology, not a clean NRI ablation.
- Do not call creation/churn results static dataplane parity. There is no such
  inference from these latency summaries.

## Metric Discipline

- `schedule_to_run` includes runtime and container startup work. It is not
  NFQUEUE verdict latency, identity dissemination latency, or policy-ready time.
- Report `pod_startup` separately from its components. Percentiles of components
  cannot be added or subtracted to reconstruct percentiles of the sum.
- A configured QPS is an offered object-operation rate. A ReplicaSet operation
  can create many Pods. Report achieved Pods/s and the actual operation type.
- Initial setup plus wait is a phase-duration cross-check, not the per-Pod
  latency distribution. Five churn rounds in one run are not five independent
  cold-cluster trials.
- The September node CPU query is `*_instantaneous_node_cpu_cores`
  (mean/p99/max across nodes over the run, plus `max_kubelet_cpu_cores`); the
  July Kindnet baseline uses a `rate(...[1m])`-based `mean_node`/`p99_node`
  query. Do not compare the two families' CPU rows as like for like. A
  `max_kindnetd_cpu_cores` term exists in the saved query but returned no
  samples in any run; there is no policy-agent CPU series anywhere.
- JSON percentiles are insufficient to reconstruct a CDF or valid confidence
  interval over Pods. Plot the available quantiles and individual trials; do
  not synthesize raw samples or average P99s into a pooled P99.
- Completion counts and failed/pending Pods must accompany survivor latencies.
  An all-zero startup report in `reports/run2_hpt` with JUnit failures is not
  evidence of zero startup latency.

## Gap Scan (September 17)

Both repositories were scanned for the evidence the reviewer critique asked
for. Recovered values are now in the manuscript (Table 2, Section 6.2, 6.5,
6.7, 8.1); what is still missing is in Table 4 of the paper.

### Recovered from artifacts

| Run | Phase-1 Pods/s P50 / P90 | Node CPU mean / P99 (cores) | Pod LIST P99 (s) |
| --- | ---: | ---: | ---: |
| Cilium gateway 7 / 700 / 3,500 / 35,000 | 284/377, 317/364, 316/372, 170/182 | 0.52/0.71, 0.51/0.69, 0.54/0.69, 0.56/0.81 | 18.8, 14.6, 18.6, 28.8 |
| Cilium spoke 7 / 700 / 3,500 / 35,000 | 0/327, 323/398, 321/373, 169/181 | 0.51/0.69, 0.61/0.86, 0.54/0.67, 0.55/0.78 | n/a (not extracted) |
| Cilium mesh 7 / 700 / 3,500 | 277/376, 302/351, 328/385 | 0.54/0.72, 0.54/0.67, 0.63/0.77 | 14.6, 14.0, 18.8 |
| **KNP mesh 7 / 700 / 3,500 / 35,000 (Raw)** | **0/310, 124/134, 103/106, 0/97 (841 max)** | **0.52/0.66, 0.48/0.61, 0.45/0.56, 0.66/0.86** | **n/a (not extracted)** |
| Cilium QPS 500 verified | 180/412 | not collected | 7.8 |
| Kindnet QPS 500 baseline | 233/262 | 0.40/0.46 (rate query) | 2.8 |
| Kindnet tune 5 | 190/225 | 0.63/0.79 | 7.6 |

Sources: `Phase1SchedulingThroughput_*.json` (`perc50`, `perc90`),
`GenericPrometheusQuery Worker Node CPU Utilization_*.json`,
`APIResponsivenessPrometheus_simple_*.json` (cluster-scoped `pods` `LIST`).
The 35,000-ReplicaSet tiers halve Phase-1 throughput and raise Pod LIST P99;
worker CPU is flat across identity tiers in both families.

### Kindnet mesh sweep (5b152f2), validated September 17

All four tiers were re-extracted from the JSON; the values below supersede
any transcription from `artifacts_pods/kindnet/mesh-sweep/README.md`.

| Tier | JUnit | `schedule_to_run` P50 / P99 (s) | `pod_startup` P50 / P99 (s) | `create_to_schedule` P99 (s) | Phase-1 Pods/s P50 / P90 |
| --- | --- | ---: | ---: | ---: | ---: |
| 1: 7 ids, 5,000 ppr | 0 | 38.946 / 151.479 | 39.630 / 152.139 | 1.412 | 0 / 310 |
| 2: 700 ids, 50 ppr | 0 | 3.273 / 5.331 | 3.515 / 5.553 | 0.418 | 124 / 134 |
| 3: 3,500 ids, 10 ppr | 0 | 2.234 / 2.791 | 2.341 / 2.918 | 0.231 | 103 / 106 |
| 4: 35,000 raw Pods, mesh | 2 (startup P90 SLO: 357.7 s > 300 s) | 120.003 / 421.410 | 139.557 / 499.865 | 106.691 | 0 / 97 (max 841) |

- Tiers 1-3 use the same generator (`SandboxPeerMode: mesh`, same ppr) as the
  Cilium mesh tiers and are a matched comparison. Tier 4 is **not matched**:
  Cilium's mesh tier 4 was never run, and Cilium's raw-Pod run
  (`microsegmentation/tier4-35000-identities-rawpods`) has no `SandboxPeerMode`
  (hub-and-spoke policy).
- Tier 1 is a 22x P99 gap against Cilium's 6.767 s on the identical
  configuration, consistent with the July Kindnet 6x5,000 runs (57 s, tuned
  9.7 s post-scheduling / 95.8 s total). The artifacts do not explain it.
- KNP tiers 2-3 created Pods at 124/103 Pods/s versus Cilium's 302/328 on the
  same configured 500 QPS and identical control-plane settings (cluster specs
  differ only in CNI, kube-proxy, and CIDRs). Cause unrecorded; it lowers the
  per-node burst and therefore the KNP tail.
- Tier 4 README claims "scheduler placed all pods in under 50 seconds" and
  "0 CNI errors": `create_to_schedule` P99 is 106.7 s, and the CNI-latency
  query returned no samples. Neither claim is usable. The JUnit SLO failures
  and the tier-1 latency are omitted from that README.
- Node CPU: 0.52/0.66, 0.48/0.61, 0.45/0.56, 0.66/0.86 mean/P99 cores; tier-1
  and tier-4 max 2.19 and 2.55 cores.
- All six `GenericPrometheusQuery Kube Network Policies *` files and the
  `Kubelet CNI Plugin Operations Latency` file have `"dataItems": null` in
  every tier. `scripts/query-kindnet-metrics.sh` documents the cause: the
  deployed Kindnet build has no metrics port. Agent CPU, memory, verdict rate,
  processing latency, and drops therefore remain **absent**.
- `Sandbox Pod Density Per Node` reports `max_pods_per_node: 23789` in tier 4
  (mean 88.8, P99 56): almost certainly pending Pods bucketed under an empty
  node label, not a real node. Do not cite.

### Enforcement checks (validated September 17)

- **Positive, per Pod, at scale**: `manifests/agentic-sandbox/manifests/sandbox-pod.yaml`
  and `sandbox-replicaset.yaml` carry a `wait-for-gateway` init container that
  loops `nc -z -w 1 $GATEWAY_SERVICE_0_SERVICE_HOST $PORT` until a TCP connect
  succeeds, and logs `Latency: N ms`. With `default-deny-policy.yaml`
  (`ApplyDefaultDenyPolicy: true` in every archived run),
  `global-sandbox-policy.yaml` (sandbox egress to `group: gateway` TCP 80) and
  `gateway-policy.yaml` (gateway ingress from `group: sandbox`), a sandbox
  reaches `Running` only after one permitted connection was admitted by the
  source node's egress evaluation and the gateway node's ingress evaluation.
  Consequence: `schedule_to_run` is an upper bound on first-permitted-
  communication latency and includes propagation of the new Pod IP to the
  gateway node. Caveats: sandbox-to-gateway path only; no forbidden path
  exercised; under KNP fail-open a saturated queue would also pass; the
  per-Pod `Latency:` log lines were not collected.
- **Negative, once per cluster**: `scripts/verify-netpol.sh` (two Pods, open ->
  default-deny ingress blocked -> explicit allow succeeds, 5 s propagation
  waits). Run at cluster creation on an idle cluster per the operator; output
  not archived; not invoked by any run script.
- The earlier manuscript sentence "schedule_to_run ... is not a measurement of
  policy programming or first permitted communication" was wrong and is
  corrected in the paper.

### Recovered from the implementation repository

- `docs/testing/README.md` (April 2024, three nodes, no versions recorded):
  ApacheBench 10,000 requests at concurrency 1,000 completed at 2,317 req/s,
  P50 5 ms, P99 3,080 ms, connect-dominated, with `nf_conntrack: table full`
  at `nf_conntrack_max=262144`. Charts: `packet_process_duration_microseconds`
  P50 80-120 us, P99 170-630 us; `rate(packet_count[30s])` peak ~8,000/s per
  node. Indicative only; cited as an order-of-magnitude bound on one node's
  verdict rate.
- PR 218 single-client integration logs: 10k records 643 ms / 35 MB heap /
  1 MB bolt; 40k records at 30k writes/s 6.58 s / 174 MB / 8 MB with watch
  stalls reported above 40k; 10M records at 1,024 writes/s 43 ms / 24.7 GiB
  heap / 1.25 GiB bolt in 9,828 s. LRU sized to hold all records.
- `pkg/cmd/cmd.go` `--fail-open` default `true`; `pkg/dataplane/controller.go`
  sets the NFQUEUE bypass flag when fail-open, queue length 1,024; denied
  packets never receive the conntrack label. No rate limiter or deny cache.
- `pkg/networkpolicy/networkpolicy.go`: a `nil` (unresolved) peer matches only
  `ipBlock`; under default deny an unknown remote source is dropped until
  metadata arrives (fail-closed, availability delay).
- `plugins/iptracker/iptracker_networkpolicy.go` `ManagedIPs` returns
  `divertAll=true`: the IPTracker flavor queues all forwarded traffic.
- Cilium v1.20.1 source: `bpf-policy-map-max` default 16,384, clamped to
  [256, 65,536]. The value effective on `agentic-cilium.k8s.local` is **not
  archived**: `run-mesh-sweep.sh` reads the `cilium-config` ConfigMap at run
  time (fallback 16,384) and its header comment records 65,536. Independent
  corroboration: `gateway-policy.yaml` admits ingress from every sandbox
  identity, so the gateway endpoints needed ~35,000 entries in the completed
  unidirectional 35k tiers; behind a 16,384 map the `wait-for-gateway` gate
  would have stranded Pods. All 35,000 reached Running, so the effective limit
  was >= 35,000 unless aggregation applied (v1.20.1 `pkg/policy/aggregate.go`
  aggregates only into cluster/clustermesh/world/remote-node buckets). A
  `cilium-dbg bpf policy get` dump on a gateway node would settle it.
- Cilium issue 7515 closed by PR 44900 (v1.20.0). The archived v1.18.6
  700-identity directory has only `cl2-metadata.json` and the generated config;
  the 34,981/19 counts come from `benchmark_results.md`.

### Confirmed absent

- Memory metrics of any kind; policy-agent CPU, verdict rate, processing
  latency, queue/user drops (six KNP queries added in the mesh sweep all
  returned no samples; the Kindnet build exposes no metrics port); Cilium
  pprof (all `PodPeriodicCommand` pprof captures failed with connection
  refused); kubelet CNI operation latency (query returned no samples).
- A matched pair at 35,000 identities (Cilium raw-Pod mesh, or KNP
  1-Pod-per-ReplicaSet), and any repeat trial for any mesh tier.
- An explanation for the KNP tier-1 151 s tail and the 2.5-3x lower KNP
  Phase-1 throughput; per-Pod `wait-for-gateway` latencies.
- Policy-map dumps (`cilium-dbg bpf policy get`), the effective
  `cilium-config`, image digests, effective KNP flags per run. The install
  manifest pins `kube-network-policies:v1.1.0` with `--nfqueue-id=98` and no
  `--fail-open`; the cluster spec uses kops `kindnet: {}` and
  `scripts/create-netpol.sh` patches `kindnet:v1.0.1`.
- Logs for the v1.18.6 and raw-Pod aborts; archived `verify-netpol.sh` output.

## Claim Gate

| Proposed claim | Current status | Minimum additional evidence |
| --- | --- | --- |
| Userspace semantic evaluation with kernel-cached accepted decisions | Supported by current source inspection | Pin the measured binary to that implementation |
| Less eager identity-related work at endpoint admission | Partially supported: KNP mesh P99 does not rise from 700 to 3,500 identities (5.33 -> 2.79 s) and the 35k mesh tier completes; but tier 1 is 151 s vs Cilium 6.8 s, throughput is 2.5-3x lower, one trial per tier | Repeat tiers 2-3 on both clusters; explain tier-1 tail; equalize achieved Pods/s |
| Dense mesh exceeds per-endpoint policy-map capacity | Analytical exclusion documented in `f998224`; 65,536 limit documented only in a script comment, corroborated by the completed unidirectional 35k tiers | Map dump and ConfigMap on one gateway node |
| Better than Cilium at high identity cardinality | **Mixed.** KNP completes the 35k mesh tier Cilium excluded (35,000 Running, 0 stranded) but at 421 s P99 with 2 SLO failures; the Cilium raw-Pod abort used a different policy and is not a matched pair; at 700/3,500 KNP is 0.5-2.4 s slower than Cilium at lower throughput; at 7 identities KNP is 22x slower | Matched 35k pair; repeat trials; agent metrics |
| Enforcement verified at scale | Positive path only: every sandbox gates on a permitted connection to the gateway (`wait-for-gateway`); negative path checked once per cluster by `verify-netpol.sh`, unarchived | Archive `verify-netpol.sh` output per run; add a denied-connection probe to the sandbox template |
| Zero startup latency from NRI | Incorrect as stated | Claim removal of local asynchronous Pod-IP dependency; timestamp event ordering |
| Secure by default throughout lifecycle | Not established; fail-open default plus 1,024-packet queue and uncached denials form a documented bypass vector | Bootstrap, shutdown, missing metadata, queue saturation (fail-open and fail-closed), and restart tests |
| Static-flow throughput parity | Not measured here | Existing traffic benchmark or a small matched connection/throughput test |
| Lower memory with IPTracker + disk + LRU | Design support, no matched cluster result | Heap/RSS/page-cache measurement with working set larger than LRU |
| Agentic workload representativeness | Motivation only | Workload trace or explicitly label this a synthetic stress test |

## Provisional Conclusion

The evidence now supports four observations: low post-scheduling latency in
executed Cilium identity/mesh tiers within its feasible region; a dense-mesh
tier excluded on Cilium on predicted per-endpoint map demand; an aborted Cilium
hub-and-spoke raw-Pod run with 5,694 stranded Pods; and a KNP bidirectional
mesh sweep that matches Cilium at three ReplicaSet-paced tiers (5.33 and
2.79 s P99 at 700 and 3,500 identities; 151 s at 7 identities with 5,000 ppr)
and completes an unmatched 35,000 raw-Pod mesh tier (35,000 Running, 0
stranded, 421 s P99, 2 SLO failures). Because every sandbox gates on a
permitted connection, these latencies bound first permitted communication.
The sweep establishes the capacity claim (KNP has no per-endpoint bound that
excludes the tier) and does not yet establish an admission-latency advantage:
KNP is slower than Cilium at every matched tier, achieved 2.5-3x lower Pod
throughput, has one trial per tier, and its agent metrics are empty. Present
the matched tiers, the unmatched tier, the tier-1 gap, and the throughput
confound together.
