# How to resume the restructured-pipeline bug-hunt run

This directory runs `Aging_organoids_30weeks_restructured.Rmd` session-by-session
via `_bughunt.R`, saving a full checkpoint to `_ckpt/after_<NN>.RData` after each
**completed** session. Everything survives a reboot — the background R process
dies, but the last checkpoint on disk does not.

## CURRENT STATE — paused 2026-06-16

Latest checkpoint = `_ckpt/after_07.RData` (Session 5 done). Session 6's 12-min
model fit is cached at `Restructured_results/Objects/sce_S6_postfit.rds`.
Remaining: finish Session 6 (APCA), then Sessions 7–10.

> IMPORTANT memory finding: doing the scplainer **fit and `scpComponentAnalysis`
> in the same R process crashes** (heap fragmentation, not OOM — see bug #2
> below). So each heavy session is run in its own fresh `Rscript` process, and
> Session 6's APCA is finished from the cached fit. Do NOT just run
> `_bughunt.R 8` for Session 6 — it will refit and crash at APCA.

### Resume sequence (run each line as a separate process; check it finished OK before the next)

```powershell
Set-Location "D:\Documents\Projetos\Aging_organoids_SCP\Full_analysis\20250502_SCP_WT83_7point5_Months\DIANN\DIANN\scp"
$R = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
& $R _s6_from_cache.R               # finish S6 APCA from cached fit -> writes after_08
& $R _bughunt.R 9 10                 # S7 + S8 (fresh process)        -> after_09, after_10
& $R _bughunt.R 11 11                # S9 cluster-model + DE (isolated, the memory hog)
& $R _bughunt.R 12 12                # S10 trajectory / pseudotime
```

After all four, optionally `& $R _bughunt.R 13 14 appendix` for Appendix A +
Session info (needs `scRNAseq`/`zellkonverter`; network refs, tolerated to fail).

## General resume (auto)

`Rscript _bughunt.R auto` finds the highest `_ckpt/after_NN.RData` and continues
from session NN+1. On resume it: (1) loads that checkpoint's data into a clean
env, then (2) re-runs the preamble + Session 0 to re-attach packages and rebuild
the `save_fig`/`save_tab` helpers (the package search path is NOT saved in a
checkpoint, so this bootstrap is required every resume). NOTE: `auto` from
`after_07` would run Session 6 in-process and crash — use `_s6_from_cache.R`
first (above), after which `auto` is safe.

## Session ORDER index map

| idx | session |
|----|---------|
| 1  | (preamble) |
| 2  | Session 0 — Setup & params |
| 3  | Session 1 — Data import (740 MB read, ~75 s) |
| 4  | Session 2 — Contaminant annotation |
| 5  | Session 3 — Cell QC & filtering |
| 6  | Session 4 — Peptide processing → Protein.Group (~8 min) |
| 7  | Session 5 — Missing-value characterization |
| 8  | Session 6 — scplainer modeling (slow model fit) |
| 9  | Session 7 — Clustering & embedding |
| 10 | Session 8 — Cell-type identity |
| 11 | Session 9 — Differential expression (heavy cluster-model fit) |
| 12 | Session 10 — Trajectory / pseudotime |
| 13 | Appendix A — imputed + SingleR (network refs; skipped by default) |
| 14 | Session info |

## Deliverable intermediate objects (written by the Rmd, not the harness)

`Restructured_results/Objects/`:
`sce_minimal.rds` (S6), `sce_clustered.rds` (S7), `daRes.rds` (S9),
`sce_trajectory.rds` (S10), plus tables in `Restructured_results/Tables/` and
figures in `Restructured_results/Figures/`.

## Bug fixes applied so far (in the Rmd)

1. **Session 4:** `filterFeatures(scp, ~ Global.PG.Q.Value <= QC$pg_qvalue)`
   mis-parsed `QC$pg_qvalue` as a rowData column (filterFeatures reads the
   formula via `all.vars`). Fixed by binding a plain local scalar
   `pg_qvalue_thr <- QC$pg_qvalue` first.
2. **Session 6 / Session 9 memory (the scplainer heap-fragmentation issue):**
   running `scpModelWorkflow` (the ~12-min per-peptide fit) and then
   `scpComponentAnalysis(APCA)` / the cluster-model DE in the SAME process
   crashes hard — not OOM (25 GB free), but heap fragmentation defeating APCA's
   ~3.9 GB allocation. Verified: the same APCA succeeds in a fresh process
   loading the pre-fit `sce` from disk. Rmd mitigations applied: S6 drops scp's
   peptide-level assays + `gc()` before APCA; S9 frees `sce` before the
   cluster-model fit (S10 rebuilds from `scp[["Protein.Group"]]`, so `sce` isn't
   needed) + `gc()` between steps. Execution mitigation: run each heavy session
   in its own process (see resume sequence above). NOTE: the Rmd mitigations
   reduce pressure but a *single-process* knit may still fragment on the fit→APCA
   hop — caching the fits to disk (TODO) would let a re-knit skip the fit.

(Harness fixes in `_bughunt.R` — checkpoint/control isolation, package
bootstrap, load-then-bootstrap order — are NOT Rmd bugs.)
