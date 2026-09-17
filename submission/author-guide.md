# Author Guide And Deadline Plan

Research and editorial preparation, not manuscript sections. Human authors
should write the paper; see the live CFP's generative-AI policy in
[README.md](README.md). Source checks below were made on 2026-09-16.

A complete AI-generated writing exercise is now available in
[paper.tex](paper.tex) and [paper-draft.pdf](paper-draft.pdf), as separately
requested by the author for non-submission use. This guide's submission gates
still apply; the exercise does not replace human authorship or missing evidence.

## Recommendation

Target **Traditional Research**, subject to an honest evidence gate. The
contribution should concern when Kubernetes policy work is performed and how
that changes the balance between workload admission, metadata distribution,
and connection admission. NFQUEUE and conntrack are implementation mechanisms,
not inventions of this paper.

Operational Systems becomes the better choice only with actual deployment
experience and generalizable lessons: duration, scale, traffic, upgrades,
incidents, and resulting design changes. Project adoption or integrations alone
do not establish that evidence. Frontiers is not an incomplete-evaluation track:
the CFP excludes ordinary early-stage work and expects an unusually ambitious
idea that is inherently difficult to evaluate in the traditional way.

No acceptance prediction is justified. A submission centered on an unverified
failure chart, with no connection-cost evaluation, faces substantial research
track risk. Do not rely on receiving a one-shot revision to fill core gaps.

## Historical Argument: A Design Space

Use an evolution of requirements and work placement, not a replacement ladder.
The alternatives coexist and share techniques.

| Approach | Relevant mechanism | Cost to distinguish | Bibliography keys |
| --- | --- | --- | --- |
| Linear rule chains | Ordered matching and controller-generated rules | Rules examined per packet versus update size and synchronization | `sutter2017nftables`, `winship2025nftables` |
| ipset / nftables sets and maps | Indexed membership and incremental updates | Selector expansion and membership changes remain separate from lookup cost | Same as above |
| NVP / OVS / OVN | Distributed virtual networking, flow caches, stateful ACLs | Compilation, dissemination, cache misses, invalidation, and conntrack resources | `koponen2014nvp`, `pfaff2015ovs`, `ovnacl` |
| eBPF and Cilium | Programmable datapath, mutable maps, label-derived identities | Program updates versus map updates versus identity allocation/distribution | `linuxbpfmaps`, `ciliumidentities` |
| NFQUEUE policy engine | Userspace semantic decisions; accepted-flow state in conntrack | Less eager materialization may cost more at first communication and under overload | `nfqueueapi`, `pfaff2015ovs`, `oncache2025` |
| Compact metadata distribution | Reflector tier and disk-backed local records | API-server load shifts to reflectors; freshness, disk latency, and fan-out remain | `calicotypha`, `iptracker190`, `iptrackerbolt` |

Corrections essential for the human rewrite:

- Do not say everyone used iptables before containers. Hypervisors, switches,
  appliances, and SDN systems had other enforcement mechanisms.
- Sutter's 2017 experiment demonstrates the benefit of sets, including ipset,
  rather than establishing a general nftables scalability failure.
- Winship's 2025 article explicitly describes incremental nftables updates. It
  concerns Service proxying, not NetworkPolicy; identify that scope when citing.
- OVS already sends misses to userspace and caches actions. OVN supports
  conntrack-backed `allow-related` ACLs. Calling OVS/OVN inherently stateless
  would misrepresent the baseline.
- eBPF map updates do not require replacing the whole program. Neither eBPF nor
  Cilium guarantees zero update latency; a limit of one configuration is not a
  fundamental limit of eBPF.
- Do not equate label sets, allocated security identities, IP records,
  directional policy-map entries, and live conntrack entries. In particular,
  ingress plus egress permissions do not imply twice as many identities.
- Treat agentic workloads as motivation for short-lived sandboxes. The saved
  workloads are synthetic, not production traces of agents.

## What Recent NSDI Papers Teach

These are public accepted papers, not confidential submissions or reviews.
The selection is relevant and bounded, not a systematic literature survey.
Publisher pages verify titles, authors, and venue/year. PDF checks were made
for OVS, ONCache, KUBEDIRECT, and MirrorNet; the other summaries use publisher
abstracts and technical documentation.

