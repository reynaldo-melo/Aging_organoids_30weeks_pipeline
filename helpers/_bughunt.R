# ============================================================================
# _bughunt.R  — staged runner for Aging_organoids_30weeks_restructured.Rmd
# Extracts code chunks grouped by "# Session" header, runs them in order inside
# a DEDICATED pipeline environment (penv), checkpoints ONLY penv after each
# session, and supports resuming. Control state (START/STOP/chunks) lives in the
# global env and is never clobbered by a checkpoint load — so an Rmd edit always
# takes effect on resume.
#
# Usage:
#   Rscript _bughunt.R [START] [STOP] [appendix]
#     START   1-based session ORDER index to start at (default 1)
#     STOP    session ORDER index to stop after (default = last non-appendix)
#     appendix  literal word "appendix" to also run Appendix A / Session info
# Resume loads _ckpt/after_<START-1>.RData into penv first.
# ============================================================================

RMD   <- "Aging_organoids_30weeks_restructured.Rmd"
CKDIR <- "_ckpt"
dir.create(CKDIR, showWarnings = FALSE)

args  <- commandArgs(trailingOnly = TRUE)
## latest on-disk checkpoint index (0 if none) — used by "auto" resume so a
## reboot just needs:  Rscript _bughunt.R auto
latest_ckpt <- function() {
  fs <- list.files(CKDIR, pattern = "^after_\\d+\\.RData$")
  if (!length(fs)) return(0L)
  max(as.integer(sub("^after_(\\d+)\\.RData$", "\\1", fs)))
}
START <- if (length(args) >= 1) {
  if (identical(args[[1]], "auto")) latest_ckpt() + 1L else as.integer(args[[1]])
} else 1L
STOPa <- if (length(args) >= 2 && !is.na(suppressWarnings(as.integer(args[[2]]))))
  as.integer(args[[2]]) else NA_integer_
RUN_APPENDIX <- "appendix" %in% args

# ---- pipeline object store, kept separate from driver control state ---------
penv <- new.env(parent = globalenv())

# ---- parse Rmd into (header, code) chunks in document order ----------------
lines <- readLines(RMD, warn = FALSE)
chunks <- list(); cur_hdr <- "(preamble)"; i <- 1L; n <- length(lines)
while (i <= n) {
  ln <- lines[[i]]
  if (grepl("^#\\s+", ln)) {                       # top-level markdown header
    cur_hdr <- sub("^#\\s+", "", ln)
  } else if (grepl("^```\\{r", ln)) {              # open code chunk
    j <- i + 1L
    while (j <= n && !grepl("^```\\s*$", lines[[j]])) j <- j + 1L
    code <- if (j - 1L >= i + 1L) lines[(i + 1L):(j - 1L)] else character(0)
    chunks[[length(chunks) + 1L]] <- list(hdr = cur_hdr, code = code)
    i <- j
  }
  i <- i + 1L
}

# ---- group chunks into ordered sessions by header --------------------------
hdrs <- vapply(chunks, function(c) c$hdr, character(1))
sess_order <- unique(hdrs)                          # in document order
is_appendix <- function(h) grepl("Appendix|Session info", h, ignore.case = TRUE)

if (is.na(STOPa)) {
  non_app <- which(!vapply(sess_order, is_appendix, logical(1)))
  STOPa <- max(non_app)
}

cat(sprintf("Parsed %d chunks across %d sessions:\n", length(chunks), length(sess_order)))
for (k in seq_along(sess_order))
  cat(sprintf("  [%2d] %s\n", k, sess_order[[k]]))
cat(sprintf("Running session order %d .. %d  (appendix=%s)\n\n", START, STOPa, RUN_APPENDIX))

# ---- run one session's chunks in penv (defined before bootstrap uses it) ----
run_one <- function(hdr) {
  these <- chunks[hdrs == hdr]
  code  <- unlist(lapply(these, function(c) c$code))
  if (!length(code)) { cat("  (no code)\n"); return(invisible(TRUE)) }
  expr <- tryCatch(parse(text = code),
                   error = function(e) { cat("  PARSE ERROR:", conditionMessage(e), "\n"); NULL })
  if (is.null(expr)) return(FALSE)
  ok <- TRUE
  withCallingHandlers(
    tryCatch(eval(expr, envir = penv),            # <-- run in pipeline env
      error = function(e) {
        ok <<- FALSE
        cat("  >>> ERROR:", conditionMessage(e), "\n")
        cc <- conditionCall(e)
        if (!is.null(cc)) cat("  >>> in call:", paste(deparse(cc), collapse = " "), "\n")
      }),
    warning = function(w) invokeRestart("muffleWarning"))
  ok
}

# ---- resume: load checkpoint data, THEN bootstrap packages/helpers ----------
# Order matters. A checkpoint .RData stores objects but NOT the attached-package
# search path, so on resume we must re-run the preamble + Session 0 (library() +
# params) to make functions like filterFeatures()/scpModelWorkflow() available.
# We load the checkpoint FIRST and bootstrap SECOND so that Session 0's helper
# closures (save_fig/save_tab, which capture PATHS) are freshly defined IN penv
# and overwrite the stale saved copies — a saved function's closure otherwise
# rebinds to globalenv on load and can't see PATHS in penv.
if (START > 1L) {
  ck <- file.path(CKDIR, sprintf("after_%02d.RData", START - 1L))
  if (!file.exists(ck)) stop("Cannot resume: missing checkpoint ", ck)
  cat("Loading checkpoint into penv:", ck, "\n"); load(ck, envir = penv)
  for (b in 1:2) {                                # [1] (preamble), [2] Session 0
    cat(sprintf("[%2d] BOOT  %s\n", b, sess_order[[b]]))
    if (!run_one(sess_order[[b]]))
      stop("Bootstrap failed at: ", sess_order[[b]])
  }
}

# ---- run sessions ----------------------------------------------------------
checkpoint <- function(k) {
  obj <- ls(penv, all.names = TRUE)
  save(list = obj, envir = penv, file = file.path(CKDIR, sprintf("after_%02d.RData", k)))
}

t0 <- Sys.time()
for (k in seq_along(sess_order)) {
  if (k < START || k > STOPa) next
  hdr <- sess_order[[k]]
  if (is_appendix(hdr) && !RUN_APPENDIX) { cat(sprintf("[%2d] SKIP  %s\n", k, hdr)); next }
  cat(sprintf("[%2d] RUN   %s\n", k, hdr)); flush.console()
  ts <- Sys.time()
  ok <- run_one(hdr)
  dt <- round(as.numeric(difftime(Sys.time(), ts, units = "secs")), 1)
  if (!ok) {
    if (is_appendix(hdr)) { cat(sprintf("[%2d] FAIL (tolerated, appendix) %ss\n\n", k, dt)); next }
    cat(sprintf("\n[%2d] FAILED after %ss — stopping. Fix the Rmd and resume:\n", k, dt))
    cat(sprintf("     Rscript _bughunt.R %d\n", k))
    quit(status = 1L)
  }
  checkpoint(k)
  cat(sprintf("[%2d] OK    %ss  (checkpoint after_%02d.RData)\n\n", k, dt, k))
}
cat(sprintf("ALL DONE in %s min\n",
            round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)))
