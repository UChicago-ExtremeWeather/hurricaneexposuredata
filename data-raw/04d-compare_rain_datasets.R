## Compare the legacy `rain` dataset to the PRISM-based `rain_prism` dataset.
##
## This script produces:
## - a concise console summary
## - a one-row overview CSV
## - metric tables for `precip` and `precip_max`
## - storm/year/county summaries of absolute differences
## - example rows with the largest discrepancies

library(dplyr)
library(readr)
library(tidyr)

output_dir <- "data-raw/rain_comparison"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

print_plain <- function(x, digits = 3) {
  if (is.data.frame(x)) {
    num_cols <- vapply(x, is.numeric, logical(1))
    x[num_cols] <- lapply(x[num_cols], round, digits = digits)
    print.data.frame(x, row.names = FALSE, right = FALSE)
  } else {
    print(x)
  }
}

load_dataset_fallback <- function(object_name, local_path) {
  if (file.exists(local_path)) {
    env <- new.env()
    load(local_path, envir = env)
    return(get(object_name, envir = env))
  }

  data(list = object_name, package = "hurricaneexposuredata", envir = environment())
  get(object_name, envir = environment())
}

metric_summary <- function(df, legacy_col, prism_col, label) {
  legacy <- df[[legacy_col]]
  prism <- df[[prism_col]]
  diff <- prism - legacy
  abs_diff <- abs(diff)

  tibble(
    measure = label,
    correlation = cor(legacy, prism, use = "complete.obs"),
    mean_diff = mean(diff, na.rm = TRUE),
    mean_abs_diff = mean(abs_diff, na.rm = TRUE),
    median_abs_diff = median(abs_diff, na.rm = TRUE),
    rmsd = sqrt(mean(diff ^ 2, na.rm = TRUE)),
    p90_abs_diff = unname(quantile(abs_diff, probs = 0.90, na.rm = TRUE)),
    p99_abs_diff = unname(quantile(abs_diff, probs = 0.99, na.rm = TRUE)),
    pct_exact_match = mean(abs_diff == 0, na.rm = TRUE),
    pct_within_1mm = mean(abs_diff <= 1, na.rm = TRUE),
    pct_within_5mm = mean(abs_diff <= 5, na.rm = TRUE),
    pct_within_10mm = mean(abs_diff <= 10, na.rm = TRUE),
    pct_within_25mm = mean(abs_diff <= 25, na.rm = TRUE)
  )
}

diff_quantiles <- function(df, diff_col, label) {
  probs <- c(0, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1)
  out <- quantile(df[[diff_col]], probs = probs, na.rm = TRUE)
  tibble(
    measure = label,
    quantile = names(out),
    value = as.numeric(out)
  )
}

rain <- load_dataset_fallback("rain", "data/rain.rda")
rain_prism <- load_dataset_fallback("rain_prism", "data/rain_prism.rda")

legacy_years <- as.integer(sub(".*-", "", rain$storm_id))
prism_years <- as.integer(sub(".*-", "", rain_prism$storm_id))

key_cols <- c("fips", "storm_id", "usa_atcf_id", "lag")

both <- inner_join(
  rain,
  rain_prism,
  by = key_cols,
  suffix = c("_legacy", "_prism")
) %>%
  mutate(
    year = as.integer(sub(".*-", "", storm_id)),
    precip_diff = precip_prism - precip_legacy,
    precip_max_diff = precip_max_prism - precip_max_legacy,
    precip_abs_diff = abs(precip_diff),
    precip_max_abs_diff = abs(precip_max_diff)
  )

if (nrow(both) == 0) {
  stop("No overlapping rows between `rain` and `rain_prism`.")
}

overview <- tibble(
  legacy_rows = nrow(rain),
  rain_prism_rows = nrow(rain_prism),
  overlap_rows = nrow(both),
  legacy_start_year = min(legacy_years),
  legacy_end_year = max(legacy_years),
  prism_start_year = min(prism_years),
  prism_end_year = max(prism_years),
  legacy_storms = length(unique(rain$storm_id)),
  prism_storms = length(unique(rain_prism$storm_id)),
  shared_storms = length(intersect(unique(rain$storm_id), unique(rain_prism$storm_id)))
)