| Work | Relevant evidence or framing | Lesson for this paper |
| --- | --- | --- |
| OVS, NSDI 2015 | Userspace miss handling and kernel caches; flow classification; deployment-informed evaluation | Explicitly explain what Kubernetes semantics and churn change about this old tradeoff |
| Andromeda, NSDI 2018 | Hierarchy of processing paths; provisioning scale and feature velocity | Separate common-path performance from feature complexity and uncommon work |
| ONCache, NSDI 2025 | Quantifies repeated overlay work; cross-layer caches including filtering; microbenchmarks and applications; optional changes evaluated separately | Identify exactly what is cached, why it remains valid, and what a miss costs; do not claim caching is novel |
| Role-based Micro-Segmentation, NSDI 2025 | Infers endpoint roles and policies using large flow logs | Related problem, different stage: policy inference is not policy enforcement |
| KUBEDIRECT, NSDI 2026 | Diagnoses API-mediated controller messaging on the FaaS critical path; addresses state consistency when bypassing it | Decompose startup, explain compatibility, and make failure/recovery semantics part of the design |
| MirrorNet, NSDI 2026, Operational Systems | More than two years of WAN use; real operational tasks and reconstruction/consistency mechanisms | This is the type of experience evidence the operational track needs, beyond a large testbed |

Each entry has a corresponding key in [references.bib](references.bib).
MirrorNet is primarily a track-fit exemplar and need not be cited in the final
related-work section. Do not pad the bibliography with weakly relevant papers.
Missing page numbers and DOIs were deliberately not guessed. Rolling
documentation needs a version/date check before publication. The local
implementation citation's pinned commit must be publicly accessible before use.

## Mechanism Notes For Author Verification

Inspected implementation HEAD: `9984dcd47142f7c0963cf7f6b4866cb4704a0869`.
This is not proof that a benchmark image contains the same implementation.
Paths below are relative to the companion `kube-network-policies` repository.

| Source anchor | Observed behavior | Consequence |
| --- | --- | --- |
| `pkg/dataplane/controller.go`, NFQUEUE callback | Copies up to 128 packet bytes, parses headers, calls `evaluatePacket`, emits a verdict and acceptance conntrack label | Draw a userspace policy-decision path, not selector matching in kernel hash sets |
| Same file, NFQUEUE configuration | Queue capacity 1,024; GSO flag; configurable fail-open | New-connection bursts, denied traffic, parser limits, and queue drops need evaluation |
| `pkg/cmd/cmd.go`, `AddFlags` | `fail-open` defaults to true | Do not call the shipped default fail-closed; record effective deployment flags |
| `pkg/dataplane/controller.go`, initial sync and `Shutdown` | Initial rule-sync error is logged without blocking; fail-closed graceful shutdown cleans nftables rules | Startup/upgrade/uninstall transitions require explicit safety assumptions and tests |
| Same file, `firewallEnforcer` | Strict mode scans conntrack, reevaluates flows, clears acceptance labels for newly denied traffic | Revocation is additional work, not instantaneous or free |
| `pkg/podinfo/nri/resolver.go`, `RunPodSandbox` | Runtime callback fills local IP-to-Pod metadata; namespace labels may come from informer | Removes a local asynchronous Pod-IP observation dependency, not all metadata delay |
| Same file, `getPodIPs` | Runtime API IPs or network-namespace fallback | Pin runtime/NRI version and permissions; failed discovery must not be mistaken for success |

A useful design illustration should show three separate paths: metadata
reconciliation; packet queue/evaluation/verdict; and accepted-connection bypass.
Keep local Pod steering state, policy metadata, and per-connection cache state
separate. Specify enforcement points for local versus remote endpoints, NAT,
and the supported protocols. Do not label the diagram "one packet per flow"
without measuring retransmissions and concurrent initial packets.

Safety argument the authors should supply:

- For policies already observed by the agent, establish isolation before any
  application or init-container traffic can bypass enforcement.
- Explain what happens when local metadata, remote metadata, namespace labels,
  or policy updates are missing or stale, including IP reuse.
- Distinguish newly created policy convergence from enforcement of a policy
  already handled by the plugin. Kubernetes documents this distinction.
- Separate new-connection decisions from existing-connection revocation. The
  NetworkPolicy API leaves the latter implementation-defined; strict-mode
  claims still require evidence.
- State trusted components and assumptions about address spoofing, privileged
  workloads, `hostNetwork`, and the underlying CNI. NRI alone is not a proof
  of secure-by-default lifecycle behavior.

## IPTracker As Bounded Future Work

Evidence anchors: `pkg/ipcache/client.go`, `bbolt.go`, `lru.go`, the IPTracker
plugin, PR 190, and issue 114659. The reflector mechanism is implemented;
its large-cluster benefit is future evaluation, not a measured benefit of the
current startup runs.

- The API server is the interface for most declarative control-plane state,
  with authentication, authorization, admission, persistence, and watch
  delivery. Application packets and all runtime events do not pass through it.
- Each broadly watched update can create work across many consumers. With
  node count N and event rate U, N times U is a useful first-order delivery
  count for all-to-all subscriptions, not an exact CPU or network-cost model.
- R reflectors can reduce the policy agents' full Pod subscriptions against
  the API server from N to R. Other consumers remain. Reflector-to-agent
  dissemination still exists; this implementation watches the whole IP prefix.
