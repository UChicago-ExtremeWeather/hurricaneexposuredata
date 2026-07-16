## Be sure to re-build package after re-running 01 and 02 and before
## re-running this
# Use decennial Census population centers by storm decade:
# 1988-1999 -> 2000, 2000-2009 -> 2000, 2010-2019 -> 2010,
# and 2020+ -> 2020.

library(sp)
library(dplyr)
library(lubridate)
library(tidyr)
library(purrr)
library(hurricaneexposure)

data(county_centers_decennial, package = "hurricaneexposuredata")
data(hurr_tracks, package = "hurricaneexposuredata")

library(stormwindmodel)
library(countytimezones)

add_local_time_modern <- function(df, datetime_colname, include_tz = FALSE) {
  datetime_values <- df[[datetime_colname]]
  date_times <- ymd_hm(datetime_values, tz = "UTC")
  tz_lookup <- countytimezones::county_tzs %>%
    transmute(fips = sprintf("%05d", as.integer(fips)),
              local_tz = tz)

  out <- df %>%
    mutate(fips = sprintf("%05d", as.integer(fips))) %>%
    left_join(tz_lookup, by = "fips")

  missing_tz <- out %>%
    filter(is.na(local_tz)) %>%
    distinct(fips) %>%
    pull(fips)
  if (length(missing_tz) > 0) {
    warning(paste("Missing timezone for FIPS:",
                  paste(missing_tz, collapse = ", ")))
  }

  out$local_time <- NA_character_
  out$local_date <- NA_character_

  for (local_tz in unique(stats::na.omit(out$local_tz))) {
    in_tz <- out$local_tz == local_tz & !is.na(out$local_tz)
    local_dates <- with_tz(date_times[in_tz], tzone = local_tz)
    out$local_time[in_tz] <- format(local_dates, "%Y-%m-%d %H:%M")
    out$local_date[in_tz] <- format(local_dates, "%Y-%m-%d")
  }

  if (include_tz) {
    out
  } else {
    dplyr::select(out, -local_tz)
  }
}

## Interpolate storm tracks to every 15 minutes
all_tracks <- hurr_tracks %>%
  mutate(date_time = ymd_hm(date)) %>%
  group_by(storm_id, usa_atcf_id) %>%
  mutate(start_time = first(date_time)) %>%
  mutate(track_time = difftime(date_time, first(date_time), units = "hours"),
         track_time_simple = as.numeric(track_time)) %>%
  ungroup() %>%
  group_by(storm_id, usa_atcf_id, start_time) %>%
  nest() %>%
  mutate(interp_time = purrr::map(data, ~ seq(from = first(.x$track_time_simple),
                                              to = last(.x$track_time_simple),
                                              by = 0.25))) %>%
  # Interpolate latitude and longitude using natural cubic splines
  mutate(interp_lat = purrr::map2(data, interp_time,
                           ~ interpolate_spline(x = .x$track_time_simple,
                                                y = .x$latitude,
                                                new_x = .y))) %>%
  mutate(interp_lon = purrr::map2(data, interp_time,
                           ~ interpolate_spline(x = .x$track_time_simple,
                                                y = .x$longitude,
                                                new_x = .y))) %>%
  select(-data) %>%
  unnest(interp_time:interp_lon) %>%
  ungroup() %>%
  mutate(date = start_time + minutes(60 * interp_time)) %>%
  select(storm_id:usa_atcf_id, date, interp_lat:interp_lon) %>%
  rename(tclon = interp_lon,
         tclat = interp_lat)


calc_closest_dist <- function(this_storm = "Katrina-2005"){
        print(this_storm)
        storm_tracks <- subset(all_tracks, storm_id == this_storm)
        this_id <- storm_tracks$usa_atcf_id[1]
        storm_year <- lubridate::year(storm_tracks$date[1])
        assigned_year <- dplyr::case_when(
                storm_year <= 2009 ~ 2000,
                storm_year <= 2019 ~ 2010,
                TRUE ~ 2020
        )
        county_centers <- county_centers_decennial %>%
                filter(census_year == assigned_year) %>%
                select(-census_year)

        # Calculate distance from county center to storm path
        storm_county_distances <- spDists(
                as.matrix(county_centers[,c("longitude", "latitude")]),
                as.matrix(storm_tracks[,c("tclon", "tclat")]),
                longlat = TRUE) # Return distance in kilometers

        min_locs <- apply(storm_county_distances, 1, which.min)
        min_dists <- apply(storm_county_distances, 1, min)

        study_states <- c("Alabama", "Arkansas", "Connecticut", "Delaware",
                          "District of Columbia", "Florida", "Georgia",
                          "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
                          "Louisiana", "Maine", "Maryland", "Massachusetts",
                          "Michigan", "Mississippi", "Missouri",
                          "New Hampshire", "New Jersey", "New York", "North Carolina",
                          "Ohio", "Oklahoma", "Pennsylvania", "Rhode Island",
                          "South Carolina", "Tennessee", "Texas", "Vermont",
                          "Virginia", "West Virginia", "Wisconsin")

        closest_dist <- mutate(county_centers,
                               closest_date = storm_tracks$date[min_locs],
                               storm_lat = storm_tracks$tclat[min_locs],
                               storm_long = storm_tracks$tclon[min_locs],
                               storm_dist = min_dists) %>%
                filter(state_name %in% study_states) %>%
                mutate(closest_date = format(closest_date, "%Y%m%d%H%M"),
                       storm_id = this_storm, usa_atcf_id = this_id) %>%
                select(storm_id, usa_atcf_id, fips, closest_date, storm_dist)

        return(closest_dist)
}

# Apply to all hurricane tracks
hurrs <- as.character(unique(hurr_tracks$storm_id))

closest_dist <- lapply(hurrs, calc_closest_dist)
closest_dist <- do.call("rbind", closest_dist)

closest_dist <- add_local_time_modern(df = closest_dist,
                     datetime_colname = "closest_date",
                     include_tz = FALSE) %>%
        dplyr::rename(closest_time_utc = closest_date,
               closest_date = local_date) %>%
        mutate(closest_time_utc = ymd_hm(closest_time_utc)) %>%
        mutate(closest_time_utc = format(closest_time_utc,
                                         "%Y-%m-%d %H:%M"))

# Limit hurricane tracks to only storms within 250 km of at least one county
us_storms <- closest_dist %>%
  dplyr::group_by(storm_id) %>%
  dplyr::summarize(closest_county = min(storm_dist)) %>%
  dplyr::filter(closest_county <= 250)
excluded_tracks <- hurr_tracks %>%
  dplyr::filter(!(storm_id %in% us_storms$storm_id))
hurr_tracks <- hurr_tracks %>%
  dplyr::filter(storm_id %in% us_storms$storm_id)

usethis::use_data(excluded_tracks, overwrite = TRUE)
usethis::use_data(hurr_tracks, overwrite = TRUE)

closest_dist <- closest_dist %>%
  dplyr::filter(storm_id %in% us_storms$storm_id)

usethis::use_data(closest_dist, overwrite = TRUE)
