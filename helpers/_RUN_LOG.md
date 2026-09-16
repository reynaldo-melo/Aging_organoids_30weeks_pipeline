# Autonomous run log — restructured pipeline (Aging_organoids_30weeks_restructured.Rmd)

Maintained by Claude while the user is away. Newest entries at the bottom.
Machine: R 4.5.2, 32 GB RAM, Windows. Driver: `_bughunt.R` (per-session
checkpoints in `_ckpt/`). Resume doc: `RESUME.md`.

## Plan (each heavy session = its own fresh R process — heap-fragmentation fix)

- [ ] S6 APCA + downstream  → `_s6_from_cache.R`        → after_08, sce_minimal.rds
- [ ] S7 + S8               → `_bughunt.R 9 10`          → after_09, after_10
- [ ] S9 cluster model + DE → `_bughunt.R 11 11`         → after_11, daRes.rds
- [ ] S10 trajectory        → `_bughunt.R 12 12`         → after_12, sce_trajectory.rds
- [ ] Harden Rmd fit-caching + final report

## Fixes already applied (before this session)

- S4: `filterFeatures(~ Global.PG.Q.Value <= QC$pg_qvalue)` → bind local scalar
  `pg_qvalue_thr` (formula read symbolically, mis-parsed `QC$pg_qvalue`).
- S6: drop scp peptide assays + `gc()` before APCA.
- S9: free `sce` before the cluster-model fit + `gc()` between steps.
- Root cause of crashes: scplainer fit + component/DE analysis in the SAME
  process fragments R's heap → next big alloc fails (not OOM). Mitigation:
  one fresh process per heavy session.

## Timeline

### Resume start
- State verified: latest checkpoint `after_07` (S5 done); S6 fit cached
  (`sce_S6_postfit.rds`, 26 MB); no R processes; 25.4 GB free.
- Launching leg 1: `_s6_from_cache.R` (finish S6 APCA from cached fit).

### Leg 1 — Session 6 APCA ✅ COMPLETE
- APCA **succeeded** in a fresh process → confirms the heap-fragmentation
  diagnosis and fix (fit + APCA must be in separate processes).
- `reducedDims = unmodelled, residuals, APCA_log_sumsRI` — `residuals` present,
  so Session 7 clustering can proceed.
- Wrote `after_08.RData` (52 MB) + `sce_minimal.rds` (26 MB).
- Non-fatal hiccup: `_s6_from_cache.R` called its `mark()` logger one line after
  `rm()`-ing it, so the script exited 1 AFTER everything was already saved.
  Cosmetic only; fixed the script.
- Launching leg 2: `_bughunt.R 9 10` (Sessions 7 + 8).

### Leg 2 — Sessions 7 + 8 ✅ COMPLETE (0.9 min, exit 0)
- S7 clustering on residuals: **3 clusters** (1:28, 2:47, 3:56 cells). → after_09
- S8 AUCell types (n=131): Immature_neuron 37, Progenitor 21, Glutamatergic 19,
  Proliferating 18, Astroglia 15, GABAergic 11, Mature_neuron 10. → after_10
- Figures/tables for S7/S8 written to Restructured_results/.
- 3 clusters ⇒ Session 9 has combn(3,2)=3 pairwise contrasts (OK, >=2 clusters).
- Launching leg 3: `_bughunt.R 11 11` (Session 9 — cluster model + DE, the memory
  hog; running one-process to validate the free-`sce`-early Rmd fix).

### Leg 3 — Session 9 ❌ CRASHED at 95% of the cluster-model fit
- Hard crash during `scpModelWorkflow(cluster_form)` at ~95% (no R error, no
  checkpoint). No completion notification fired and the run sat dead ~5 h until
  the user pinged — MONITORING GAP noted; caching the fit (below) makes this
  non-destructive going forward.
- Cause: either OOM/heap-fragmentation near the end of the fit, or the machine
  slept/rebooted while away. Likely aggravated because the fit ran on
  `sce_da <- sce`, and `sce` still carried the ~200 MB minimal-model metadata
  from S6 → ~400 MB dead weight during the fit.
