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

- QPS 50 and 100 have JUnit failures in both families despite startup reports;
  inspect the cases rather than calling all these runs fully successful.
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
- CPU peaks based on `rate(...[1m])` are maxima of one-minute averages, not
  instantaneous spikes. Preserve whether an aggregation is per node or fleet
  wide, and whether it is percent of one CPU or all CPUs.
- JSON percentiles are insufficient to reconstruct a CDF or valid confidence
  interval over Pods. Plot the available quantiles and individual trials; do
  not synthesize raw samples or average P99s into a pooled P99.
- Completion counts and failed/pending Pods must accompany survivor latencies.
  An all-zero startup report in `reports/run2_hpt` with JUnit failures is not
  evidence of zero startup latency.

## Claim Gate

| Proposed claim | Current status | Minimum additional evidence |
| --- | --- | --- |
| Userspace semantic evaluation with kernel-cached accepted decisions | Supported by current source inspection | Pin the measured binary to that implementation |
| Less eager identity-related work at endpoint admission | Mechanism hypothesis | Matched identity-turnover experiment and stage timing |
| Dense mesh exceeds per-endpoint policy-map capacity | Analytical exclusion documented in `f998224`; tier 4 never executed | Verify per-identity expansion and effective limit in the tested Cilium version; distinguish calculated demand from occupancy |
| Better than Cilium at high identity cardinality | Documented raw-burst failure; completed Cilium sweeps remain successful; matched KNP comparison missing | Matched KNP sweep, measured identities, isolated workload rate |
| Zero startup latency from NRI | Incorrect as stated | Claim removal of local asynchronous Pod-IP dependency; timestamp event ordering |
| Secure by default throughout lifecycle | Not established | Bootstrap, shutdown, missing metadata, queue saturation, and restart tests |
| Static-flow throughput parity | Not measured here | Existing traffic benchmark or a small matched connection/throughput test |
| Lower memory with IPTracker + disk + LRU | Design support, no matched cluster result | Heap/RSS/page-cache measurement with working set larger than LRU |
| Agentic workload representativeness | Motivation only | Workload trace or explicitly label this a synthetic stress test |

## Provisional Conclusion

The evidence now supports three complementary observations: low latency in
executed identity/mesh tiers; a dense-mesh tier excluded on predicted policy-map
capacity grounds; and an aborted raw-Pod run with documented stranded Pods.
This strengthens the argument about topology-dependent materialization and
admission under churn, without establishing that latency must rise with
identity count. The matched Kindnet scaling advantage and NFQUEUE connection
cost still require evidence. Use a version-grounded capacity model alongside
the measured and documented outcomes, without presenting the unexecuted tier
as an experiment.
