## Process county-day PRISM precipitation summaries into the storm-relative
## rain dataset format used by hurricaneexposuredata.
##
## This script leaves the original 04-process_precip_data.R untouched and
## instead reads the PRISM-derived county-day table created by
## 04b-aggregate_prism_to_counties.R.

data("closest_dist", package = "hurricaneexposuredata")
library(dplyr)
library(tidyr)
library(lubridate)
library(data.table)

prism_input_file <- "data-raw/prism_precip_export_wonderlike.txt"

check_dates <- dplyr::select(closest_dist, -storm_dist) %>%
  dplyr::mutate(closest_date = ymd(closest_date)) %>%
  dplyr::rename(day_0 = closest_date) %>%
  dplyr::mutate(
    fips = as.integer(fips),
    day_0 = day_0 + days(0),
    day_b1 = day_0 - days(1),
    day_b2 = day_0 - days(2),
    day_b3 = day_0 - days(3),
    day_b4 = day_0 - days(4),
    day_b5 = day_0 - days(5),
    day_a1 = day_0 + days(1),
    day_a2 = day_0 + days(2),
    day_a3 = day_0 + days(3)
  ) %>%
  dplyr::select(
    storm_id, usa_atcf_id, fips, day_b5, day_b4, day_b3, day_b2, day_b1,
    day_0, day_a1, day_a2, day_a3
  ) %>%
  tidyr::pivot_longer(cols = day_b5:day_a3, names_to = "lag", values_to = "day") %>%
  dplyr::mutate(day = as.numeric(format(day, "%Y%m%d")))

all_dates <- unique(check_dates$day)
all_fips <- unique(check_dates$fips)

rain_prism_wonder <- data.table::fread(
  prism_input_file,
  header = TRUE,
  select = c("county", "year_month_day", "precip", "precip_max")
) %>%
  dplyr::filter(
    county %in% all_fips,
    year_month_day %in% all_dates
  ) %>%
  dplyr::rename(fips = county, day = year_month_day) %>%
  dplyr::right_join(data.table(check_dates), by = c("fips" = "fips", "day" = "day")) %>%
  dplyr::filter(!is.na(precip) & !is.na(precip_max)) %>%
  dplyr::select(-day) %>%
  dplyr::arrange(usa_atcf_id, fips) %>%
  dplyr::select(fips, storm_id, usa_atcf_id, lag, precip, precip_max) %>%
  dplyr::mutate(
    fips = sprintf("%05d", fips),
    lag = gsub("day_", "", lag),
    lag = gsub("b", "-", lag),
    lag = gsub("a", "", lag),
    lag = as.numeric(lag)
  )

usethis::use_data(rain_prism_wonder, overwrite = TRUE)
