## Aggregate downloaded PRISM daily precipitation rasters to county-day summaries
## using county assignment rules that more closely mimic CDC WONDER's NLDAS
## precipitation methodology.
##
## Compared with 04b-aggregate_prism_to_counties.R, this script changes the
## county aggregation logic:
## 1. Raster cells are assigned to counties by raster-cell centroid.
## 2. County mean / max are then computed across the assigned cells.
## 3. If a county contains no raster-cell centroids, the single raster cell that
##    overlaps the greatest county area is assigned to that county.
##
## This is still not an exact reproduction of WONDER because it uses PRISM
## precipitation and current Census county geometries, but it is closer to the
## documented county-assignment methodology than area-weighted polygon overlap.

required_pkgs <- c("dplyr", "readr", "sf", "terra", "tigris", "stringr")
missing_pkgs <- required_pkgs[!vapply(
  required_pkgs,
  requireNamespace,
  quietly = TRUE,
  FUN.VALUE = logical(1)
)]
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
output_file <- "data-raw/prism_precip_export_wonderlike.txt"

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

find_fallback_value <- function(county_sf, raster_day, value_col) {
  county_vect <- terra::vect(county_sf)
  county_crop <- terra::crop(raster_day, county_vect, snap = "out")

  if (is.null(county_crop) || all(is.na(terra::values(county_crop, mat = FALSE)))) {
    return(NA_real_)
  }

  cell_polys <- terra::as.polygons(county_crop, values = TRUE, na.rm = TRUE)
  if (is.null(cell_polys) || nrow(cell_polys) == 0) {
    return(NA_real_)
  }

  cell_polys_sf <- sf::st_as_sf(cell_polys)
  overlaps <- suppressWarnings(sf::st_intersection(cell_polys_sf, county_sf))
  if (nrow(overlaps) == 0) {
    return(NA_real_)
  }

  overlaps$overlap_area <- as.numeric(sf::st_area(overlaps))
  overlaps <- overlaps[order(overlaps$overlap_area, decreasing = TRUE), , drop = FALSE]
  overlaps[[value_col]][1]
}

aggregate_one_day <- function(zip_file, year_month_day) {
  extract_subdir <- file.path(
    prism_extract_dir,
    tools::file_path_sans_ext(basename(zip_file))
  )
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

  raster_day <- terra::rast(raster_files)
  counties_proj <- sf::st_transform(counties, crs = terra::crs(raster_day))
  raster_crop <- terra::crop(raster_day, terra::vect(counties_proj), snap = "out")

  points_sf <- terra::as.points(raster_crop, values = TRUE, na.rm = TRUE) %>%
    sf::st_as_sf()

  value_cols <- setdiff(names(points_sf), attr(points_sf, "sf_column"))
  if (length(value_cols) != 1) {
    stop("Expected exactly one raster value column, found ", length(value_cols), ".")
  }
  value_col <- value_cols[1]

  assigned <- sf::st_join(
    points_sf,
    counties_proj %>% select(county),
    join = sf::st_within,
    left = FALSE
  ) %>%
    sf::st_drop_geometry() %>%
    group_by(county) %>%
    summarize(
      precip = mean(.data[[value_col]], na.rm = TRUE),
      precip_max = max(.data[[value_col]], na.rm = TRUE),
      .groups = "drop"
    )

  missing_counties <- setdiff(counties_proj$county, assigned$county)
  if (length(missing_counties) > 0) {
    fallback <- lapply(missing_counties, function(this_county) {
      county_sf <- counties_proj[counties_proj$county == this_county, , drop = FALSE]
      fallback_value <- find_fallback_value(county_sf, raster_crop, value_col)
      tibble(
        county = this_county,
        precip = fallback_value,
        precip_max = fallback_value
      )
    }) %>%
      bind_rows()

    assigned <- bind_rows(assigned, fallback)
  }

  assigned %>%
    mutate(year_month_day = year_month_day, .before = precip) %>%
    filter(!is.na(precip) & !is.na(precip_max)) %>%
    arrange(county)
}

for (i in seq_len(nrow(zip_info))) {
  this_zip <- zip_info$zip_file[i]
  this_day <- zip_info$year_month_day[i]
  message("Aggregating WONDER-like county summaries for ", basename(this_zip))

  day_df <- aggregate_one_day(this_zip, this_day)

  if (!file.exists(output_file)) {
    readr::write_csv(day_df, output_file)
  } else {
    readr::write_csv(day_df, output_file, append = TRUE)
  }
}

message("Wrote WONDER-like PRISM county-day summaries to ", output_file)