- RECOVERY (fit/DE split, like S6):
  - `_s9_fit.R` — fit cluster model on a LEAN SCE (peptide matrix + Cluster only,
    no carried minimal-model metadata) → save `sce_S9_postfit.rds` (fit cached).
  - `_s9_from_cache.R` — fresh process: variance + DE + volcano → daRes.rds + after_11.
- Launching leg 3a: `_s9_fit.R`.

### DETOUR — cluster-number optimization (user request)
- User flagged we never optimized cluster number (S7 used fixed bluster
  NNGraphParam k=6, default walktrap → 3 clusters) and disliked the UMAP grouping.
- PAUSED leg 3a (the S9 cluster fit on the 3-cluster solution — likely moot once
  clustering changes; also frees memory for the sweep). S9 scripts preserved.
- Wrote `_k_sweep.R`: adapted the user's NeuronVsAPP template to WT83 —
  embedding = "residuals" (not "APCA_Condition"); k rescaled 4..30 for 131 cells;
  NO genotype here so ARI-vs-Condition replaced with ARI vs AUCell type + vs
  NA-cluster (QC check); inline ARI (no mclust); outputs to Restructured_results.
- Launching `_k_sweep.R` (read-only on pipeline state).

### k-sweep RESULT ✅ (exit 0)
- Louvain k=4..30 on residual embedding. n_clusters 8→2 as k rises.
- Silhouette weak (~0.1) for all k except trivial 2-cluster (~0.20); ARI vs AUCell
  type uniformly low (0.10-0.14). ⇒ NO strong discrete structure = CONTINUUM
  (consistent with a differentiation trajectory; matches user disliking the grouping).
- RED FLAG: ARI vs NA-cluster > ARI vs AUCell for most k ⇒ clusters track
  missingness/quality more than biology. Worst at 2 clusters (ari_naclust 0.27).
  ⇒ avoid the 2-cluster solution (it's a quality axis).
- Current pipeline 3-cluster (walktrap) is among least stable → supports redoing.
- RECOMMENDATION: trajectory (S10) is the primary biological model. If discrete
  groups needed for DE: k=10 → 4 clusters (best silhouette+stability among
  non-trivial; ari_aucell 0.13). Alt: k=6 → 5 clusters (highest cell-type ARI).
- Final k DEFERRED to user (their scientific/aesthetic call). S9 stays blocked
  on that choice. Outputs: S7_k_sweep_{summary,tSNE,composition}.{pdf,png},
  S7_k_sweep_summary.csv, S7_k_sweep_clusterings.rds.

### Leg 4 — Session 10 trajectory (independent of S7/S9 clustering)
- S10 uses scp[["Protein.Group"]] + its own internal Louvain + SOX2/NES root, so
  its results are NOT affected by the k choice → safe to run now.
- after_11 doesn't exist (S9 deferred); copying after_10 -> after_11 as a stand-in
  so the harness can resume S10 (S10 ignores S9 outputs). Real S9 will overwrite it.
- Watch points: prcomp(scale.=TRUE) zero-variance protein columns; SOX2/NES root;
  GAM driver loop; enrichGO.
- Launching `_bughunt.R 12 12`.

### Leg 4 — Session 10 trajectory ✅ COMPLETE (96 s, exit 0) → after_12
- Input 1631 proteins x 102 cells (22% drop); 1 lineage.
- Marker crossover plot: clear progenitor-high-early → neuron-high-late crossover
  (~pseudotime 75) = CORRECT biology. The Spearman rho table looks weak ONLY
  because the progenitor trend is non-monotonic (rises then falls); GAM driver
  detection (which handles non-monotonic) found 1058 drivers (502 up / 556 down).
- Absolute-abundance validation (no centring):
  * Ribosomal 100% down (median rho -0.23); Mitochondrial ~97% down (-0.34);
    DOWN drivers down (-0.29)  ← ROBUST, matches prior Python finding.
  * UP (neuronal) drivers FLAT on absolute scale (median +0.04, ~52% up)
    ← much weaker than documented Python CR (+0.26, 83% up).
- FLAG FOR USER: the DOWN program (ribosome+mito decline = proliferative/
  biosynthetic exit) is the robust, absolute-validated result. The UP (neuronal)
  program is relative/compositional and weak on absolute scale here. Likely cause:
  the restructured pipeline's STRICTER QC gate keeps 131 cells (vs 185 in the
  Python analysis) → 102 in the trajectory (vs 144) → less power for up-direction.
  Stricter-QC vs trajectory-power trade-off to weigh for the poster. NOT a bug.
