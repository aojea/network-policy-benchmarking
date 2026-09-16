# NSDI '27 Submission Preparation

Working research and editorial notes, not submission-ready paper prose.
Prepared against the live NSDI '27 CFP on 2026-09-16. The original draft and
benchmark summary are preserved; neither is an independently verified source.

## Complete Working Draft

At the author's request, [paper.tex](paper.tex) now contains a complete
AI-generated, non-submission writing exercise:
**Decoupling Workload Admission from Policy Materialization in Kubernetes**.
Read the compiled [paper-draft.pdf](paper-draft.pdf). It has eleven pages of
main text, references, and a provenance appendix, with an architecture
diagram, separate plots for measured latency and analytical capacity, a
recovered throughput/CPU table, and an explicit "What the Artifacts Do Not
Contain" table (Section 6.7).
It is not attributed to Antonio Ojea and is not eligible for submission as
human-written text. The evidence limitations remain part of the manuscript.
The earlier [paper-scaffold.pdf](paper-scaffold.pdf) is a superseded layout
preview, not the current draft.

## Gap Scan After Self-Review (September 17)

A simulated NSDI review of the draft rated it weak reject, chiefly for the
absence of any KNP identity-sweep data, missing resource metrics, an
unquantified NFQUEUE verdict rate, and an unexamined fail-open bypass. Both
repositories were scanned for anything that could close those gaps:

- **Recovered and added**: Phase-1 scheduling throughput and worker CPU for
  every September tier and both Kindnet QPS-500 runs (paper Table 2); cluster
  Pod LIST P99 latency; the exact cause of the QPS 50/100 JUnit asterisks
  (teardown deletion timeouts); the archived Cilium v1.18.6 700-identity abort
  and its fix in v1.20.0; the KNP `docs/testing` ApacheBench microbenchmark and
  Prometheus charts as an indicative verdict-rate bound; PR 218 IPTracker
  integration-test numbers; the Cilium v1.20.1 `bpf-policy-map-max` default
  (16,384) and maximum (65,536); the IPTracker flavor's divert-all behavior;
  the benchmark manifest's fail-open default.
- **Confirmed absent and now highlighted in the paper (Table 4)**: any KNP run
  above ~7 identities; memory metrics; policy-agent CPU; agent `/metrics` at
  scale; policy-map dumps and effective Cilium configuration; image digests
  and flags per Kindnet run; logs for either abort; an NRI ablation.
- **Added analysis**: a security paragraph on fail-open plus queue overflow
  plus uncached denials as a tenant-triggerable bypass, the unknown-remote-peer
  deny semantics, and related work on conjunctive-match (OVS/Antrea) and
  ipset (Calico) factoring as kernel-resident alternatives to per-peer
  expansion.

Details and sources are in [evidence-audit.md](evidence-audit.md) under
"Gap Scan"; the prioritized reruns are in [author-guide.md](author-guide.md).

## Immediate Decisions

- Target: **Traditional Research**, provisionally. A working implementation and
  controlled scalability experiments fit a systems design paper. Acceptance will
  depend on a precise contribution beyond known reactive flow processing and a
  credible evaluation of its costs, not merely a large cluster demonstration.
- Do not use **Frontiers** to compensate for missing experiments. The CFP explicitly
  excludes ordinary early-stage work; its prescreening criterion expects an idea
  that a graduate student could not completely implement and evaluate in a PhD.
- Switch to **Operational Systems** only if the authors can supply substantive
  deployment experience: environment, duration, scale, workloads, incidents, and
  generalizable lessons. Integration into Kindnet, Talos, Flannel, or a Rancher
  catalog establishes relevance, not measured operational experience by itself.
- Author confirmed that the September 10 title/abstract registration was completed.
- Full paper deadline: **September 17, 2026, 23:59 US EDT**, equivalent to
  **September 18, 2026, 03:59 UTC**. Confirm the submission's HotCRP settings now.
- The current CFP is newer than the July PDF in the repository. Use the live CFP:
  <https://www.usenix.org/conference/nsdi27/call-for-papers>.

## Authorship And Format Gates

The current CFP prohibits entirely or substantively AI-written papers, explicitly
including any AI-written whole section, related work, or conclusion. Authors must
attest that the text is primarily human written. Use these files for evidence
checking, bibliography preparation, analysis, and organization. Authors must write
the actual sections; do not paste these notes as sections or paraphrase generated
sections to evade that rule. AI assistance for grammar and clarity of human-written
text is permitted. Ask the chairs about ambiguous uses.

- At most 12 main-text pages, including figures, tables, and footnotes.
- References and supplementary appendices may extend beyond that limit. The main
  paper must stand alone; reviewers need not read appendices.
- US letter, two columns, 10-point Times-like type, 12-point leading,
  7-by-9-inch text block, 0.33-inch column separation, numbered pages.
- Put the selected track on the title page and in HotCRP; track cannot change
  after submission.
- Introduction is prescreened and must not exceed three pages. It must make the
  networked-systems problem, intellectual contribution, and evaluative claims
  understandable to a systems researcher outside Kubernetes networking.
- Traditional Research requires good-faith double-blind anonymization: no author
  names, affiliations, acknowledgments, identifying links to the authors' content,
  or SIG leadership credentials. Cite prior work fairly in the third person; use
  the submission form for required de-anonymized auxiliary references.
- Operational Systems still withholds author names, but permits real system and
  company names and links needed to understand the deployment.
- Check conflicts, authorship agreement, submission count, prior rejection rules,
  and concurrent submissions before uploading.

