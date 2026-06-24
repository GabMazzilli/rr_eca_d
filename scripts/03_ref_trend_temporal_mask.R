# ==============================================================================
# Rzine methodology: Step 3 - Temporal quality masking & spatial coverage audit
# Target source: Clean Parquet matrix & GeoJSON layer from Step 2
# Context: Rzine publication
# Author: Gabriel Mazzilli (2026), University of Lille
# ==============================================================================

library(dplyr)
library(arrow)
library(sf)
library(lubridate)
library(tidyr)
library(readr)
library(purrr)
library(here) # Added for path portability

# 1. Path and threshold configuration
path_daily_clean  <- here("data", "outputs", "step_data", "E2_daily_final_clean.parquet")
path_gis_stations <- here("data", "outputs", "gis", "E2_stations_final.geojson")
path_study_area   <- here("data", "study_area.gpkg")

dir_data_step <- here("data", "outputs", "step_data")
dir_tables    <- here("data", "outputs", "tables")
dir_reports   <- here("data", "outputs", "tables", "reports")

# Ensure directory structure
if (!dir.exists(dir_data_step)) dir.create(dir_data_step, recursive = TRUE)
if (!dir.exists(dir_tables))    dir.create(dir_tables, recursive = TRUE)
if (!dir.exists(dir_reports))   dir.create(dir_reports, recursive = TRUE)

# Scientific threshold configuration
min_annual_prcp <- 50 

# 2. Dataset loading and total study area estimation
message("[INFO] Ingesting climate series and calculating baseline domain...")

daily                <- read_parquet(path_daily_clean) %>% mutate(date = as.Date(date))
stations_geo         <- st_read(path_gis_stations, quiet = TRUE) %>% st_transform(3035)
study_area           <- st_read(path_study_area, quiet = TRUE) %>% st_transform(3035)

study_area_reference <- st_union(study_area)
study_area_total_km2 <- as.numeric(st_area(study_area_reference)) / 1e6

# 3. Structural multi-level quality masking
message("[STATUS] Compiling chronological validity matrices...")

mask_month_raw <- daily %>%
  mutate(year = year(date), month = month(date)) %>%
  group_by(station_id, year, month) %>%
  summarise(
    valid_days = sum(!is.na(rr)),
    days_in_month = days_in_month(first(date)),
    missing_days = days_in_month - valid_days,
    good_month_raw = missing_days <= 3,
    .groups = "drop"
  )

mask_year_raw <- mask_month_raw %>%
  group_by(station_id, year) %>%
  summarise(
    total_missing_days = sum(missing_days),
    good_months_count = sum(good_month_raw),
    months_present = n(),
    .groups = "drop"
  )

annual_totals <- daily %>%
  mutate(year = year(date)) %>%
  group_by(station_id, year) %>%
  summarise(prcp_tot = sum(rr, na.rm = TRUE), .groups = "drop")

mask_year <- mask_year_raw %>%
  left_join(annual_totals, by = c("station_id", "year")) %>%
  mutate(
    good_year = (total_missing_days <= 15) & 
      (good_months_count == 12) & 
      (months_present == 12) & 
      (prcp_tot >= min_annual_prcp)
  ) %>%
  select(station_id, year, total_missing_days, good_months_count, months_present, prcp_tot, good_year)

mask_month <- mask_month_raw %>%
  left_join(mask_year %>% select(station_id, year, good_year), by = c("station_id", "year")) %>%
  mutate(good_month = if_else(good_year == TRUE, good_month_raw, FALSE)) %>%
  select(station_id, year, month, valid_days, days_in_month, missing_days, good_month)

get_season <- function(m) {
  case_when(
    m %in% c(12, 1, 2)  ~ "DJF",
    m %in% c(3, 4, 5)   ~ "MAM",
    m %in% c(6, 7, 8)   ~ "JJA",
    m %in% c(9, 10, 11) ~ "SON"
  )
}

year_start_data <- min(mask_month$year)
year_end_data   <- max(mask_month$year)

mask_season <- mask_month %>%
  mutate(
    season = get_season(month),
    season_year = if_else(month == 12, year + 1, year)
  ) %>%
  filter(
    !(season == "DJF" & season_year == year_start_data),
    !(season == "DJF" & season_year == (year_end_data + 1))
  ) %>%
  group_by(station_id, season_year, season) %>%
  summarise(
    months_present = n(),
    good_months_count = sum(good_month),
    good_season = (months_present == 3) & (good_months_count == 3),
    .groups = "drop"
  )

