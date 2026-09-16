## run_pipeline.R --------------------------------------------------------------
## Knit the restructured single-cell proteomics pipeline to HTML.
##
## Usage (from this directory):
##     Rscript run_pipeline.R
## or open Aging_organoids_30weeks_restructured.Rmd in RStudio and click Knit.
##
## Requirements: R (tested on 4.5.2), a working pandoc, the R packages listed in
## README.md, and the input data at PATHS$base (set at the top of the Rmd).
## A full knit takes ~20-25 min.
## -----------------------------------------------------------------------------

## rmarkdown needs pandoc. RStudio ships one; auto-detect it if RSTUDIO_PANDOC is
## unset (harmless if you already have pandoc on PATH).
if (Sys.getenv("RSTUDIO_PANDOC") == "" && .Platform$OS.type == "windows") {
  cand <- c("C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools",
            "C:/Program Files/RStudio/bin/quarto/bin/tools",
            "C:/Program Files/RStudio/bin/pandoc")
  hit <- cand[file.exists(file.path(cand, "pandoc.exe"))]
  if (length(hit)) {
    Sys.setenv(RSTUDIO_PANDOC = hit[1])
    message("Using pandoc from: ", hit[1])
  }
}

rmd <- "Aging_organoids_30weeks_restructured.Rmd"
if (!file.exists(rmd)) stop("Run this from the directory that contains ", rmd)

if (!requireNamespace("rmarkdown", quietly = TRUE))
  stop("Package 'rmarkdown' is required. install.packages('rmarkdown')")

t0 <- Sys.time()
message("Knitting ", rmd, " -- this takes ~20-25 min ...")
ok <- tryCatch({
  rmarkdown::render(rmd, output_file = "Aging_organoids_30weeks_restructured.html", quiet = FALSE)
  TRUE
}, error = function(e) { message("KNIT ERROR: ", conditionMessage(e)); FALSE })

message("Knit ", if (ok) "OK" else "FAILED", " in ",
        round(difftime(Sys.time(), t0, units = "mins"), 1), " min.")
if (ok) message("Output: Aging_organoids_30weeks_restructured.html")
