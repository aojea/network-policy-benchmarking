# Tier 4: 35,000 Identities (Raw Pods Direct Burst)

No final latency results were generated for this run because the benchmark aborted due to 5,694 permanently stranded pods (29,306 Running / 5,694 Stranded).

## Root Causes
1. **Local CNI Rate Limiting (`HTTP 429`)**: Concurrent unbuffered pod creation at 500 QPS triggered concurrent CNI `ADD` calls, tripping `cilium-agent`'s local REST API rate limiter.
2. **The 16-Bit Identity Ceiling (`65,280 Identities`)**: Cumulative identity allocations across initial creation and churn exhausted the cluster-wide 16-bit identity space ($2^{16} - 256 = 65,280$), causing the identity allocator to fail with `error="no more available IDs in configured space"`.
