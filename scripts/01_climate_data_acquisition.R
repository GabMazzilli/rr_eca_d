# ==============================================================================
# Rzine methodology: Step 1 - Data acquisition and format conversion
# Source: ECA&D database (non-blended precipitation dataset)
# Context: Rzine publication
# Author: Gabriel Mazzilli (2026), University of Lille
# ==============================================================================

library(readr)
library(dplyr)
library(arrow)
library(stringr)
library(here)

# 1. Path configuration and infrastructure setup
url_zip <- "https://knmi-ecad-assets-prd.s3.amazonaws.com/download/ECA_nonblend_rr.zip"
dir_raw <- here("data", "ECA_nonblend_rr")
path_parquet <- here("data", "Daily_ECA.parquet")

# Create directory structure if it does not exist
if (!dir.exists(dir_raw)) dir.create(dir_raw, recursive = TRUE)

# 2. Automated raw dataset retrieval
if (!file.exists(file.path(dir_raw, "stations.txt"))) {
  message("[INFO] Local data directory empty or missing. Initiating download...")
  temp_zip <- tempfile(fileext = ".zip")
  
  download.file(url = url_zip, destfile = temp_zip, mode = "wb")
  
  message("[INFO] Extracting raw station files...")
  unzip(zipfile = temp_zip, exdir = dir_raw)
  unlink(temp_zip)
  
  message("[SUCCESS] Download and extraction completed.")
} else {
  message("[INFO] Raw ECA&D assets already present locally.")
}

# 3. Data files scanning
station_files <- list.files(dir_raw, pattern = "^RR_SOUID.*\\.txt$", full.names = TRUE)
message("[INFO] Total source station files identified: ", length(station_files))

# 4. Parsing function for individual station profiles
read_eca_file <- function(file) {
  lines <- read_lines(file, skip_empty_rows = TRUE)
  
  last_header_line <- tail(grep("STAID", lines), 1)
  if (length(last_header_line) == 0) return(NULL)
  
  data_lines <- lines[(last_header_line + 1):length(lines)]
  data_lines <- data_lines[nzchar(trimws(data_lines))]
  if (length(data_lines) == 0) return(NULL)
  
  df <- suppressMessages(read_delim(
    file = I(data_lines),
    delim = ",",
    trim_ws = TRUE,
    col_names = c("STAID", "SOUID", "DATE", "RR", "Q_RR"),
    col_types = cols(
      STAID = col_integer(),
      SOUID = col_integer(),
      DATE  = col_character(), 
      RR    = col_double(),
      Q_RR  = col_integer()
    )
  ))
  
  if (nrow(df) == 0) return(NULL)
  
  df %>%
    mutate(
      station_id = paste0("eca_", STAID),
      date = as.Date(DATE, format = "%Y%m%d"),
      rr = RR / 10, 
      quality = case_when(
        Q_RR == 0 ~ "valid",
        Q_RR == 1 ~ "suspect",
        TRUE      ~ NA_character_
      )
    ) %>%
    filter(!is.na(date)) %>%
    select(station_id, date, rr, quality)
}

# 5. Batch-based pipeline processing
if (!file.exists(path_parquet)) {
  batch_size <- 1000
  batches <- split(station_files, ceiling(seq_along(station_files) / batch_size))
  message("[INFO] Converting text files across ", length(batches), " batches...")
  
  all_data <- vector("list", length(batches))
  
  for (b in seq_along(batches)) {
    message("[STATUS] Processing batch ", b, "/", length(batches))
    
    current_batch_files <- batches[[b]]
    total_in_batch <- length(current_batch_files)
    batch_list <- vector("list", total_in_batch)
    
    for (i in seq_along(current_batch_files)) {
      f <- current_batch_files[[i]]
      batch_list[[i]] <- tryCatch(read_eca_file(f), error = function(e) NULL)
    }
    
    all_data[[b]] <- bind_rows(batch_list)
    rm(batch_list); gc() 
  }
  
  final_data <- bind_rows(all_data)
  message("[INFO] Master dataframe compiled. Total rows parsed: ", nrow(final_data))
  
  write_parquet(final_data, path_parquet)
  message("[SUCCESS] Master file saved as Daily_ECA.parquet")
  
  rm(final_data, all_data); gc()
} else {
  message("[INFO] Master Parquet file exists. Bypassing processing.")
}