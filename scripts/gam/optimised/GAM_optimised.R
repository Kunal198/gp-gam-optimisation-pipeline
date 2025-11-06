#!/usr/bin/env Rscript

# ===== Quiet, required libs =====
suppressPackageStartupMessages({
  library(mgcv)
})

# ===== CLI args =====
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript GAM_alt_stream.R <ilat> <ilon> <month>")
}
ilat  <- args[1]      # e.g., "34.375"
ilon  <- args[2]      # e.g., "-10.3125"
month <- tolower(args[3])  # e.g., "jan"

# ===== Config =====
varname    <- "H2SO4"
pred_block <- 200000L   # larger blocks reduce predict() overhead; adjust to RAM
set.seed(1)

# ===== Paths relative to repo (like the Python baseline) =====
get_script_path <- function() {
  sp <- grep("^--file=", commandArgs(), value = TRUE)
  if (length(sp)) return(normalizePath(sub("^--file=", "", sp)))
  return(normalizePath(sys.frames()[[1]]$ofile))
}
script_path <- tryCatch(get_script_path(), error = function(e) normalizePath("."))
script_dir  <- dirname(script_path)
repo_root   <- normalizePath(file.path(script_dir, "..", "..", ".."))

# Directories that mirror baseline layout
gp_root  <- file.path(repo_root, "examples", "tiny_sample_outputs", "gp_emulation", "baseline")
gam_root <- file.path(repo_root, "examples", "tiny_sample_outputs", "gam_variance", "optimised")
lhc_path <- file.path(repo_root, "examples", "large_sample", "constrained_multi_million_sample_first_million.dat")

# ===== Formatting helpers =====
ilat_num <- as.numeric(ilat); ilon_num <- as.numeric(ilon)
ilat_fmt <- formatC(ilat_num, format = "f", digits = 3)
ilon_fmt <- formatC(ilon_num, format = "f", digits = 4)

# ===== Find GP emulation file (like Python find_gp_file) =====
lat_dir <- file.path(gp_root, sprintf("lat%s", ilat_fmt))
if (!dir.exists(lat_dir)) stop(sprintf("GP lat directory not found: %s", lat_dir))
esc <- function(x) gsub("\\.", "\\\\.", x)
pat <- sprintf("^emulated_mean_values_%s_%s_ilat_%s_ilon_%s_([0-9]+)_w_o_carb\\.dat$",
               varname, month, esc(ilat_fmt), esc(ilon_fmt))
cand <- list.files(lat_dir, pattern = pat, full.names = TRUE)
if (!length(cand)) stop(sprintf("No GP file matched at %s with pattern %s", lat_dir, pat))
if (length(cand) > 1) message("Multiple GP files matched; taking the first:\n", paste0(" - ", basename(cand), collapse = "\n"))
data_file <- cand[[1]]
message(sprintf("[GAM-OPT] Using GP mean: %s", data_file))

# Extract N from filename, fallback to length(y)
N_from_name <- {
  m <- regexec(pat, basename(data_file))
  regmatches(basename(data_file), m)[[1]][2]
}
N_from_name <- suppressWarnings(as.integer(N_from_name))

# ===== Read emulated response =====
y <- scan(data_file, quiet = TRUE)
y <- as.numeric(y)
if (is.matrix(y)) y <- y[, 1]
if (any(!is.finite(y))) {
  y <- y[is.finite(y)]
  warning("Non-finite values detected in y; removed.")
}
N <- length(y)
if (!is.na(N_from_name) && N_from_name != N) {
  message(sprintf("Note: filename N=%d but file length(y)=%d; using length(y).", N_from_name, N))
}

# ===== Load raw LHC and take FIRST N rows (Case B) =====
if (!file.exists(lhc_path)) stop(sprintf("Missing LHC sample file: %s", lhc_path))
LHC_norm <- as.matrix(read.table(lhc_path))
if (ncol(LHC_norm) < 55) stop(sprintf("LHC must have >=55 columns; got %d", ncol(LHC_norm)))
if (nrow(LHC_norm) < N)  stop(sprintf("LHC has only %d rows; need %d", nrow(LHC_norm), N))