## Working Research Question

Can a Kubernetes policy engine decouple endpoint admission from eager expansion
of label-derived peer permissions by evaluating connection admission in userspace
and caching accepted decisions in the kernel, while preserving isolation and
keeping connection-setup costs acceptable?

Candidate title direction for the authors to refine: **Decoupling Workload
Admission from Policy Materialization in Kubernetes**. Avoid promising a new
generation of packet filtering or making NFQUEUE itself the novelty claim.

Potential contribution to test: placement and timing of semantic work. Keep
label-based policy logic in userspace, avoid a separate policy-specific distributed
security-identity allocation path, and pay policy evaluation on attempted
communication rather than materializing all permitted peer relationships before
workloads run. NRI supplies timely local endpoint metadata; it does not synchronize
remote nodes or all policy state.

## First Mechanism Check

Local hypothesis: the draft incorrectly treats KNP as a compiler of policy
selectors into shared kernel hash sets. The owning implementation instead queues
packets to a userspace evaluator and emits verdicts, with conntrack state handling
subsequent traffic.

Discriminating check: inspect `pkg/dataplane/controller.go` in the implementation
repository. Its NFQUEUE callback parses headers, invokes `evaluatePacket`, and
calls `SetVerdictWithOption`, setting `CTLabelAccept` for an accepted verdict.
This confirms the mechanism mismatch in the draft. NFTables still participates
in packet steering and bypass decisions; it is not evidence of selector-to-set
policy compilation.

Consequences for the human rewrite:

- Replace the draft's "Synchronous Node-Global Set Matching" description and all
  numerical/kernel-state calculations derived from that fictitious design.
- Do not claim O(1) total startup, constant-time semantic matching, unlimited
  identities, zero processing cost, or topology invariance from this mechanism.
- Distinguish policy metadata, kernel steering state, and per-connection state.
- A connection may cause multiple queued packets; protocol behavior, concurrent
  initial packets, denied traffic, cache invalidation, and retransmission matter.
- Define admission safety separately from availability. Removing a local Pod-IP
  watch dependency is not zero total startup latency or instantaneous remote
  convergence.
- Inspect fail-open settings, startup/shutdown transitions, stale metadata, and
  policy revocation before claiming secure-by-default behavior.
- Treat eBPF as a mechanism, Cilium as a versioned architecture, and its tested
  configuration as the experimental baseline. An implementation-specific failure
  is not a fundamental limitation of eBPF.
- NFQUEUE, conntrack, reactive SDN, OVS caching, and userspace packet processing
  are prior art. Novelty must concern the combination and demonstrated tradeoff
  in Kubernetes policy enforcement, with explicit comparison to that prior art.

## Evidence Rules

- Raw machine-readable artifacts outrank narrative summaries and directory names.
- Record every plotted run's configuration, image/version or digest, topology,
  offered and achieved rate, object count, completion status, and metric source.
- Do not pool different topologies, raw-Pod and ReplicaSet generators, versions,
  APF configurations, or incomplete and complete runs as matched comparisons.
- Failed runs must remain visible. A percentile over completed Pods does not
  describe the whole submitted workload when some Pods never start.
- Synthetic creation/churn benchmarks motivate ephemeral workloads but are not
  traces of AI agents, production traffic, or measured static-flow throughput.
- Keep IPTracker and upstream API scalability proposals separate from mechanisms
  enabled in the measured binaries. Implemented-but-unmeasured is not evaluated.

## Author Inputs Still Needed

- Registered title and abstract: ensure the refined contribution is consistent
  with the submitted scope and HotCRP rules.
- Exact benchmark binary/image provenance, especially labels claiming unreleased
  or development Cilium versions, and actual identity counts per run.
- Any production deployment scale, duration, incidents, or externally published
  operator experience that could justify Operational Systems.
- Existing connection-rate, policy correctness, queue-overload, or startup-safety
  results not yet present in this workspace.

## Preparation Files

- [author-guide.md](author-guide.md): historical framing, recent NSDI comparisons,
  source-grounded mechanism notes, IPTracker scope, page budget, and deadline plan.
- [evidence-audit.md](evidence-audit.md): corrected quantitative results and the
  reported Figure 2 failure case, distinguished from reconstructable metrics.
- [upstream/extracted-results.md](upstream/extracted-results.md): current pinned
  snapshot, including diagnostic-only attempts and relative artifact links.
- [references.bib](references.bib): twenty candidate references with checked
  title/author/source metadata; human citation selection and anonymity review remain.
- [paper.tex](paper.tex) and [paper-draft.pdf](paper-draft.pdf): complete
  non-submission working draft, explicitly labeled AI-generated. The original
  scaffold preview remains separately available for reference.
- [overleaf/README.md](overleaf/README.md): self-contained Overleaf project and
  import instructions. Upload [nsdi-overleaf.zip](nsdi-overleaf.zip) as a new
  Overleaf project; its main document is [overleaf/main.tex](overleaf/main.tex).
  The original draft is preserved; the Overleaf copy is independently editable.

The user's Figure 2 pointer and both new evidence notes are incorporated in
the audit. Commit `0442dce` documents the raw-Pod run's 29,306 Running / 5,694
stranded outcome and absence of final latency results. Commit `f998224`
establishes that mesh tier 4 was deliberately not executed because predicted
per-endpoint policy-map demand exceeded the stated limit. Distinguish completed
tiers, analytical capacity exclusions, and observed aborted admission. The
capacity argument adds value even without a latency increase, but neither
the excluded tier nor the aborted run has a measured numeric P99.