- Minor oddity: progenitor module rises in early pseudotime (0-40) before the
  crossover — possible root/sub-structure; worth a look, not blocking.
- Outputs: S10_UMAP_pseudotime, S10_marker_crossover, S10_sensitivity,
  S10_absolute_validation (+ S10_drivers.csv, S10_GO_up/down.csv,
  S10_sensitivity.csv, S10_absolute_validation.csv, sce_trajectory.rds).
- NOTE: after_11 was a stand-in copy of after_10 (S9 deferred); S10 is independent
  of S9 so after_12 is valid. Real S9 will write a proper after_11 later.

### Rmd hardening (deliverable robustness) ✅
- S6: cache the minimal-model fit to sce_S6_postfit.rds (readRDS if present) →
  re-knit skips the 12-min fit AND the fragmentation that crashes APCA.
- S9: build a LEAN SCE for the cluster fit (drop the ~200 MB minimal-model
  metadata) → directly fixes the 95% crash cause.

### Quality-artifact diagnostic (user hypothesis) ✅ — answer: NOT an artifact
- Spearman rho(pseudotime, quality), 102 cells: detect_frac -0.07, mean_int -0.07,
  log_sumsRI -0.03 (all DECOUPLED); count -0.16, contam +0.11, diameter -0.25.
- "Everything declines with depth/quality" signature ABSENT (detection decoupled).
- Tertiles: LOW-pt (root) cells are HIGHEST quality (count 4869, detect 0.79,
  diam 15.5); quality non-monotonic → low-quality cells NOT anchoring pseudotime.
- Sensitivity corroborates: drop=0 IS the artifact (neurons -0.78/-0.79); the 22%
  drop already flips to the biological crossover (artifact was present, drop fixed it).
- Only residual coupling = diameter (-0.25), not accompanied by detection coupling
  → biological cell-size change, not quality. ⇒ do NOT filter further.
- Weak absolute-UP = power (102 vs 144 cells) + biology (down-program dominates).
- Output: S10_pseudotime_quality_check.csv.

### User chose k=10 → reclustering S7 (louvain k=10 -> 4 clusters) + re-running S9
- Rmd S7 updated: PROC$clust_k=10, PROC$clust_fun="louvain" (separate from S10 nn_k=6).
- Launching `_bughunt.R 9 10` (recluster S7 + S8) → new after_10 with 4 clusters,
  then `_s9_fit.R` (lean, cached) + `_s9_from_cache.R` (DE) → after_11.
- BUG (mine): first recluster still gave 3 clusters — I'd added PROC$clust_k/fun
  but forgot to change the clusterCells() call (still NNGraphParam(k=PROC$nn_k)).
  Fixed the call → now 4 clusters (1:36, 2:21, 3:25, 4:49). after_10 updated.
- Launching `_s9_fit.R` (lean cluster-model fit on 4 clusters; combn(4,2)=6 contrasts).
- S9 fit ✅ COMPLETE (100%): lean SCE 22 MB (vs 207 MB with metadata) → the 95%
  crash is gone. Cached sce_S9_postfit.rds. Launching `_s9_from_cache.R` (DE).

### Leg 5 — Session 9 DE ✅ COMPLETE (k=10 / 4 clusters)
- Lean fit (22 MB) cleared the crash; DE = 6 pairwise contrasts (peptide-level, padj<0.05):
  C1v4 4552, C1v3 3136, C1v2 2398, C3v4 1221, C2v4 879, C2v3 672.
  ⇒ Cluster 1 most distinct; clusters 2 & 3 most similar.
- Outputs: daRes.rds (5.9 MB), S9_volcano.png, after_11 (real S9 checkpoint).

### S10 re-run ✅ — checkpoint chain now consistent
- Re-ran `_bughunt.R 12 12` from the real after_11 (4-cluster S9). Identical results
  (1631 prot x 102 cells, 1 lineage, 1058 drivers, ribo 100%↓/mito 97%↓).
  after_08..after_12 now all on the k=10 4-cluster solution. Stopped here per user.