# ===== 37-parameter subset (unchanged) =====
par_index <- c(1,2,3,21:42,44:55)
parameter_names_55 <- c(
  "bl_nuc","ait_width","cloud_ph","carb_ff_ems_eur","carb_ff_ems_nam",
  "carb_ff_ems_chi","carb_ff_ems_asi","carb_ff_ems_mar","carb_ff_ems_r",
  "carb_bb_ems_sam","carb_bb_ems_naf","carb_bb_ems_saf","carb_bb_ems_bnh",
  "carb_bb_ems_rnh","carb_bb_ems_rsh","carb_res_ems_chi","carb_res_ems_asi",
  "carb_res_ems_afr","carb_res_ems_lat","carb_res_ems_r","carb_ff_diam",
  "carb_bb_diam","carb_res_diam","prim_so4_diam","sea_spray","anth_so2_chi",
  "ant	h_so2_asi","anth_so2_eur","anth_so2_nam","anth_so2_r","volc_so2",
  "bvoc_soa","dms","prim_moc","dry_dep_ait","dry_dep_acc","dry_dep_so2",
  "kappa_oc","sig_w","rain_frac","cloud_ice_thresh","conv_plume_scav",
  "scav_diam","bc_ri","oxidants_oh","oxidants_o3","bparam","two_d_fsd_factor",
  "c_r_correl","autoconv_exp_lwp","autoconv_exp_nd","dbsdtbs_turb_0",
  "ai","m_ci","a_ent_1_rp"
)
# fix any accidental tab in the line above:
parameter_names_55[which(parameter_names_55 == "ant\th_so2_asi")] <- "anth_so2_asi"

parameter_subset <- parameter_names_55[par_index]

X_full <- LHC_norm[seq_len(N), , drop = FALSE]     # FIRST N rows (Case B)
X      <- X_full[, par_index, drop = FALSE]
colnames(X) <- parameter_subset

# ===== Sanity clean (finite rows) =====
keep <- is.finite(y)
for (j in seq_len(ncol(X))) keep <- keep & is.finite(X[, j])
if (!any(keep)) stop("No finite rows remain after cleaning X/y.")
X <- X[keep, , drop = FALSE]
y <- y[keep]
N_used <- length(y)

# ===== Fit GAM with bam (unchanged spec, multi-thread if available) =====
formula_str <- paste("y ~", paste(sprintf("s(%s)", parameter_subset), collapse = " + "))
df <- data.frame(y = y, X, check.names = FALSE)

gam_model <- bam(
  formula  = as.formula(formula_str),
  data     = df,
  method   = "fREML",
  discrete = TRUE,
  nthreads = parallel::detectCores()   # ignored if mgcv not built with OpenMP
)

# ===== FAST path (vectorized, output-identical) =====
# type="terms" returns per-smooth contributions f_i(X_i) up to a constant;
# variance and sign(cov) are invariant to adding a constant, so outputs match.
terms_mat <- predict(
  gam_model,
  newdata    = df,
  type       = "terms",
  block.size = pred_block,
  gc.level   = 0
)
# terms_mat: N_used x length(parameter_subset)

# Variance importance per parameter (identical to median-hold method)
var_array <- apply(terms_mat, 2, var)

# Gradient sign via covariance with X_i (identical sign as before)
grad_sign_array <- numeric(ncol(terms_mat))
for (i in seq_len(ncol(terms_mat))) {
  xi <- X[, i]
  ti <- terms_mat[, i]
  grad_sign_array[i] <- if (var(xi) <= 1e-15) 0 else sign(cov(xi, ti))
}

# ===== Save like baseline, but under "optimised/" =====
out_dir <- file.path(gam_root, sprintf("lat%s", ilat_fmt))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

y_len <- length(scan(data_file, quiet = TRUE))
N_out <- if (!is.na(N_from_name) && N_from_name == y_len) N_from_name else N_used

var_file  <- file.path(out_dir, sprintf("GAM_variances_%s_%s_%d_ilat_%s_ilon_%s.dat", varname, month, N_out, ilat_fmt, ilon_fmt))
grad_file <- file.path(out_dir, sprintf("GAM_gradient_signs_%s_%s_%d_ilat_%s_ilon_%s.dat", varname, month, N_out, ilat_fmt, ilon_fmt))

write.table(var_array,       file = var_file,  row.names = FALSE, col.names = FALSE)
write.table(grad_sign_array, file = grad_file, row.names = FALSE, col.names = FALSE)

cat(sprintf("✅ GAM optimised complete (fast terms path). rows_used=%d\n→ %s\n→ %s\n",
            N_used, var_file, grad_file))