metric_table <- bind_rows(
  metric_summary(both, "precip_legacy", "precip_prism", "precip"),
  metric_summary(both, "precip_max_legacy", "precip_max_prism", "precip_max")
)

quantile_table <- bind_rows(
  diff_quantiles(both, "precip_diff", "precip_diff"),
  diff_quantiles(both, "precip_max_diff", "precip_max_diff")
)

storm_summary <- both %>%
  group_by(storm_id, year) %>%
  summarise(
    n = n(),
    mean_precip_abs_diff = mean(precip_abs_diff, na.rm = TRUE),
    mean_precip_max_abs_diff = mean(precip_max_abs_diff, na.rm = TRUE),
    max_precip_abs_diff = max(precip_abs_diff, na.rm = TRUE),
    max_precip_max_abs_diff = max(precip_max_abs_diff, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_precip_max_abs_diff), desc(max_precip_max_abs_diff))

year_summary <- both %>%
  group_by(year) %>%
  summarise(
    n = n(),
    mean_precip_abs_diff = mean(precip_abs_diff, na.rm = TRUE),
    mean_precip_max_abs_diff = mean(precip_max_abs_diff, na.rm = TRUE),
    correlation_precip = cor(precip_legacy, precip_prism, use = "complete.obs"),
    correlation_precip_max = cor(precip_max_legacy, precip_max_prism, use = "complete.obs"),
    .groups = "drop"
  ) %>%
  arrange(year)

county_summary <- both %>%
  group_by(fips) %>%
  summarise(
    n = n(),
    mean_precip_abs_diff = mean(precip_abs_diff, na.rm = TRUE),
    mean_precip_max_abs_diff = mean(precip_max_abs_diff, na.rm = TRUE),
    max_precip_abs_diff = max(precip_abs_diff, na.rm = TRUE),
    max_precip_max_abs_diff = max(precip_max_abs_diff, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_precip_max_abs_diff), desc(max_precip_max_abs_diff))

largest_examples <- both %>%
  arrange(desc(precip_max_abs_diff), desc(precip_abs_diff)) %>%
  select(
    fips, storm_id, year, lag,
    precip_legacy, precip_prism, precip_diff, precip_abs_diff,
    precip_max_legacy, precip_max_prism, precip_max_diff, precip_max_abs_diff
  ) %>%
  slice_head(n = 100)

write_csv(overview, file.path(output_dir, "overview.csv"))
write_csv(metric_table, file.path(output_dir, "metric_table.csv"))
write_csv(quantile_table, file.path(output_dir, "difference_quantiles.csv"))
write_csv(storm_summary, file.path(output_dir, "storm_summary.csv"))
write_csv(year_summary, file.path(output_dir, "year_summary.csv"))
write_csv(county_summary, file.path(output_dir, "county_summary.csv"))
write_csv(largest_examples, file.path(output_dir, "largest_examples.csv"))

cat("Rain comparison outputs written to ", output_dir, "\n\n", sep = "")

cat("Overview\n")
print_plain(overview)

cat("\nMetric table\n")
print_plain(metric_table)

cat("\nDifference quantiles\n")
print_plain(quantile_table)

cat("\nTop 10 storms by mean precip_max absolute difference\n")
print_plain(slice_head(storm_summary, n = 10))

cat("\nTop 10 years by mean precip_max absolute difference\n")
print_plain(arrange(year_summary, desc(mean_precip_max_abs_diff)) %>% slice_head(n = 10))

cat("\nTop 10 counties by mean precip_max absolute difference\n")
print_plain(slice_head(county_summary, n = 10))

cat("\nTop 10 example rows by precip_max absolute difference\n")
print_plain(slice_head(largest_examples, n = 10))
