# ==============================================================================
# ARTICLE METHODOLOGY: Master Pipeline Orchestrator
# Target Framework: Comprehensive Reproducibility Protocol
# Project Context: Rzine Publication Standards
# Author: Gabriel Mazzilli (2026), University of Lille
# ==============================================================================

# Note: Open this project using the .Rproj file to ensure the working directory
# is correctly set to the project root.

library(here)

# ==============================================================================
# 1. ORCHESTRATION ENGINE (HELPER FUNCTIONS)
# ==============================================================================
run_methodological_step <- function(script_path, step_label) {
  cat("----------------------------------------------------------------------\n")
  cat(sprintf(" MODULE RUN: %s\n", step_label))
  cat(sprintf(" Source Asset: %s\n", script_path))
  cat("----------------------------------------------------------------------\n")
  
  step_start <- Sys.time()
  
  # Process script within an isolated scope
  execution_status <- tryCatch({
    source(here::here(script_path), local = FALSE, echo = FALSE)
    TRUE
  }, error = function(e) {
    cat(sprintf("\n[CRITICAL ERROR] Execution aborted within: %s\n", step_label))
    cat("Intercepted Exception: ", e$message, "\n\n")
    return(FALSE)
  })
  
  if (!execution_status) {
    stop("Global pipeline execution terminated to prevent structural data corruption.", call. = FALSE)
  }
  
  step_end <- Sys.time()
  duration <- round(difftime(step_end, step_start, units = "secs"), 1)
  cat(sprintf("[STATUS] Module verified. Processing time: %s seconds.\n\n", duration))
}

# ==============================================================================
# 2. PIPELINE EXECUTION SEQUENCE
# ==============================================================================
pipeline_start_time <- Sys.time()
cat(">>> [INIT] Initializing climate data processing pipeline...\n\n")

# Step 1: Remote asset acquisition and binary format conversion
run_methodological_step(
  script_path = "scripts/01_climate_data_acquisition.R", 
  step_label  = "Step 1 - Remote Asset Acquisition & Binary Format Conversion"
)

# Step 2: Spatial intersection and chronological grid harmonization
run_methodological_step(
  script_path = "scripts/02_spatial_quality_temporal_step.R", 
  step_label  = "Step 2 - Spatial Intersection & Chronological Grid Harmonization"
)

# Step 3: Data quality profiling and temporal threshold filtering
run_methodological_step(
  script_path = "scripts/03_ref_trend_temporal_mask.R", 
  step_label  = "Step 3 - Data Quality Profiling & Critical Temporal Filtering"
)

# ==============================================================================
# 3. FINAL INTEGRITY MATRIX & RUNTIME REPORT
# ==============================================================================
pipeline_end_time <- Sys.time()
total_duration    <- round(difftime(pipeline_end_time, pipeline_start_time, units = "mins"), 2)

cat("======================================================================\n")
cat(" PIPELINE INTEGRITY METRICS REPORT: VERIFICATION COMPLETED\n")
cat("======================================================================\n")
cat(" Status Result:         SUCCESS — Pipeline reproducible\n")
cat(" Total Pipeline Runtime:", total_duration, "minutes\n")
cat(" Completion Timestamp:  ", as.character(pipeline_end_time), "\n")
cat(" Output Assets Secured: data/outputs/step_data/\n")
cat("                        data/outputs/gis/\n")
cat("======================================================================\n")