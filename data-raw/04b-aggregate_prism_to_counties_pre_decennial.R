## Aggregate downloaded PRISM daily precipitation rasters to county-day summaries
## using one fixed county-boundary vintage. This is for comparing against the
## decennial-boundary PRISM workflow while keeping the current closest_dist.

required_pkgs <- c("dplyr", "readr", "sf", "terra", "exactextractr", "tigris",
                   "stringr", "tidyr", "lubridate")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace,
                                      quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0) {
  stop(
    "Install required packages first: ",
    paste(missing_pkgs, collapse = ", ")
  )
}

library(dplyr)
library(lubridate)
library(readr)
library(sf)
library(tidyr)
library(tigris)

prism_zip_dir <- "data-raw/cache/prism/ppt"
prism_extract_dir <- "data-raw/cache/prism/extracted"
output_file <- "data-raw/prism_precip_export_pre_decennial_current_closest_dist.txt"

dir.create(prism_extract_dir, recursive = TRUE, showWarnings = FALSE)

zip_files <- list.files(prism_zip_dir, pattern = "[.]zip$", full.names = TRUE)
if (length(zip_files) == 0) {
  stop("No PRISM zip files found in ", prism_zip_dir, ".")
}

zip_info <- tibble(
  zip_file = zip_files,
  year_month_day = as.integer(stringr::str_extract(basename(zip_files), "[0-9]{8}"))
) %>%
  filter(!is.na(year_month_day)) %>%
  arrange(year_month_day)

load("data/closest_dist.rda")

needed_county_days <- closest_dist %>%
  mutate(
    fips = sprintf("%05d", as.integer(fips)),
    closest_date = lubridate::ymd(closest_date),
    day_0 = closest_date,
    day_b1 = day_0 - days(1),
    day_b2 = day_0 - days(2),
    day_b3 = day_0 - days(3),
    day_b4 = day_0 - days(4),
    day_b5 = day_0 - days(5),
    day_a1 = day_0 + days(1),
    day_a2 = day_0 + days(2),
    day_a3 = day_0 + days(3)
  ) %>%
  select(
    fips, day_b5, day_b4, day_b3, day_b2, day_b1,
    day_0, day_a1, day_a2, day_a3
  ) %>%
  pivot_longer(cols = day_b5:day_a3, values_to = "day") %>%
  transmute(
    county = fips,
    year_month_day = as.integer(format(day, "%Y%m%d"))
  ) %>%
  distinct()

zip_info <- zip_info %>%
  semi_join(distinct(needed_county_days, year_month_day), by = "year_month_day")

if (file.exists(output_file)) {
  existing <- readr::read_csv(output_file, show_col_types = FALSE)

  if ("boundary_year" %in% names(existing)) {
    stop(
      output_file,
      " has a boundary_year column, but this fixed-boundary script expects ",
      "the old export schema. Move or delete it before rerunning."
    )
  }

  existing <- existing %>%
    mutate(county = sprintf("%05d", as.integer(county))) %>%
    distinct(county, year_month_day)
  needed_county_days <- needed_county_days %>%
    anti_join(existing, by = c("county", "year_month_day"))
  zip_info <- zip_info %>%
    semi_join(distinct(needed_county_days, year_month_day),
              by = "year_month_day")
}

if (nrow(zip_info) == 0) {
  message("All available PRISM zip files already aggregated.")
  quit(save = "no")
}

options(tigris_use_cache = TRUE)
needed_fips <- sort(unique(needed_county_days$county))
counties <- tigris::counties(cb = TRUE, year = 2020, class = "sf") %>%
  transmute(county = GEOID, geometry = geometry) %>%
  filter(county %in% needed_fips)

aggregate_one_day <- function(zip_file, this_day) {
  extract_subdir <- file.path(prism_extract_dir, tools::file_path_sans_ext(basename(zip_file)))
  dir.create(extract_subdir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(extract_subdir, recursive = TRUE, force = TRUE), add = TRUE)

  utils::unzip(zip_file, exdir = extract_subdir)

  raster_files <- c(
    list.files(extract_subdir, pattern = "[.]tif$", full.names = TRUE),
    list.files(extract_subdir, pattern = "[.]bil$", full.names = TRUE)
  )
  raster_files <- unique(raster_files)

  if (length(raster_files) != 1) {
    stop(
      "Expected exactly one raster (.tif or .bil) in ",
      zip_file, "; found ", length(raster_files), "."
    )
  }

  raster <- terra::rast(raster_files)
  day_counties <- counties %>%
    semi_join(filter(needed_county_days, year_month_day == this_day),
              by = "county")
  counties_proj <- sf::st_transform(day_counties, crs = terra::crs(raster))

  stats <- exactextractr::exact_extract(raster, counties_proj, c("mean", "max"))

  tibble(
    county = counties_proj$county,
    year_month_day = this_day,
    precip = stats$mean,
    precip_max = stats$max
  ) %>%
    filter(!is.na(precip) & !is.na(precip_max))
}

for (i in seq_len(nrow(zip_info))) {
  this_zip <- zip_info$zip_file[i]
  this_day <- zip_info$year_month_day[i]
  message("Aggregating ", basename(this_zip))

  day_df <- aggregate_one_day(this_zip, this_day)

  if (!file.exists(output_file)) {
    readr::write_csv(day_df, output_file)
  } else {
    readr::write_csv(day_df, output_file, append = TRUE)
  }
}

message("Wrote fixed-boundary PRISM county-day summaries to ", output_file)