- Protobuf records avoid shipping full Pod objects, but Kubernetes itself can
  use protobuf too. Attribute savings to schema reduction, filtering, and
  fan-out placement, not "JSON versus protobuf" without measurement.
- bbolt stores serialized records and sync metadata; the LRU wraps reads,
  writes, and deletes. Updates enter the LRU too, so metadata churn can evict
  a communication working set. Disk access holds the wrapper's mutex.
- A bounded Go-object cache is not a bound on RSS or system memory: bbolt
  mappings, page cache, full-sync response buffers, and `List()` matter.
- Full sync fetches the entire prefix, clears the store, and inserts records.
  Do not promise constant-memory bootstrap or atomic snapshot replacement
  without verifying that stronger guarantee.
- Capture revision recovery, compaction, reflector failover, restart, disk
  errors, and stale-policy behavior. Persisted cache is not automatically
  trusted current state after restart.
- Calico Typha is mandatory comparison for watch aggregation. The distinctive
  question is the compact, persistent metadata path and its costs, not whether
  an intermediate distributor can exist.
- APF is concurrency isolation and queueing, not unlimited capacity. Raising
  shares can move latency between components; exemptions can remove protection.
  Include etcd storage latency, API CPU/memory, watch traffic, and achieved
  request rates before diagnosing APF as the root cause.

## Two-Day Evidence Budget

The actual remaining deadline is September 17, 23:59 EDT / September 18,
03:59 UTC. Reserve at least two hours for PDF and submission checks. Do not
start another 720-node investigation or change production settings for this
preparation package.

| Priority and budget | Work | Deliverable or stopping rule |
| --- | --- | --- |
| P0, done September 17 | Scan both repositories for reviewer-requested data | Recovered Phase-1 throughput, node CPU, Pod LIST latency, JUnit teardown diagnosis, KNP microbenchmark, PR 218 IPTracker logs, Cilium v1.20.1 map limits; confirmed absences listed in `evidence-audit.md` "Gap Scan" and paper Table 4 |
| P0, done September 17 | Verify the mesh capacity model against the tested Cilium version; recover raw-Pod failure diagnostics and Kindnet comparison runs | Separate completed tiers, Cilium tier 4 not executed (`f998224`), and raw-Pod abort (`0442dce`); pin limits, images, and each plotted value. Map limit: 65,536 is documented in the `run-mesh-sweep.sh` header and corroborated by the completed unidirectional 35k tiers (gateway endpoints needed ~35k entries); the ConfigMap is not archived, so a `cilium-dbg bpf policy get` dump or `kubectl get cm cilium-config -o yaml` capture is still the cheapest closure |
| P0, 1-2 hours | Write the precise contribution and reconcile registered abstract with measured scope | Author-written introduction outline that distinguishes OVS/ONCache, conjunctive-match (Antrea) and ipset (Calico) factoring, and states the new cost |
| P0, done September 17 | **Rerun the September mesh generators on the Kindnet cluster** | Done and validated: `artifacts_pods/kindnet/mesh-sweep/`. Tiers 1-3 match the Cilium mesh generator; tier 4 is 35,000 raw Pods with no Cilium counterpart. Results: 151.5 / 5.33 / 2.79 s P99 at 7 / 700 / 3,500 identities (Cilium: 6.77 / 2.93 / 2.28 s); tier 4 all 35,000 Running, 0 stranded, 421 s P99, 2 startup-SLO failures. KNP created Pods at 103-124 Pods/s vs Cilium 302-328. Six KNP agent queries and the kubelet CNI query returned no samples (Kindnet build has no metrics port). This supports the capacity claim, not an admission-latency advantage |
| P0, 1-2 hours if the Kindnet cluster is up | **Rebuild/deploy a Kindnet image with the KNP metrics server enabled and rerun tier 2** | Fills the agent CPU / memory / verdict-rate / drops rows of Table 4 in one run; without it the queue model has no data at scale |
| P0, 30 minutes if the Kindnet cluster is up | **Collect `wait-for-gateway` init-container logs (`Latency: N ms`) from a sample of ~200 sandboxes on tiers 1 and 2** | Isolates first-permitted-connection time from image pull and container start; explains or exonerates KNP for the 151 s tier-1 tail |
| P1, 1 hour each | **One matched 35k pair**: either Cilium raw-Pod mesh (expected to fail, records how) or KNP 35,000 x 1-Pod ReplicaSets | Turns the unmatched tier-4 row into a comparison |
| P1, 1 hour | Archive `verify-netpol.sh` output per cluster; add a second init container (or sidecar probe) that attempts a forbidden connection and asserts failure | Converts the enforcement check from positive-only to positive-and-negative at scale |
| P1, 2-4 hours on an existing small testbed | Replay issue 85966's startup dependency with already-applied deny/allow policies, NRI on/off | Runtime/IP observation and first successful allowed connection timestamps; zero forbidden connectivity; do not use public targets |
| P1, 2-4 hours on an existing small testbed | Fresh TCP/UDP flows versus reused flows, plus denied new flows, at increasing offered rates; once fail-open, once `--fail-open=false` | Achieved connections/s, P50/P99 setup latency, agent CPU, NFQUEUE drops, conntrack occupancy, and the offered rate at which fail-open starts accepting unevaluated packets |
| P1, 2-4 hours if existing harness permits | Matched fixed-Pod/fixed-generator comparison with reused versus fresh label sets | Measured identities and churn rate; same policies, topology, flags, APF and images; no claim of full-cluster scaling from a small test |
| P2, at most 1 hour | Recover existing IPTracker measurements, or retain design-only discussion | PR 218 logs are now cited; no new disk-cache scaling study before the deadline |
| Final 2 hours minimum | Human review, bibliography/anonymity/format check, upload and inspect rendered PDF | No unresolved numerical provenance; main text at most 12 pages; introduction at most 3 pages |

