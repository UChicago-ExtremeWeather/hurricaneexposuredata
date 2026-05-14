## Aggregate downloaded PRISM daily precipitation rasters to county-day summaries.
##
## This script:
## 1. Finds PRISM daily zip files under data-raw/cache/prism/ppt
## 2. Extracts one zip at a time
## 3. Computes county mean precipitation and county max precipitation
## 4. Appends results to a flat text file suitable for script 04
## 5. Deletes extracted files after each day to save space

required_pkgs <- c("dplyr", "readr", "sf", "terra", "exactextractr", "tigris", "stringr")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace,
                                      quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0) {
  stop(
    "Install required packages first: ",
    paste(missing_pkgs, collapse = ", ")
  )
}

library(dplyr)
library(readr)
library(sf)
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

if (file.exists(output_file)) {
  existing <- readr::read_csv(output_file, show_col_types = FALSE) %>%
    distinct(year_month_day)
  zip_info <- zip_info %>%
    filter(!(year_month_day %in% existing$year_month_day))
}

if (nrow(zip_info) == 0) {
  message("All available PRISM zip files already aggregated.")
  quit(save = "no")
}

load("data/closest_dist.rda")
needed_fips <- sort(unique(closest_dist$fips))

options(tigris_use_cache = TRUE)
counties <- tigris::counties(cb = TRUE, year = 2023, class = "sf") %>%
  transmute(county = GEOID, geometry = geometry) %>%
  filter(county %in% needed_fips)

aggregate_one_day <- function(zip_file, year_month_day) {
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
  counties_proj <- sf::st_transform(counties, crs = terra::crs(raster))

  stats <- exactextractr::exact_extract(raster, counties_proj, c("mean", "max"))

  out <- tibble(
    county = counties_proj$county,
    year_month_day = year_month_day,
    precip = stats$mean,
    precip_max = stats$max
  ) %>%
    filter(!is.na(precip) & !is.na(precip_max))
  out
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