### Appendix A (user request) — running
- All deps installed (impute, SingleR, celldex, scRNAseq, zellkonverter).
- Running via dedicated `_appendixA.R` (per-step tryCatch; harness whole-session
  eval won't honor per-chunk error=TRUE). A.1 (impute->PCA->recluster->markers,
  no network) saves first; A.2 SingleR vs Blueprint/Zhong/laManno each isolated.
  HNOCA skipped (eval=FALSE, needs local h5ad). Loads after_12.
- ✅ COMPLETE (exit 0). FIX: modelGeneVar fails on the per-protein-centred matrix
  even with density.weights=FALSE (means all ~0) → use top-variance HVGs instead
  (patched in both _appendixA.R and the Rmd A.1).
- A.1 imputed reclustering: 4 clusters (23/42/51/15). sce_imputed.rds saved.
  (Imputed cluster 1 top markers = skin-ish KPRP/CSTA/SERPINB12 + VIM → looks like
  a residual low-quality/contaminant group in imputed space; sanity branch only.)
- A.2 SingleR (sce_imputed_annotated.rds + A2_SingleR_*.csv):
  * Blueprint (immune/stromal sanity ref): mostly forced/noise (Neutrophils 35,
    B-cells 19...) — expected; only Neurons 18 relevant → cells aren't immune.
  * Zhong-2018 prefrontal cortex (primary): GABAergic neurons 38 + Neurons 8,
    Astrocytes 20, Microglia 43(?), OPC 8, Stem cells 14 = developing-cortex mix.
  * laManno-2016 iPSC brain: radial-glia-like iRgl1 DOMINANT (59/131) + progenitors
    (~17) + dopaminergic (26) + neuroblasts (8) → progenitor/radial-glia-heavy,
    consistent with the trajectory being progenitor-rich, mid-differentiation.
  * Caveat: SingleR forces a label per cell; organoid-vs-these-refs calls are
    approximate. Cross-ref theme = neuronal + progenitor/radial-glia + astroglia.

### Appendix A.2b — non-centred SingleR + verification ✅
- Non-gene-centred log-abundance protein matrix (aggregate peptides_log_noNorm ->
  protein), KNN-imputed, SingleR vs Blueprint/Zhong/laManno.
- Centering effect LARGE: per-cell agreement centred-vs-noncentred = Blueprint 6%,
  Zhong 19%, laManno 39% ⇒ input representation dominates; non-centred (abundance)
  is the correct SingleR input.
- Quality (delta = top-2nd score) LOW across all refs (frac delta<0.05: Blueprint
  100%, Zhong 74%, laManno 88%) → cross-modality (protein vs RNA) makes SingleR weak;
  Blueprint (immune ref) useless.
- VERIFICATION (pseudotime ordering — decisive): progenitor-type labels sit at LOWER
  pseudotime than neuron labels in ALL 3 refs (Zhong Stem 77.8 < Neurons 94.9;
  laManno iRgl1 74.3 < iNb2 93.4; Blueprint Fibroblasts 59.6 < Neurons 94.6) ⇒ the
  coarse progenitor->neuron axis is REAL, concordant with the trajectory. AUCell
  concordance only PARTIAL/over-broad (Zhong "Stem cells" = low-conf catch-all) ⇒
  fine labels unreliable.
- VERDICT: non-centred = correct SingleR input; treat SingleR as SOFT COARSE
  corroboration of the progenitor->neuron trajectory, not confident subtyping;
  laManno best-discriminated. Outputs: A2b_* figs/tables, A2b_delta_confidence.*,
  sce_imputed_noncentered_annotated.rds, A2b_preds_noncentered.rds.

### Rmd integration — non-centred SingleR is now canonical Appendix A.2 ✅
- S4: build `Protein.Group_abund` (aggregate peptides_log_noNorm -> protein, NON-
  centred absolute log abundance) alongside centred Protein.Group; added to keep_assays
  (survives S6 assay cleanup).
- Appendix A.2 rewritten: impute Protein.Group_abund -> SingleR vs Blueprint/Zhong/
  laManno (each tryCatch-isolated) on the NON-centred matrix; A.1 reclustering still
  uses centred imputed Protein.Group.
