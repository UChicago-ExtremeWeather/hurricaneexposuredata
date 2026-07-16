## Be sure to re-build package after running 02 and 03 before running this script

library(dplyr)
library(lubridate)
library(stringr)
library(tidyr)

load("data/hurr_tracks.rda")
load("data/closest_dist.rda")

stormevents_base_url <- "https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/"
stormevents_cache_dir <- "data-raw/cache/stormevents"
dir.create(stormevents_cache_dir, recursive = TRUE, showWarnings = FALSE)

find_stormevents_file <- function(year, file_type = "details") {
  index <- readLines(stormevents_base_url, warn = FALSE)
  file_pattern <- paste0("StormEvents_", file_type, "-ftp_v1.0_d", year,
                         "_c[0-9]+\\.csv\\.gz")
  file_name <- str_extract(index, file_pattern)
  file_name <- file_name[!is.na(file_name)]

  if (length(file_name) == 0) {
    stop("No NOAA Storm Events ", file_type, " file found for ", year, ".")
  }

  sort(unique(file_name), decreasing = TRUE)[1]
}

read_stormevents_year <- function(year) {
  file_name <- find_stormevents_file(year = year, file_type = "details")
  local_file <- file.path(stormevents_cache_dir, file_name)

  if (!file.exists(local_file)) {
    download.file(
      url = paste0(stormevents_base_url, file_name),
      destfile = local_file,
      mode = "wb",
      quiet = FALSE
    )
  }

  utils::read.csv(gzfile(local_file), as.is = TRUE) %>%
    tibble::as_tibble() %>%
    stats::setNames(tolower(names(.)))
}

match_forecast_county <- function(storm_data_z) {
  utils::data(county.fips, package = "maps")
  county.fips <- county.fips %>%
    tidyr::separate("polyname", c("state", "cz_name"), sep = ",") %>%
    mutate(cz_name = str_replace(cz_name, ":.+", "")) %>%
    distinct()

  small_data <- storm_data_z %>%
    select(event_id, state, cz_name) %>%
    filter(!(state %in% c(
      "GULF OF MEXICO", "GUAM", "ATLANTIC NORTH", "LAKE HURON",
      "LAKE ST CLAIR", "AMERICAN SAMOA", "LAKE SUPERIOR", "ATLANTIC SOUTH",
      "LAKE MICHIGAN", "HAWAII WATERS", "PUERTO RICO", "E PACIFIC",
      "LAKE ERIE", "LAKE ONTARIO", "VIRGIN ISLANDS", "HAWAII", "ALASKA"
    ))) %>%
    mutate(state = str_to_lower(state),
           cz_name = str_to_lower(cz_name),
           cz_name = str_replace_all(cz_name, "[.'``]", ""))

  direct_matches <- small_data %>%
    left_join(county.fips, by = c("state", "cz_name")) %>%
    mutate(fips = ifelse(state == "district of columbia", 11001, fips),
           fips = ifelse(state == "virginia" & cz_name == "chesapeake",
                         51550, fips),
           fips = ifelse(state == "alabama" & cz_name == "dekalb",
                         1049, fips)) %>%
    filter(!is.na(fips)) %>%
    select(event_id, fips)

  unmatched <- filter(small_data, !(event_id %in% direct_matches$event_id))
  county_name_matches <- unmatched %>%
    mutate(cz_name = str_match(cz_name, "([a-z]*+\\s?[a-z]*+)\\s(county|cnty|counties)")[, 2]) %>%
    filter(!is.na(cz_name)) %>%
    left_join(county.fips, by = c("state", "cz_name")) %>%
    filter(!is.na(fips)) %>%
    select(event_id, fips)

  matched_data <- bind_rows(direct_matches, county_name_matches) %>%
    distinct() %>%
    mutate(fips = ifelse(fips == 49049, NA, fips))

  storm_data_z %>%
    left_join(matched_data, by = "event_id") %>%
    mutate(fips = ifelse(str_detect(str_to_lower(cz_name), "national park"),
                         NA, fips))
}

clean_stormevents_details <- function(storm_data) {
  needed_cols <- c(
    "begin_yearmonth", "begin_day", "end_yearmonth", "end_day",
    "episode_id", "event_id", "state", "cz_type", "cz_name", "event_type",
    "state_fips", "cz_fips", "source"
  )

  storm_data %>%
    select(any_of(needed_cols)) %>%
    mutate(state = str_to_title(state),
           cz_name = str_to_title(cz_name))
}

countyize_stormevents <- function(storm_data) {
  storm_data_z <- storm_data %>%
    filter(cz_type == "Z") %>%
    match_forecast_county()

  storm_data_c <- storm_data %>%
    filter(cz_type == "C") %>%
    mutate(fips = as.numeric(paste0(state_fips, sprintf("%03d", cz_fips))))

  bind_rows(storm_data_c, storm_data_z) %>%
    mutate(begin_date = ymd(sprintf("%06d%02d",
                                    as.integer(begin_yearmonth),
                                    as.integer(begin_day))),
           end_date = ymd(sprintf("%06d%02d",
                                  as.integer(end_yearmonth),
                                  as.integer(end_day)))) %>%
    select(-begin_yearmonth, -begin_day, -end_yearmonth, -end_day) %>%
    filter(!is.na(fips)) %>%
    arrange(begin_date)
}

find_storm_events <- function(storm, year_data, dist_limit = 500) {
  distance_df <- closest_dist %>%
    filter(storm_id == storm) %>%
    select(-closest_time_utc, -local_time) %>%
    mutate(closest_date = ymd(closest_date),
           earliest_date = closest_date - days(2),
           latest_date = closest_date + days(2),
           fips = as.numeric(fips))

  year_data %>%
    left_join(distance_df, by = "fips") %>%
    filter(!is.na(begin_date),
           earliest_date <= begin_date,
           begin_date <= latest_date,
           storm_dist <= dist_limit) %>%
    select(-storm_dist, -closest_date, -earliest_date, -latest_date,
           -state_fips, -cz_fips)
}

storm_id_table <- hurr_tracks %>%
  select(storm_id, usa_atcf_id) %>%
  distinct()
storm_years <- gsub(".+-", "", storm_id_table$storm_id)
storms <- storm_id_table$storm_id

storm_events <- vector("list", length(storms))
names(storm_events) <- storms

for (storm_year in unique(storm_years)) {
  print(storm_year)
  yearly_data <- read_stormevents_year(storm_year) %>%
    clean_stormevents_details() %>%
    countyize_stormevents()

  yearly_storms <- storms[storm_years == storm_year]
  for (storm in yearly_storms) {
    print(storm)
    i <- which(storms == storm)
    this_storm_events <- find_storm_events(storm = storm,
                                           year_data = yearly_data,
                                           dist_limit = 500) %>%
      rename(type = event_type) %>%
      mutate(fips = str_pad(fips, width = 5, side = "left", pad = "0")) %>%
      select(fips, type) %>%
      group_by(fips) %>%
      summarize(events = list(type), .groups = "drop")
    storm_events[[i]] <- this_storm_events
  }
}

usethis::use_data(storm_events, overwrite = TRUE)
