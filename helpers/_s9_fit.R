# ============================================================================
# _s9_fit.R — Session 9 cluster-model fit, LEAN + cached.
# The in-harness Session 9 fit crashed at ~95% because it fit on `sce_da <- sce`
# where `sce` still carried the ~200 MB scplainer MINIMAL-model metadata from
# Session 6. Here we fit on a clean SCE (peptide matrix + Cluster only), and save
# the post-fit object to disk so the (~12-min) fit is never lost to an
# interruption and the DE step can run in a fresh, un-fragmented process.
# ============================================================================
options(warn = 1)
mark <- function(...) { cat(">>>>", ..., "\n"); flush.console() }
suppressPackageStartupMessages({
  library(scp); library(SingleCellExperiment); library(QFeatures); library(scater)
})

mark("load after_10 (S8 state): sce(clustered+AUCell), scp, PATHS, PROC, marker_sets")
load("_ckpt/after_10.RData", envir = globalenv())

mark("build LEAN cluster-fit SCE — drop the scplainer minimal-model metadata")
cat("   incoming sce size:", format(object.size(sce), units = "MB"), "\n")
an <- assayNames(sce)[1]
cd <- colData(sce); cd$Cluster <- as.character(colLabels(sce))
sce_da <- SingleCellExperiment(
  assays  = setNames(list(as.matrix(assay(sce))), an),
  colData = cd, rowData = rowData(sce))
rm(sce); invisible(gc())
cat("   lean sce_da size:", format(object.size(sce_da), units = "MB"),
    "| clusters:", paste(sort(unique(sce_da$Cluster)), collapse = ","), "\n")

mark("fit cluster model ~1+log_sumsRI+Cluster  (this is the step that died at 95%)")
sce_da <- scpModelWorkflow(sce_da, formula = PROC$cluster_form)
scpModelFilterThreshold(sce_da) <- 1
mark("saving sce_S9_postfit.rds")
saveRDS(sce_da, file.path(PATHS$base, PATHS$obj, "sce_S9_postfit.rds"))
mark("DONE — cluster-model fit complete and cached")