- Added scoring-quality panels: plotScoreHeatmap per ref + custom delta-confidence
  panel (robust to singleton labels) + SingleR-call UMAP overlays.
- VERIFIED the two new QFeatures ops (aggregateFeatures + impute) reproduce the
  verified manual aggregation exactly (max diff 8.9e-15; impute -> 0 NA). SingleR +
  plotting downstream already verified via the helper scripts.
- A fresh knit will regenerate; existing checkpoints predate Protein.Group_abund so
  resuming the Appendix needs a re-run from S4 (or use the helper scripts).

### Residual-APCA biplot (user request) ✅
- Adapted the NeuronVsAPP APCA biplot to WT83 residual APCA (scplainer minimal-model
  biological component). No genotype here → colour by cluster / AUCell / Trans_Diameter
  / pseudotime. Top-10 loadings deduped to one peptide per GENE (peptide-level stacked
  5 GLUD1 arrows; gene-level shows 10 distinct drivers).
- Drivers split cleanly: proliferation/cell-cycle (CDK1, CDK6, RRM2) vs neuronal
  (TUBB3, STMN1, DBNL) + GLUD1/FASN (metabolic) toward cluster 1 — confirms the
  progenitor↔neuron axis in the residual PCA. PC% is a proxy (APCA stores no percentVar).
- Standalone: `_biplot_apca.R` -> S6_biplot_residualAPCA_{cluster,AUCell,diameter,
  pseudotime}.{pdf,png} + S6_biplot_residualAPCA_top_loadings.{pdf,png}.