Do not require every proposed experiment to proceed. Recover existing evidence
first, then choose the missing test that directly supports the contribution.
If the cost and correctness of connection admission remain entirely unmeasured,
reduce the claims and make an explicit submission-versus-deferral decision.

For a focused identity test, hold live Pod count, resource type, placement,
creation rate, burst, policy count, and topology fixed. Change label sharing
independently from whether replacement Pods use fresh label sets. Measure
identity count and policy-map occupancy separately. Use at least three trials
where feasible; show individual outcomes instead of inventing confidence bands.

## Suggested Page Budget

This is an allocation for human writing, not generated section content.

| Part | Pages | Question to answer |
| --- | ---: | --- |
| Introduction | 1.5 | What networked-systems insight changes, beyond using NFQUEUE? |
| Background and problem | 1.0 | Which costs do churn, labels, and asynchronous observation introduce? |
| Design and semantics | 2.5 | What runs where, what is cached, and what remains safe under change? |
| Implementation | 0.75 | Which existing mechanisms and runtime versions implement the design? |
| Evaluation | 4.0 | Does the benefit appear under controlled conditions, and what does it cost? |
| Related work | 0.75 | How is the contribution different from reactive caches and metadata reflectors? |
| Discussion and conclusion | 0.5 | What is supported, what is limited, and what is future work? |

Figure plan: one architecture/work-placement diagram; one startup timeline;
verified per-run identity results; a compact capacity panel distinguishing
derived policy-map demand from measured occupancy; raw-Pod failure counts
distinct from latency; and one connection-rate/cost graph if measured. The
Cilium 35k mesh tier was not run (`2I = 70,000 > 65,536`), whereas the KNP 35k
mesh tier completed all 35,000 pods (`schedule_to_run` 120.003s P50 / 421.410s P99).
Keep APF tuning as sensitivity analysis. Cite actual run paths
in the internal audit; do not expose identifying repository links in the
anonymous research-track submission.

## Artifact And Build Use

- [evidence-audit.md](evidence-audit.md): verified numbers, Figure 2 provenance,
  missing reports, and the current claim gate.
- [upstream/extracted-results.md](upstream/extracted-results.md): current
  per-run startup quantiles and JUnit outcomes with relative source paths.
- [references.bib](references.bib): candidate bibliography, not an instruction
  to cite every item. Self-references need a double-blind review.
- [paper.tex](paper.tex): complete AI-generated non-submission exercise in
  numbered USENIX format, with citations, diagrams, quantitative tables, and
  evidence limitations.
- [paper-draft.pdf](paper-draft.pdf): current compiled manuscript exercise.
- [paper-scaffold.pdf](paper-scaffold.pdf): superseded placeholder preview.

Offline extraction from the benchmark root:

```sh
node submission/analyze.mjs --self-test
node submission/analyze.mjs --root . --output submission/upstream --revision "$(git rev-parse HEAD)"
```

Build from the submission directory:

```sh
pdflatex -interaction=nonstopmode -halt-on-error paper.tex
bibtex paper
pdflatex -interaction=nonstopmode -halt-on-error paper.tex
pdflatex -interaction=nonstopmode -halt-on-error paper.tex
cp paper.pdf paper-draft.pdf
```

The extractor uses Node.js, the `yaml` package, and `xmllint`; the build uses
pdfLaTeX, BibTeX, TikZ/PGFPlots, the included USENIX style, and standard TeX Live
packages. The draft uses standard `plain` bibliography style; URLs are also
in note fields because that style does not print the `url` field. Only cited
references appear in the manuscript. The PDF includes an AI-generation notice
and is not a submission artifact.
