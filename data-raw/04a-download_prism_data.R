## Download PRISM daily precipitation rasters for the county-day windows
## needed to rebuild the rain dataset.
##
## This script:
## 1. Loads `closest_dist` from the installed hurricaneexposuredata package
## 2. Computes the unique dates needed for lags -5 through +3 days
## 3. Downloads missing PRISM daily precipitation zip files for those dates
## 4. Saves them under data-raw/cache/prism/ppt

library(dplyr)
library(lubridate)
library(tidyr)

data("closest_dist", package = "hurricaneexposuredata")

prism_dir <- "data-raw/cache/prism/ppt"
dir.create(prism_dir, recursive = TRUE, showWarnings = FALSE)

prism_variable <- "ppt"
prism_region <- "us"
prism_resolution_dir <- "4km"
prism_resolution_code <- "25m"
prism_base_url <- "https://data.prism.oregonstate.edu/time_series"

needed_dates <- closest_dist %>%
  transmute(
    closest_date = ymd(closest_date),
    day_b5 = closest_date - days(5),
    day_b4 = closest_date - days(4),
    day_b3 = closest_date - days(3),
    day_b2 = closest_date - days(2),
    day_b1 = closest_date - days(1),
    day_0 = closest_date,
    day_a1 = closest_date + days(1),
    day_a2 = closest_date + days(2),
    day_a3 = closest_date + days(3)
  ) %>%
  select(-closest_date) %>%
  pivot_longer(everything(), values_to = "date") %>%
  distinct(date) %>%
  filter(!is.na(date)) %>%
  arrange(date) %>%
  pull(date)

find_prism_filename <- function(date, variable = prism_variable) {
  year_string <- format(date, "%Y")
  ymd_string <- format(date, "%Y%m%d")
  year_url <- paste0(
    prism_base_url, "/", prism_region, "/an/", prism_resolution_dir, "/",
    variable, "/daily/", year_string, "/"
  )

  index_lines <- tryCatch(
    readLines(year_url, warn = FALSE),
    error = function(e) NULL
  )
  if (is.null(index_lines)) {
    return(NA_character_)
  }

  matches <- stringr::str_extract(
    index_lines,
    paste0(
      "prism_", variable, "_", prism_region, "_", prism_resolution_code, "_",
      ymd_string, "[.]zip"
    )
  )
  matches <- unique(matches[!is.na(matches)])

  if (length(matches) == 0) {
    return(NA_character_)
  }
  matches[1]
}

build_prism_url <- function(date, variable = prism_variable) {
  file_name <- find_prism_filename(date, variable)
  paste0(
    prism_base_url, "/", prism_region, "/an/", prism_resolution_dir, "/",
    variable, "/daily/", year(date), "/", file_name
  )
}

download_prism_date <- function(date, overwrite = FALSE) {
  file_name <- find_prism_filename(date)
  if (is.na(file_name)) {
    message("Skipping unavailable PRISM date: ", format(date, "%Y-%m-%d"))
    return(invisible(NA_character_))
  }

  dest_file <- file.path(prism_dir, file_name)

  if (file.exists(dest_file) && !overwrite) {
    message("Already downloaded: ", file_name)
    return(invisible(dest_file))
  }

  url <- build_prism_url(date)
  message("Downloading ", file_name)
  utils::download.file(url = url, destfile = dest_file, mode = "wb", quiet = FALSE)

  invisible(dest_file)
}

message("Need PRISM files for ", length(needed_dates), " unique dates.")
message("Date range: ", min(needed_dates), " to ", max(needed_dates))

downloaded <- vapply(
  needed_dates,
  function(x) {
    tryCatch({
      result <- download_prism_date(x)
      !is.na(result)
    }, error = function(e) {
      message("Failed for ", format(x, "%Y-%m-%d"), ": ", conditionMessage(e))
      FALSE
    })
  },
  logical(1)
)
#
message("Downloaded or confirmed present: ", sum(downloaded), " / ", length(downloaded))
