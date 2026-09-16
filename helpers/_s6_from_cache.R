# ============================================================================
# _s6_from_cache.R — finish Session 6 from the cached post-fit sce in a FRESH
# process, so APCA gets an un-fragmented heap (the in-process fit fragments it
# and makes scpComponentAnalysis crash). Writes harness checkpoint after_08 so
# _bughunt.R can resume Session 7 normally.
# ============================================================================
options(warn = 1)
mark <- function(...) { cat(">>>>", ..., "\n"); flush.console() }
suppressPackageStartupMessages({
  library(scp); library(SingleCellExperiment); library(QFeatures)
  library(scater); library(scran); library(scuttle); library(bluster)
  library(tidyverse); library(patchwork); library(ggrepel)
})

mark("load Session 5 state (after_07) for scp / PATHS / PROC")
load("_ckpt/after_07.RData", envir = globalenv())

## mirror the edited Session-6 memory step: drop scp's peptide-level assays
scp <- removeAssay(scp, intersect(c("peptides", "peptides_log_noNorm"), names(scp)))
invisible(gc())

mark("load cached post-fit sce (skips the 12-min in-process fit)")
sce <- readRDS(file.path(PATHS$base, PATHS$obj, "sce_S6_postfit.rds"))
cat("   sce:", nrow(sce), "peptides x", ncol(sce), "cells\n")

## route plots to a throwaway device (Rscript has no interactive device)
pdf(file.path(tempdir(), "_s6_from_cache_plots.pdf"), width = 7, height = 6)
on.exit(grDevices::dev.off(), add = TRUE)

mark("scpModelFilterPlot")
print(scpModelFilterPlot(sce))

mark("scpVarianceAnalysis + annotate + plot")
vaRes <- scpVarianceAnalysis(sce)
vaRes <- scpAnnotateResults(vaRes, rowData(sce), by = "feature", by2 = "Stripped.Sequence")
print(scpVariancePlot(vaRes) + theme_minimal(base_size = 13))

mark("gc, then scpComponentAnalysis(ncomp=10, APCA)  [the crash-in-fitted-process step]")
invisible(gc())
caRes      <- scpComponentAnalysis(sce, ncomp = 10, method = "APCA")
sce$cell   <- colnames(sce)
caResCells <- scpAnnotateResults(caRes$bySample,  colData(sce), by = "cell")
caResPeps  <- scpAnnotateResults(caRes$byFeature, rowData(sce), by = "feature", by2 = "Genes")
sce <- addReducedDims(sce, caResCells)
cat("   reducedDims:", paste(reducedDimNames(sce), collapse = ", "), "\n")
print(scpComponentPlot(caResCells, pointParams = list(aes())))
saveRDS(sce, file.path(PATHS$base, PATHS$obj, "sce_minimal.rds"))

mark("writing harness checkpoint after_08.RData")
## drop probe-only helper from the checkpoint but keep it live for the final log
save(list = setdiff(ls(), "mark"), file = "_ckpt/after_08.RData")
mark("DONE — Session 6 complete; after_08 written. reducedDims above must include 'residuals'.")
