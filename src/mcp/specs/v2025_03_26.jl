# 2025-03-26 — the revision that added JSON-RPC batching (removed again in
# 2025-06-18). One file per revision keeps each protocol isolated: only this
# revision's deltas live here. Identity lives in `specs.jl`; a revision with no
# deltas needs no file at all.

allows_batch(::Val{:v2025_03_26})::Bool = true
