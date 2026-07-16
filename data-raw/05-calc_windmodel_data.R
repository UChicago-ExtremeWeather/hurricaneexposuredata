## Be sure to re-build package after running 01, 02, and 03 and before
## running this

library(dplyr)

load("data/hurr_tracks.rda")
load("data/county_centers_decennial.rda")

storms <- unique(hurr_tracks$usa_atcf_id)
storm_id_table <- hurr_tracks %>%
  select(storm_id, usa_atcf_id) %>%
  distinct()

library(stormwindmodel)

library(devtools)
library(dplyr)

study_states <- c("Alabama", "Arkansas", "Connecticut", "Delaware",
                  "District of Columbia", "Florida", "Georgia",
                  "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
                  "Louisiana", "Maine", "Maryland", "Massachusetts",
                  "Michigan", "Mississippi", "Missouri",
                  "New Hampshire", "New Jersey", "New York", "North Carolina",
                  "Ohio", "Oklahoma", "Pennsylvania", "Rhode Island",
                  "South Carolina", "Tennessee", "Texas", "Vermont",
                  "Virginia", "West Virginia", "Wisconsin")

assign_center_year <- function(storm_year) {
  dplyr::case_when(
    storm_year <= 2009 ~ 2000,
    storm_year <= 2019 ~ 2010,
    TRUE ~ 2020
  )
}

make_county_points <- function(storm_year) {
  center_year <- assign_center_year(storm_year)

  county_centers_decennial %>%
    filter(
      census_year == center_year,
      state_name %in% study_states
    ) %>%
    transmute(
      gridid = fips,
      glat = latitude,
      glon = longitude,
      glandsea = TRUE
    )
}

storm_winds <- vector("list",
                      #length = 2)
                      length = length(storms))
for(i in 1:length(storm_winds)){
  print(storms[i])
  storm_track <- subset(hurr_tracks, usa_atcf_id == storms[i])
  storm_year <- as.integer(sub(".*-([0-9]{4})$", "\\1", storm_track$storm_id[1]))
  county_points <- make_county_points(storm_year)
  winds <- get_grid_winds(hurr_track = storm_track,
                          grid_df = county_points) %>%
    dplyr::rename(fips = gridid) %>%
    dplyr::mutate(usa_atcf_id = storms[i],
                  storm_id = storm_id_table$storm_id[storm_id_table$usa_atcf_id == storms[i]])
  storm_winds[[i]] <- winds
}

storm_winds <- do.call("rbind", storm_winds)
usethis::use_data(storm_winds, overwrite = TRUE)
