#!/usr/bin/env Rscript
# emulate_optimised.R — optimised GP emulator (repo-relative, Windows/HPC compatible)
# - Same CLI as baseline: <ilat> <ilon> <month>
# - Input discovery: primary lat_<LAT>_lon_<LON>.dat (lat=3dp, lon=4dp); legacy fallback
# - Prefers constrained_multi_million_sample.{RData|rds}; auto-detects object name
# - Same design slicing (drop col 43; remove carbon group)
# - Uses JJCode_EmPred_LargeSample.r from scripts/gp/optimised/
# - Fixed 10,000-row cap by default (edit reduce_size to scale up)
# - Writes to .../gp_emulation/optimised/lat<LAT>/
# - Logs train/predict timings

## -------------------- Args --------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) stop("Usage: Rscript scripts/gp/optimised/emulate_optimised.R <ilat> <ilon> <month>")
ilat  <- as.numeric(args[1])
ilon  <- as.numeric(args[2])
month <- as.character(args[3])

options(stringsAsFactors = FALSE)
Sys.setlocale("LC_NUMERIC","C"); options(OutDec=".", scipen = 0)

## -------------------- Repo root --------------------
args_full  <- commandArgs(trailingOnly = FALSE)
scriptPath <- normalizePath(sub("--file=", "", args_full[grep("--file=", args_full)]))
repo_root  <- normalizePath(file.path(dirname(scriptPath), "..", "..", ".."))

## -------------------- Paths (ENV overrides; sensible defaults) --------------------
user_lib_path <- Sys.getenv("R_LIBS_USER", unset = "~/R/x86_64-pc-linux-gnu-library/4.3")

TRAIN_BASE <- Sys.getenv("TRAIN_BASE",
  unset = file.path(repo_root, "examples", "tiny_sample_inputs", "H2SO4", "jan")
)
DESIGN_FILE <- Sys.getenv("DESIGN_FILE",
  unset = file.path(repo_root, "examples", "design", "UKESM_PPE_Unit_emulation_ready.dat")
)
SAMPLE_DIR <- Sys.getenv("SAMPLE_DIR",
  unset = file.path(repo_root, "examples", "large_sample")
)
# ⬇️ Updated as requested (optimised folder)
JJCODE_FILE <- Sys.getenv("JJCODE_FILE",
  unset = file.path(repo_root, "scripts", "gp", "optimised", "JJCode_EmPred_LargeSample.r")
)
OUTPUT_ROOT <- Sys.getenv("OUTPUT_ROOT",
  unset = file.path(repo_root, "examples", "tiny_sample_outputs", "gp_emulation", "optimised")
)

if (!dir.exists(user_lib_path)) dir.create(user_lib_path, recursive = TRUE, showWarnings = FALSE)

## -------------------- Packages --------------------
install_if_missing <- function(package, lib, repo = "http://cran.us.r-project.org") {
  if (!require(package, character.only = TRUE, lib.loc = lib)) {
    install.packages(package, lib = lib, repos = repo)
    library(package, character.only = TRUE, lib.loc = lib)
  }
}
pkgs <- c("DiceKriging", "sensitivity", "lhs", "trapezoid", "readr", "truncnorm")
for (p in pkgs) install_if_missing(p, user_lib_path)
invisible(lapply(pkgs, function(p) library(p, character.only = TRUE, lib.loc = user_lib_path)))

## -------------------- Config (unchanged semantics) --------------------
# Limit predictions to the first 10,000 rows for quick tests.
# Increase this number to scale up, e.g., 100000, 1000000, or more,
# provided your constrained sample has that many rows.
reduce_1M   <- 1
reduce_size <- 50000
sample_size <- 2  # retained for compatibility with original structure

## -------------------- Read training data (primary + fallback) --------------------
# Primary: lat_%.3f_lon_%.4f.dat  (matches your tiny inputs)
datafile_primary <- file.path(TRAIN_BASE, sprintf("lat_%.3f_lon_%.4f.dat", ilat, ilon))
# Fallback: legacy nested name
datafile_fallback <- file.path(
  TRAIN_BASE, sprintf("lat_%s", ilat),
  sprintf("H2SO4_%s_ilat_%s_ilon_%s.dat", month, ilat, ilon)
)
datafile <- if (file.exists(datafile_primary)) datafile_primary else datafile_fallback
if (!file.exists(datafile)) {
  stop("Training data not found. Tried:\n  ", datafile_primary, "\n  ", datafile_fallback, "\n")
}
cat("Reading training data from: ", datafile, "\n", sep = "")
data_to_emulate <- scan(datafile)

## -------------------- Read parameter design (unchanged slicing) --------------------
if (!file.exists(DESIGN_FILE)) stop("Design file not found: ", DESIGN_FILE)
design_values_original  <- as.matrix(read.table(DESIGN_FILE))
design_values_no_header <- matrix(design_values_original, ncol = ncol(design_values_original))

# Remove scav_diam (column 43)
design_values_strings <- cbind(
  design_values_no_header[2:222, 1:42],
  design_values_no_header[2:222, 44:55]
)
design_values <- apply(design_values_strings, c(1, 2), as.numeric)

# Remove carbon sources from design
design_values_strings_w_o_carb <- rbind(
  design_values_no_header[2:214, c(1:3, 21:42, 44:55)],
  design_values_no_header[216:222, c(1:3, 21:42, 44:55)]
)
design_values_w_o_carb <- apply(design_values_strings_w_o_carb, c(1, 2), as.numeric)