- Rmd integration: S6.1 stores residual loadings on metadata(sce); new S8.4 chunk
  (identity-biplot + identity-biplot-loadings) renders the biplots + per-protein panels
  -> S8_biplot_residualAPCA_*. (Placed in S8 so cluster+AUCell exist and before S9's rm(sce).)

### Trajectory-curve images (user request) ✅
- Slingshot principal curve overlaid on the embedding, coloured by cluster + by
  pseudotime (per-lineage panels when >1 lineage). 1 lineage here:
  cluster 1 -> 4 -> 2 -> 5 -> 3 (102 cells), rooted at SOX2/NES-high cluster 1.
- KEY CHOICE: plotted in the compPCA FITTING space, NOT UMAP. embedCurves() onto
  UMAP produced a tangled self-intersecting curve (UMAP is a nonlinear distortion
  of compPCA; at n=102 the projected principal curve self-crosses) — misleading.
  compPCA PC1/PC2 shows the curve tracing smoothly root->end (minor 2D-projection
  bend only). Pseudotime gradient is monotonic along the curve (dark root -> bright end).
- Standalone `_traj_curves.R` -> S10_trajectory_clusters.{pdf,png} +
  S10_pseudotime_trajectory.{pdf,png}. Wired into Rmd as Session 10.2.1 (traj-curves
  chunk), after the slingshot fit; stores Pseudotime_L<i> in colData(sceTraj).

### Trajectory model-selection sweep (user questions) — current method wins
Tested alternative embeddings for the trajectory (same 102 cells; marker rho scored
on the standard log_sumsRI-only compositional residuals; progenitor<0/neurons>0):
| method | Prog | Immat | Mature | cor vs current | quality decoupling |
|---|---|---|---|---|---|
| **current** (protein OLS compositional, ~log_sumsRI) | **-0.48** | **+0.68** | **+0.82** | 1.00 | clean (diam -0.25=biology) |
| option a (scplainer PEPTIDE residuals) | +0.30✗ | -0.29✗ | -0.26✗ | -0.45 | ok but REVERSED (peptide noise) |
| hybrid (scplainer resid AGGREGATED to gene) | -0.22 | +0.31 | +0.37 | +0.42 | count-coupled (+0.32) |
| +diameter (~log_sumsRI+Trans_Diameter) | -0.19 | +0.58 | +0.42 | +0.26 | ALL couplings ~0 |
- Peptide-level scplainer residuals = noise reverses the axis; aggregating to gene
  recovers correct direction but ~half signal + residual count-coupling (scplainer
  removes log_sumsRI, not count). ⇒ keep the current protein-compositional method.
- +diameter: trajectory SURVIVES (correct dirs) but mature-neuron halves (+0.82->+0.42)
  and progenitor weakens (-0.48->-0.19) while diameter/count/log_sumsRI couplings ->~0.
  Mature-neuron taking the biggest hit = diameter is COLLINEAR with late differentiation
  (neurons = smallest cells). ⇒ diameter is a CONFOUND (partly biology); do NOT model it
  out in the main trajectory, BUT the diameter-regressed run is a strong ROBUSTNESS check
  ("signature persists after regressing out cell size"). Saved sce_trajectory_{optionA,hybrid}.rds.

### DEFINITIVE: scplainer is defensible IF protein-level + per-cell centering
Fair scplainer test (`_traj_scplainer_protein.R`): scpModelWorkflow(~1+log_sumsRI)
@ PROTEIN level on the 22%-dropped + 30%-filtered matrix -> scpModelResiduals ->
per-cell centre -> prcomp -> slingshot REPRODUCES/EXCEEDS the manual OLS method
(prog -0.50, immat +0.83, mature +0.84; cor 0.90 with current). ⇒ scplainer's
MODEL is a defensible drop-in.
Load-bearing-step test (`_traj_scplainer_apca.R`, SAME model, two embeddings):
| embedding | Prog | Immat | Mature | log_sumsRI coupling | mean_int coupling |
|---|---|---|---|---|---|
| (A) scplainer APCA "residuals" (no centring) | -0.06 | +0.02 | -0.05 | **+0.40** | **-0.38** |
| (B) scpModelResiduals + PER-CELL CENTRE + prcomp | -0.50 | +0.83 | +0.84 | -0.01 | -0.13 |
cor(A,B) = -0.06; cor(B,current)=0.90; cor(A,current)=-0.09.
⇒ PER-CELL CENTERING is the load-bearing step, NOT the model. scplainer's
off-the-shelf model->APCA workflow REPRODUCES THE MAGNITUDE ARTIFACT (pseudotime =
depth/mean_int axis, zero biology) because APCA centers per-feature, not per-cell;
the residual global-magnitude axis survives log_sumsRI removal. Recipe: scplainer
~1+log_sumsRI @ protein -> scpModelResiduals -> per-cell centre -> PCA -> slingshot.
APCA-only is the negative control that motivates the centring. Saved
sce_trajectory_scplainerProtein.rds.

### IF-validated cortical-organoid markers (user file) — CONFIRM the trajectory
`cortical organoid markers_scProt_MGL.xlsx` = 23 cell-type/state modules. Scored vs
pseudotime (`_traj_if_markers.R`): Neural progenitors -0.53 ↓, Radial glia -0.48 ↓,
Immature neurons +0.65 ↑, Pan neuronal +0.70 ↑ → clean progenitor->neuron crossover
(~pseudotime 75), independent IF-validated confirmation (stronger than the old
hardcoded set). CAVEAT: proteomics detects only 3-4 structural markers/module; TF/
receptor-heavy modules undetectable (Cortical identity 0/10, Intermediate progenitors
0/11, Glutamatergic 0/16, layer/GABAergic/interneuron/OPC/oligo/microglia/cell-cycle
0-1) — expected SCP limitation, consistent with a neuron+progenitor-dominated 30-wk
organoid. Astrocyte modules go DOWN only because their detected markers overlap radial
glia (progenitor signal, not mature astro). Outputs: S10_IF_marker_crossover.{png,pdf},
S10_IF_marker_rho.csv, IF_marker_sets.rds.
WIRED INTO Rmd (verified `_verify_if_integration.R`): S8.1 marker_sets = 23 IF modules
(embedded literal) + S8_IF_marker_detection.csv + marker_sets_det (11 modules >=3
detected) for scoring/UMAP; S8.3 AUCell classifies into the IF types (Immature_neurons
24, Pan_neuronal 18, Neural_progenitors 9, Radial_glia 8, ...); S10 crossover +
sensitivity use Neural_progenitors/Immature_neurons/Pan_neuronal. Caveat: AUCell
force-assigns sparse modules (GABAergic/interneurons) off a few ambiguous markers ->
low-conf; module scores + trajectory crossover are the rigorous readout.

### Unified clustering+UMAP onto compositional PCA (user request) ✅
- S6 now builds shared `compPCA` (131 cells x 15 PCs): regress log_sumsRI/protein +
  per-cell centre -> scaled prcomp (same method as trajectory, no 22% drop). S7
  clustering+UMAP+tSNE switched from scplainer residual APCA -> compPCA. Residual
  APCA retained for the S8.4 biplot only.
- Re-swept k on compPCA (`_k_sweep_compPCA.R`): k=10 -> 4 clusters is the silhouette
  + ARI-vs-celltype optimum (ARI 0.255 vs ~0.13 on residual APCA -> clusters MORE
  cell-type-coherent). k unchanged (10).
- BUG FIXED: Louvain is stochastic; S7 had no seed -> flickered 4/5 clusters. Added
  set.seed(101) before clusterCells -> deterministic 4 clusters (34/57/32/8).
- Verified S6+S7 via harness (after_09 updated). DOWNSTREAM: S8 (identity/AUCell/
  biplot) + S9 (DE) regenerate on the new clusters (different from old 36/21/25/49);
  S10 trajectory unaffected (own compPCA on 102 cells). Fresh knit regenerates all;
  for checkpoints use S8 via harness + S9 via lean fit/DE split on the new after_10.

### Regeneration on compPCA clusters ✅ COMPLETE (chain consistent)
Re-ran S8 -> S9 (lean fit/DE split) -> S10 on the new compPCA 4-cluster solution.
Checkpoints after_08..after_12 all rebuilt today, consistent.
- S8: AUCell (IF markers) Immature_neurons 25, Pan_neuronal 14, Neural_progenitors 10,
  Radial_glia 10, + glial/metabolic. New clusters.
- S9 DE (4 clusters, 6 contrasts; lean fit no crash): C1v2 4127, C1v3 2336, C2v3 1250,
  C1v4 935, C2v4 366, C3v4 275. Clusters 1&2 most distinct, 3&4 most similar.
- S10 trajectory unchanged (own compPCA on 102 cells): DOWN program robust (ribo 100%,
  mito 97% down), UP flat on absolute scale.

### Detection filter 10% vs 30% test (`_test_mindet.R`) -> KEEP 30%
- CLUSTERING worse at 10%: silhouette COLLAPSES 0.177 -> -0.017 (4 clusters both, but
  10% ones not separated). The ~800 extra sparse proteins (NA->0) inject detection-
  pattern noise, not a rare coherent cluster. User's "10 cells -> coherent cluster"
  hypothesis NOT supported.
- TRAJECTORY robust: marker rho slightly STRONGER at 10% (prog -0.54/immat +0.85/
  panneu +0.81 vs -0.50/+0.76/+0.76), quality coupling similar/lower. Pseudotime is a
  continuum dominated by abundant proteins; sparse extras add little.
- DECISION: keep min_det=0.30 (cleaner clusters; trajectory insensitive). Proteins:
  10%->2325/2445, 30%->1528/1631.

## CURRENT STANDING — FULL PIPELINE COMPLETE (S0–S10)
- DONE end-to-end on the k=10 louvain 4-cluster solution. All checkpoints
  (after_08..after_12), rds objects, figures, tables written.
- Quality-artifact question answered: pseudotime is NOT a quality axis (detection/
  depth decoupled); the 22% drop already removed the artifact. Weak absolute-UP =
  power + biology, not artifact. Do not filter further.
- Rmd hardened: S6 fit cached; S9 fit lean; S7 clustering = louvain k=10 (PROC knobs).
- Checkpoint bookkeeping note: after_12 (S10) was built from a stand-in after_11
  (pre-S9), but S10 is clustering-independent so its outputs are valid; only the
  scp/sce labels stored inside after_12 are the old 3-cluster ones. Re-running S10
  from the new after_11 (96 s) would make the chain fully consistent — OPTIONAL,
  changes no results.
- OPTIONAL remaining: (a) Appendix A SingleR (needs scRNAseq/zellkonverter — may be
  uninstalled); (b) full HTML knit of the Rmd (note: S9 fit is lean but NOT cached
  in-Rmd, so a single-process knit re-runs the cluster fit — use the helper scripts
  / fresh-process-per-session per the resume sequence to be safe).
