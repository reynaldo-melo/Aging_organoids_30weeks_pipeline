# ============================================================================
# _s9_from_cache.R — Session 9 differential analysis from the cached cluster-model
# fit, in a FRESH process (un-fragmented heap). Writes daRes.rds + checkpoint
# after_11 so _bughunt.R can resume Session 10.
# ============================================================================
options(warn = 1)
mark <- function(...) { cat(">>>>", ..., "\n"); flush.console() }
suppressPackageStartupMessages({
  library(scp); library(SingleCellExperiment); library(QFeatures); library(scater)
  library(tidyverse); library(ggrepel)
})

mark("load after_10 for scp / PATHS / PROC / marker_sets")
load("_ckpt/after_10.RData", envir = globalenv())
rm(sce); invisible(gc())                 # the clustered sce is not needed here

## clean save_fig (closure captures PATHS in this env)
save_fig <- function(plot, name, w = 7, h = 5) {
  stem <- tools::file_path_sans_ext(name)
  ggplot2::ggsave(file.path(PATHS$base, PATHS$fig, paste0(stem, ".png")),
                  plot, width = w, height = h, dpi = 300, device = grDevices::png, type = "cairo")
  ggplot2::ggsave(file.path(PATHS$base, PATHS$fig, paste0(stem, ".pdf")),
                  plot, width = w, height = h, device = grDevices::cairo_pdf)
  invisible(NULL)
}

mark("load cached cluster-model fit (sce_S9_postfit.rds)")
sce_da <- readRDS(file.path(PATHS$base, PATHS$obj, "sce_S9_postfit.rds"))
pdf(file.path(tempdir(), "_s9_plots.pdf"), width = 8, height = 6)
on.exit(grDevices::dev.off(), add = TRUE)

mark("variance analysis + plot")
vaResC <- scpVarianceAnalysis(sce_da)
vaResC <- scpAnnotateResults(vaResC, rowData(sce_da), by = "feature", by2 = "Genes")
print(scpVariancePlot(vaResC) + theme_minimal(base_size = 13))
rm(vaResC); invisible(gc())

mark("pairwise cluster contrasts (scpDifferentialAnalysis)")
cl <- sort(unique(colData(sce_da)$Cluster))
contrasts <- lapply(combn(cl, 2, simplify = FALSE), function(p) c("Cluster", p[1], p[2]))
daRes <- scpDifferentialAnalysis(sce_da, contrasts = contrasts)
np    <- scpModelFilterNPRatio(sce_da)
daRes <- scpAnnotateResults(daRes, data.frame(feature = names(np), npRatio = np), by = "feature")
daRes <- scpAnnotateResults(daRes, rowData(sce_da), by = "feature", by2 = "Stripped.Sequence")
saveRDS(daRes, file.path(PATHS$base, PATHS$obj, "daRes.rds"))
cat("   contrasts:", length(contrasts), "\n")

mark("volcano (bounded labels)")
options(ggrepel.max.overlaps = 10)
vp <- tryCatch(scpVolcanoPlot(daRes[1], top = 10, textBy = "Genes",
        pointParams = list(aes(colour = npRatio), size = 1.2)),
        error = function(e) { message("Volcano skipped: ", conditionMessage(e)); NULL })
if (!is.null(vp)) { print(vp[[1]]); save_fig(vp[[1]], "S9_volcano.png", 8, 6) }

mark("write checkpoint after_11.RData (for Session 10 resume)")
rm(sce_da, daRes, vp); invisible(gc())
save(list = setdiff(ls(), "mark"), file = "_ckpt/after_11.RData")
mark("DONE — Session 9 complete; after_11 written")
