#!/usr/bin/env Rscript
req <- c("mgcv","DiceKriging","lhs","sensitivity","trapezoid","readr","truncnorm")
to_install <- setdiff(req, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install, repos="https://cloud.r-project.org")
sessionInfo()