write_parquet(mask_month, file.path(dir_data_step, "E3_mask_monthly.parquet"))
write_parquet(mask_season, file.path(dir_data_step, "E3_mask_seasonal.parquet"))
write_parquet(mask_year,   file.path(dir_data_step, "E3_mask_annual.parquet"))

# 4. Helper function for spatial coverage estimation
compute_spatial_coverage <- function(valid_station_ids, radius_km = 10) {
  if (length(valid_station_ids) == 0) return(0)
  
  points_subset <- stations_geo %>% filter(station_id %in% valid_station_ids)
  
  coverage_poly <- points_subset %>%
    st_buffer(radius_km * 1000, endCapStyle = "SQUARE") %>%
    st_union() %>%
    st_intersection(study_area_reference)
  
  if (length(coverage_poly) == 0) return(0)
  return(as.numeric(st_area(coverage_poly)) / 1e6)
}

# 5. Baseline reference windows auditing
message("[INFO] Auditing baseline reference windows (Criterion: >= 24/30 valid years)...")

all_years   <- sort(unique(mask_year$year))
start_min   <- min(all_years)
start_max   <- max(all_years) - 29

ref_windows <- tibble(
  window_start = seq(start_min, start_max),
  window_end   = window_start + 29,
  window_label = paste0(window_start, "-", window_end)
)

ref_overview_list <- lapply(seq_len(nrow(ref_windows)), function(i) {
  ws <- ref_windows$window_start[i]
  we <- ref_windows$window_end[i]
  wl <- ref_windows$window_label[i]
  
  valid_ids <- mask_year %>%
    filter(year >= ws, year <= we) %>%
    group_by(station_id) %>%
    summarise(good_years_count = sum(good_year), .groups = "drop") %>%
    filter(good_years_count >= 24) %>%
    pull(station_id)
  
  covered_area <- compute_spatial_coverage(valid_ids, radius_km = 10)
  
  tibble(
    window_label = wl, window_start = ws, window_end = we,
    retained_stations = length(valid_ids),
    area_coverage_km2 = round(covered_area, 1),
    area_coverage_pct = round(100 * covered_area / study_area_total_km2, 1),
    station_id_list   = paste(valid_ids, collapse = ",")
  )
})

ref_overview <- bind_rows(ref_overview_list) %>% arrange(desc(retained_stations))
write_csv(ref_overview, file.path(dir_reports, "E3_baseline_reference_report.csv"))

# 6. Analysis trend windows auditing
message("[INFO] Auditing analysis trend windows (Criterion: >= 70% valid years)...")

year_max        <- max(mask_year$year[mask_year$good_year == TRUE])
trend_windows   <- tibble(window_start = seq(min(all_years), year_max - 29)) %>%
  mutate(
    window_end   = year_max,
    window_len   = window_end - window_start + 1,
    window_label = paste0(window_start, "-", window_end),
    req_years    = ceiling(0.70 * window_len)
  )

trend_overview_list <- lapply(seq_len(nrow(trend_windows)), function(i) {
  ws  = trend_windows$window_start[i]
  we  = trend_windows$window_end[i]
  wl  = trend_windows$window_label[i]
  len = trend_windows$window_len[i]
  req = trend_windows$req_years[i]
  
  valid_ids <- mask_year %>%
    filter(year >= ws, year <= we) %>%
    group_by(station_id) %>%
    summarise(good_years_count = sum(good_year), .groups = "drop") %>%
    filter(good_years_count >= req) %>%
    pull(station_id)
  
  covered_area <- compute_spatial_coverage(valid_ids, radius_km = 10)
  
  tibble(
    window_label = wl, window_start = ws, window_end = we, window_len = len,
    retained_stations = length(valid_ids),
    area_coverage_km2 = round(covered_area, 1),
    area_coverage_pct = round(100 * covered_area / study_area_total_km2, 1),
    station_id_list   = paste(valid_ids, collapse = ",")
  )
})

trend_overview <- bind_rows(trend_overview_list) %>% filter(retained_stations > 0) %>% arrange(desc(retained_stations))
write_csv(trend_overview, file.path(dir_reports, "E3_analysis_trend_report.csv"))

message("[SUCCESS] Step 3 pipeline finished. Structural temporal and spatial audits compiled.")