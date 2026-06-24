# ==============================================================================
# Rzine methodology: Step 2 - Spatial filtering, quality control and harmonization
# Source: Master Parquet matrix generated during Step 1
# Context: Rzine publication
# Author: Gabriel Mazzilli (2026), University of Lille
# ==============================================================================

library(dplyr)
library(sf)
library(arrow)
library(tidyr)
library(readr)
library(stringr)
library(here)

# 1. Path configuration and spatial domain definition
path_stations_txt  <- here("data", "ECA_nonblend_rr", "stations.txt")
path_daily_parquet <- here("data", "Daily_ECA.parquet")
path_study_area <- here("data", "study_area.gpkg")

# Thresholds
max_daily_precip <- 1100

# Import and parse raw station metadata inventory
lines_stations <- read_lines(path_stations_txt, locale = locale(encoding = "ISO-8859-1"))
header_idx     <- grep("STAID", lines_stations)[1]
data_rows      <- lines_stations[(header_idx + 1):length(lines_stations)]
data_rows      <- data_rows[nzchar(trimws(data_rows))]

split_matrix   <- do.call(rbind, strsplit(data_rows, split = ",\\s*"))
stations_raw   <- as.data.frame(split_matrix, stringsAsFactors = FALSE)
colnames(stations_raw) <- c("STAID", "STANAME", "CN", "LAT", "LON", "HGHT")

# Safe coordinate conversion
parse_ecad_coord <- function(coord_str) {
  coord_clean <- trimws(coord_str)
  if (coord_clean == "" || is.na(coord_clean)) return(NA_real_)
  signe <- if_else(substring(coord_clean, 1, 1) == "-", -1, 1)
  clean_str <- gsub("^[+-]", "", coord_clean)
  parts <- as.numeric(strsplit(clean_str, ":")[[1]])
  if (length(parts) == 3) {
    return(signe * (parts[1] + parts[2]/60 + parts[3]/3600))
  } else {
    return(NA_real_)
  }
}

stations_sf <- stations_raw %>%
  mutate(
    lon_dec = as.numeric(vapply(LON, parse_ecad_coord, FUN.VALUE = numeric(1))),
    lat_dec = as.numeric(vapply(LAT, parse_ecad_coord, FUN.VALUE = numeric(1)))
  ) %>%
  filter(!is.na(lon_dec) & !is.na(lat_dec)) %>%
  st_as_sf(coords = c("lon_dec", "lat_dec"), crs = 4326) %>%
  st_transform(3035)

# Spatial clipping with attribute inheritance
study_area    <- st_read(path_study_area, quiet = TRUE) %>% st_transform(3035)
valid_inside  <- suppressWarnings(st_intersection(stations_sf, study_area))
valid_ids     <- paste0("eca_", trimws(valid_inside$STAID))

# Targeted extraction of daily data
daily_raw <- read_parquet(path_daily_parquet) %>% filter(station_id %in% valid_ids)

# 2. Quality validation and physical threshold checks
message("[STATUS] Implementing quality checks and physical thresholds...")
daily_filtered <- daily_raw %>%
  mutate(
    rr = case_when(
      quality == "valid" & !is.na(rr) & rr >= 0 & rr <= max_daily_precip ~ rr,
      TRUE ~ NA_real_
    )
  )

# 3. Structural identification and resolution of temporal duplicates
message("[STATUS] Detecting and handling duplicate records...")
conflicts <- daily_filtered %>%
  filter(!is.na(rr)) %>%
  distinct(station_id, date, rr) %>%
  group_by(station_id, date) %>%
  summarise(nb_distinct = n(), .groups = "drop") %>%
  filter(nb_distinct > 1)

daily_deduped <- daily_filtered %>%
  left_join(conflicts, by = c("station_id", "date")) %>%
  mutate(rr = if_else(!is.na(nb_distinct), NA_real_, rr)) %>%
  select(-nb_distinct) %>%
  distinct(station_id, date, .keep_all = TRUE)

# 4. Temporal grid completion
message("[STATUS] Generating continuous daily timelines...")
daily_complete <- daily_deduped %>%
  filter(!is.na(date)) %>%
  group_by(station_id) %>%
  complete(date = seq(min(date), max(date), by = "1 day")) %>%
  ungroup()

# 5. Purging empty profiles and final data export
empty_stations <- daily_complete %>%
  group_by(station_id) %>%
  summarise(all_missing = all(is.na(rr)), .groups = "drop") %>%
  filter(all_missing == TRUE) %>%
  pull(station_id)

daily_final <- daily_complete %>%
  filter(!station_id %in% empty_stations)

# Directory output preparation
output_step_path <- here("data", "outputs", "step_data")
output_gis_path  <- here("data", "outputs", "gis")

if (!dir.exists(output_step_path)) dir.create(output_step_path, recursive = TRUE)
if (!dir.exists(output_gis_path)) dir.create(output_gis_path, recursive = TRUE)

write_parquet(daily_final, file.path(output_step_path, "E2_daily_final_clean.parquet"), compression = "snappy")

stations_final_sf <- valid_inside %>%
  mutate(station_id = paste0("eca_", trimws(STAID))) %>%
  filter(station_id %in% unique(daily_final$station_id))

st_write(stations_final_sf, file.path(output_gis_path, "E2_stations_final.geojson"), delete_dsn = TRUE, quiet = TRUE)

message("[SUCCESS] Step 2 pipeline completed.")