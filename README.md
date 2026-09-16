# Aging Organoids — 30-week (WT83) Single-Cell Proteomics Pipeline

Restructured, reproducible analysis pipeline for the single-cell proteomics (SCP)
study of 30-week WT83 human brain organoids (cellenONE isolation + Orbitrap Astral
DIA; DIA-NN identification; `scplainer`/`scran` analysis).

**Author:** Reynaldo M. Melo (Scripps Research)

---

## Contents

| File | Description |
|------|-------------|
| `Aging_organoids_30weeks_restructured.Rmd` | The full pipeline (Session 0 → Session 12 + Appendix A). **Self-contained**: all analysis code and the immunofluorescence-validated marker-set definitions are inline — it does not `source()` any other file. |
| `run_pipeline.R` | One-command knit runner (auto-detects pandoc, renders the Rmd to HTML). |
| `helpers/` | Optional auxiliary scripts for a **from-scratch** rebuild (see *Sessions 6 & 9* below) and the original run notes (`RESUME.md`, `_RUN_LOG.md`). Not needed for a normal knit. |
| `README.md` | This file. |

---

## Requirements

- **R** (tested on 4.5.2) and **pandoc** (bundled with RStudio; `run_pipeline.R` auto-detects it, or set the `RSTUDIO_PANDOC` environment variable).
- **R packages** (Bioconductor + CRAN):
  - *SCP / SingleCellExperiment:* `scp`, `SingleCellExperiment`, `QFeatures`, `scater`, `scran`, `scuttle`, `bluster`
  - *Modeling / trajectory / enrichment:* `slingshot`, `TrajectoryUtils`, `mgcv`, `clusterProfiler`, `org.Hs.eg.db`, `AUCell`, `GSEABase`, `SingleR`, `celldex`
  - *Tidy / visualization / knit:* `tidyverse`, `patchwork`, `ggrepel`, `ComplexHeatmap`, `circlize`, `pheatmap`, `viridis`, `RColorBrewer`, `MASS`, `rmarkdown`, `knitr`

---

## Input data (large — not included here)

The pipeline reads its inputs from the absolute path in the Rmd's `PATHS` list (Session 0):

```
PATHS$base = D:/Documents/Projetos/Aging_organoids_SCP/Full_analysis/20250502_SCP_WT83_7point5_Months
```

- Single-cell DIA-NN report: `<base>/DIANN/DIANN/report_arrow/part-0.tsv`
- Blank-run DIA-NN report:  `<base>/Blanks/DIANN/DIANN/report_arrow/part-0.tsv`
- Sample annotation:        `<base>/DIANN/sampleAnnotation.csv`

If the data lives elsewhere, edit `PATHS$base` at the top of the Rmd. Outputs are
written under `<base>/DIANN/DIANN/scp/Restructured_results/{Figures,Tables,Objects}`.

---

## How to run

```bash
Rscript run_pipeline.R
```

or open `Aging_organoids_30weeks_restructured.Rmd` in RStudio and click **Knit**.
A full knit takes **~20–25 min** and produces `Aging_organoids_30weeks_restructured.html`.

### Sessions 6 & 9 (scplainer fits) — important on Windows

Running the heavy `scplainer` model fit and its downstream APCA / differential
analysis in the **same** R process can fragment memory and crash. The Rmd guards
against this: **Session 6 loads `sce_minimal.rds` and Session 9 loads
`sce_S9_postfit.rds`** from `Restructured_results/Objects/` when present, skipping
the crash-prone recompute — so with those caches in place, `rmarkdown::render`
knits end-to-end in a single process.

For a **clean from-scratch rebuild** (no caches yet), use the staged runner in
`helpers/`, which runs each session in its own fresh R process and generates the
caches:

- `helpers/_bughunt.R` — staged runner (`Rscript _bughunt.R auto`).
- `helpers/_s6_from_cache.R` — finishes Session 6's APCA from the cached fit.
- `helpers/_s9_fit.R` + `helpers/_s9_from_cache.R` — lean cluster-model fit / DE split.

(These helpers use absolute paths pointing at the original analysis directory; adjust if you relocate the data.)

---

## Output

`Aging_organoids_30weeks_restructured.html`, plus every figure (300-dpi PNG **and**
vector PDF), table (CSV), and saved object (RDS) under `Restructured_results/`.

---

## Source

Version-controlled (private) at **https://github.com/reynaldo-melo/scp-brain-organoids**.
