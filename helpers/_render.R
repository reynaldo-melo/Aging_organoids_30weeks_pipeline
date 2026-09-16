Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
rmd <- "D:/Documents/Projetos/Aging_organoids_SCP/Full_analysis/20250502_SCP_WT83_7point5_Months/DIANN/DIANN/scp/Aging_organoids_30weeks_restructured.Rmd"
if (!file.exists(rmd)) stop("Rmd not found: ", rmd)
cat("Rendering", rmd, "\n"); t0 <- Sys.time()
rmarkdown::render(rmd, envir = new.env(), quiet = FALSE)
cat("RENDER DONE in", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
