## Aggregate downloaded PRISM daily precipitation rasters to county-day summaries.
##
## This script:
## 1. Finds PRISM daily zip files under data-raw/cache/prism/ppt
## 2. Extracts one zip at a time
## 3. Computes county mean precipitation and county max precipitation using
##    the county boundary vintage matched to each storm decade
## 4. Appends results to a flat text file suitable for script 04
## 5. Deletes extracted files after each day to save space

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
output_file <- "data-raw/prism_precip_export.txt"

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

assign_boundary_year <- function(storm_year) {
  dplyr::case_when(
    storm_year <= 2009 ~ 2000,
    storm_year <= 2019 ~ 2010,
    TRUE ~ 2020
  )
}

needed_county_days <- closest_dist %>%
  mutate(
    fips = sprintf("%05d", as.integer(fips)),
    storm_year = as.integer(stringr::str_extract(storm_id, "[0-9]{4}$")),
    boundary_year = assign_boundary_year(storm_year),
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
    fips, boundary_year, day_b5, day_b4, day_b3, day_b2, day_b1,
    day_0, day_a1, day_a2, day_a3
  ) %>%
  pivot_longer(cols = day_b5:day_a3, values_to = "day") %>%
  transmute(
    county = fips,
    boundary_year,
    year_month_day = as.integer(format(day, "%Y%m%d"))
  ) %>%
  distinct()

needed_dates <- needed_county_days %>%
  distinct(year_month_day)

zip_info <- zip_info %>%
  semi_join(needed_dates, by = "year_month_day")

if (file.exists(output_file)) {
  existing <- readr::read_csv(output_file, show_col_types = FALSE)

  if (!"boundary_year" %in% names(existing)) {
    stop(
      output_file,
      " was created before decennial county-boundary aggregation. ",
      "Move or delete it, then rerun this script to rebuild the export."
    )
  }

  existing <- existing %>%
    mutate(county = sprintf("%05d", as.integer(county))) %>%
    distinct(county, year_month_day, boundary_year)
  needed_county_days <- needed_county_days %>%
    anti_join(existing, by = c("county", "year_month_day", "boundary_year"))
  zip_info <- zip_info %>%
    semi_join(distinct(needed_county_days, year_month_day),
              by = "year_month_day")
}

if (nrow(zip_info) == 0) {
  message("All available PRISM zip files already aggregated.")
  quit(save = "no")
}

options(tigris_use_cache = TRUE)
county_geoid <- function(counties) {
  if ("GEOID" %in% names(counties)) {
    return(as.character(counties$GEOID))
  }
  if ("GEOID10" %in% names(counties)) {
    return(as.character(counties$GEOID10))
  }
  if (all(c("STATEFP", "COUNTYFP") %in% names(counties))) {
    return(paste0(
      sprintf("%02d", as.integer(counties$STATEFP)),
      sprintf("%03d", as.integer(counties$COUNTYFP))
    ))
  }
  if (all(c("STATEFP10", "COUNTYFP10") %in% names(counties))) {
    return(paste0(
      sprintf("%02d", as.integer(counties$STATEFP10)),
      sprintf("%03d", as.integer(counties$COUNTYFP10))
    ))
  }
  stop("Could not identify county FIPS columns in tigris output.")
}

counties_by_boundary_year <- lapply(
  sort(unique(needed_county_days$boundary_year)),
  function(this_year) {
    tigris::counties(cb = TRUE, year = this_year, class = "sf") %>%
      mutate(county = county_geoid(.)) %>%
      transmute(
        county = county,
        boundary_year = this_year,
        geometry = geometry
      ) %>%
      semi_join(
        filter(needed_county_days, boundary_year == this_year),
        by = c("county", "boundary_year")
      )
  }
)
names(counties_by_boundary_year) <- sort(unique(needed_county_days$boundary_year))

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
  boundary_years <- needed_county_days %>%
    filter(year_month_day == this_day) %>%
    distinct(boundary_year) %>%
    pull(boundary_year)

  lapply(boundary_years, function(this_boundary_year) {
    counties <- counties_by_boundary_year[[as.character(this_boundary_year)]] %>%
      semi_join(
        filter(needed_county_days,
               year_month_day == this_day,
               boundary_year == this_boundary_year),
        by = c("county", "boundary_year")
      )

    counties_proj <- sf::st_transform(counties, crs = terra::crs(raster))
    stats <- exactextractr::exact_extract(raster, counties_proj, c("mean", "max"))

    tibble(
      county = counties_proj$county,
      boundary_year = this_boundary_year,
      year_month_day = this_day,
      precip = stats$mean,
      precip_max = stats$max
    ) %>%
      filter(!is.na(precip) & !is.na(precip_max))
  }) %>%
    bind_rows()
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

message("Wrote PRISM county-day summaries to ", output_file)