if (nrow(design_values_w_o_carb) != length(data_to_emulate)) {
  stop("Design/response length mismatch: design=",
       nrow(design_values_w_o_carb), " vs resp=", length(data_to_emulate))
}

## -------------------- Load constrained sample (multi-million preferred; auto-detect) --------------------
sample_candidates <- c(
  file.path(SAMPLE_DIR, "constrained_multi_million_sample.RData"),
  file.path(SAMPLE_DIR, "constrained_multi_million_sample.rds"),
  file.path(SAMPLE_DIR, "constrained_near_million_sample.RData"),
  file.path(SAMPLE_DIR, "constrained_near_million_sample.rds"),
  file.path(SAMPLE_DIR, "constrained_sample.RData"),
  file.path(SAMPLE_DIR, "constrained_sample.rds")
)
sample_path <- sample_candidates[file.exists(sample_candidates)][1]
if (is.na(sample_path)) stop("No constrained sample file found in ", SAMPLE_DIR)
cat("Constrained sample file: ", sample_path, "\n", sep = "")

load_constrained <- function(path) {
  if (grepl("\\.rds$", path, ignore.case = TRUE)) return(readRDS(path))
  before <- ls(); load(path); after <- setdiff(ls(), before)
  prefer <- c("multi_million_sample_constrained", "near_million_sample_constrained", "sample_constrained")
  for (nm in prefer) if (nm %in% after) return(get(nm))
  cand <- grep("constrained", after, ignore.case = TRUE, value = TRUE)
  if (length(cand) >= 1) return(get(cand[1]))
  if (length(after) == 1) return(get(after[1]))
  stop("Could not identify constrained sample object; objects: ", paste(after, collapse = ", "))
}
sample_values_original <- load_constrained(sample_path)
if (is.data.frame(sample_values_original)) sample_values_original <- as.matrix(sample_values_original)
if (!is.matrix(sample_values_original)) stop("Loaded constrained sample is not a matrix/data.frame")

nsample <- nrow(sample_values_original); nparam <- ncol(sample_values_original)
cat(sprintf("Constrained sample dims: %d rows × %d cols\n", nsample, nparam))
if (nparam < 55) stop("Constrained sample must have ≥ 55 columns; got ", nparam)

reduce_n <- if (reduce_1M == 0) nsample else min(reduce_size, nsample)
cat(sprintf("Using %d rows for emulation (reduce_size=%d)\n", reduce_n, reduce_size))

# Original slices (kept identical)
sample_values <- cbind(
  sample_values_original[1:reduce_n, 1:42],
  sample_values_original[1:reduce_n, 44:55]
)
sample_values_w_o_carb <- cbind(
  sample_values_original[1:reduce_n, 1:3],
  sample_values_original[1:reduce_n, 21:42],
  sample_values_original[1:reduce_n, 44:55]
)

## -------------------- Train emulator (quiet) --------------------
train_t <- system.time({
  m_w_o_carb <- km(
    ~., design = data.frame(design_values_w_o_carb),
    response = data_to_emulate,
    covtype  = "matern5_2",
    control  = list(maxit = 500, trace = FALSE)
  )
})
cat(sprintf("Training time: %.3f s (elapsed)\n", train_t["elapsed"]))

## -------------------- Prediction via JJ code (larger chunks) --------------------
if (!file.exists(JJCODE_FILE)) stop("JJCode file not found: ", JJCODE_FILE)
source(JJCODE_FILE)

pred_t <- system.time({
  p_w_o_carb <- JJCode_PredictFromEm_UsingLargeSample(
    EmModIn             = m_w_o_carb,
    LargeSampInputCombs = sample_values_w_o_carb,
    nPredBreakVal       = 5000,  # foe faster increase this if memory allow; adjust if memory-constrained
    PredMean            = TRUE,
    PredSD              = TRUE,
    Pred95CIs           = FALSE
  )
})
if (is.null(p_w_o_carb$mean) || is.null(p_w_o_carb$sd)) stop("Predictor returned NULL mean/sd.")
cat(sprintf("Prediction time: %.3f s (elapsed)\n", pred_t["elapsed"]))

## -------------------- Write outputs (optimised folder) --------------------
base_dir <- file.path(OUTPUT_ROOT, paste0("lat", ilat))
dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)

mean_file <- file.path(
  base_dir,
  sprintf("emulated_mean_values_H2SO4_%s_ilat_%s_ilon_%s_%d_w_o_carb.dat",
          month, ilat, ilon, length(p_w_o_carb$mean))
)
sd_file <- file.path(
  base_dir,
  sprintf("emulated_sd_values_H2SO4_%s_ilat_%s_ilon_%s_%d_w_o_carb.dat",
          month, ilat, ilon, length(p_w_o_carb$sd))
)

readr::write_lines(p_w_o_carb$mean, mean_file)
readr::write_lines(p_w_o_carb$sd,   sd_file)
cat("✅ Wrote:\n  ", mean_file, "\n  ", sd_file, "\n", sep = "")

## -------------------- Timing log --------------------
log_file <- file.path(base_dir, sprintf("timing_log_%s_ilat_%s_ilon_%s.txt", month, ilat, ilon))
readr::write_lines(c(
  sprintf("ilat=%s  ilon=%s  month=%s", ilat, ilon, month),
  sprintf("train_elapsed=%.3f  pred_elapsed=%.3f  total=%.3f",
          train_t["elapsed"], pred_t["elapsed"], (train_t["elapsed"] + pred_t["elapsed"])),
  sprintf("used_rows=%d  nparam=%d", reduce_n, nparam)
), log_file)
cat("📝 Timing log: ", log_file, "\n", sep = "")
