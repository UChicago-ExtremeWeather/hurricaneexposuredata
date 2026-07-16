library(dplyr)
library(devtools)
library(purrr)
library(stringi)
library(stringr)

options(timeout = 300)

# Read in and clean up `county_centers`
years <- c(2000, 2010, 2020)
county_centers_list <- vector("list", length(years))

for (i in seq_along(years)) {
  year <- years[i]

  if (year == 2000) {
    base_url <- "https://www2.census.gov/geo/docs/reference/cenpop2000/county/"
    files <- readLines(base_url) %>%
      str_extract("cou_[0-9]{2}_[a-z]{2}[.]txt") %>%
      na.omit() %>%
      unique()

    county_centers_list[[i]] <- map_dfr(files, function(file) {
      message("Reading ", file)
      text <- readLines(paste0(base_url, file), warn = FALSE) %>%
        paste(collapse = " ") %>%
        str_squish() %>%
        str_replace_all("\\s+(?=[0-9]{2},[0-9]{3},)", "\n")

      read.csv(text = text,
               header = FALSE,
               col.names = c("STATEFP", "COUNTYFP", "COUNAME", "POPULATION",
                             "LATITUDE", "LONGITUDE"),
               as.is = TRUE)
    })
  } else {
    county_centers_list[[i]] <- read.csv(paste0("https://www2.census.gov/geo/docs/reference/",
                                    "cenpop",
                                    year,
                                    "/county/CenPop",
                                    year,
                                    "_Mean_CO.txt"),
                             as.is = TRUE)
  }

  county_centers_list[[i]] <- county_centers_list[[i]] %>%
        mutate(fips = paste0(sprintf("%02d", STATEFP),
                             sprintf("%03d", COUNTYFP)),
               COUNAME = stri_trans_general(COUNAME, "latin-ascii"),
               census_year = year) %>%
        select(fips, COUNAME, any_of("STNAME"), POPULATION, LATITUDE, LONGITUDE, census_year) %>%
        rename(county_name = COUNAME,
               population = POPULATION,
               latitude = LATITUDE, longitude = LONGITUDE)
}

county_centers_decennial <- bind_rows(county_centers_list)
state_lookup <- county_centers_decennial %>%
  filter(census_year == 2010) %>%
  select(fips, state_name = STNAME)

county_centers_decennial <- county_centers_decennial %>%
  left_join(state_lookup, by = "fips") %>%
  mutate(state_name = coalesce(STNAME, state_name)) %>%
  select(fips, county_name, state_name, population, latitude, longitude,
         census_year)

county_centers <- county_centers_decennial %>%
  filter(census_year == 2010) %>%
  select(-census_year)

usethis::use_data(county_centers, overwrite = TRUE)
usethis::use_data(county_centers_decennial, overwrite = TRUE)
