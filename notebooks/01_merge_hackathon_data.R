#!/usr/bin/env Rscript

# Deep Learning IndabaX Botswana 2026
# Merge and feature-engineer the provided hackathon datasets.
#
# Main modelling goal:
# Forecast Botswana monthly food price inflation for Jan-Dec 2024.
# The target is FAO_CP_23014, renamed below as target_food_price_inflation.
#
# Important design choice:
# All source data is converted to monthly frequency because the target is
# monthly. This gives one row per month, which is the natural shape for
# time-series validation, lag creation, and forecasting.

required_packages <- c("readr", "dplyr", "tidyr", "lubridate", "janitor", "zoo", "here")

install_missing <- function(packages) {
  # This makes the script portable for our team: if a package is missing
  # on a participant's laptop, R installs it automatically instead of failing at
  # the first library() call.
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
}

suppressWarnings(install_missing(required_packages))

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(janitor)
  library(zoo)
  #library(here)
})

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- "--file="
script_path <- sub(file_arg, "", script_args[grepl(file_arg, script_args)])
script_dir <- if (length(script_path) == 0) getwd() else dirname(normalizePath(script_path))

# This script lives in notebooks/, so the repo root is one level up.
# Paths stay relative to it, so it runs with `Rscript notebooks/01_merge_hackathon_data.R`
# without editing hard-coded machine-specific paths.
repo_root <- dirname(script_dir)
data_dir <- file.path(repo_root, "data", "raw")
processed_dir <- file.path(repo_root, "data", "processed")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

read_clean_csv <- function(file_name) {
  # clean_names() converts columns like "Item Code" and "BDI_Close" into
  # consistent snake_case names: item_code, bdi_close. This prevents quoting
  # problems later in dplyr pipelines.
  df <- readr::read_csv(file.path(data_dir, file_name), show_col_types = FALSE)
  suppressWarnings(janitor::clean_names(df))
}

make_month <- function(date_vector) {
  # Brent is stored on the 15th, policy rate on the 1st, and BDI is daily.
  # floor_date() maps all of these to the same monthly join key.
  lubridate::floor_date(as.Date(date_vector), unit = "month")
}

add_lags <- function(df, vars, lags, order_col = "year_month") {
  # Lags are central to forecasting: when predicting a future month, we usually
  # know past values but not same-month future values. Lagged predictors reduce
  # the risk of look-ahead leakage.
  df <- df %>% arrange(.data[[order_col]])
  for (var in vars) {
    for (lag_n in lags) {
      df[[paste0(var, "_lag", lag_n)]] <- dplyr::lag(df[[var]], lag_n)
    }
  }
  df
}

add_rolling <- function(df, vars, windows, order_col = "year_month") {
  # Rolling means smooth noisy month-to-month movements and give models a
  # simple trend signal. They are trailing windows, so they only use current
  # and past observations.
  df <- df %>% arrange(.data[[order_col]])
  for (var in vars) {
    for (window_n in windows) {
      df[[paste0(var, "_roll", window_n, "_mean")]] <- zoo::rollapplyr(
        df[[var]],
        width = window_n,
        FUN = mean,
        na.rm = TRUE,
        fill = NA_real_
      )
    }
  }
  df
}

safe_pct_change <- function(x, n = 1) {
  # Percentage changes are useful shock/momentum features. The guard avoids
  # infinite values when the previous observation is zero or missing.
  previous <- dplyr::lag(x, n)
  ifelse(is.na(previous) | previous == 0, NA_real_, (x / previous - 1) * 100)
}

# Dataset 1: Baltic Dry Index, daily.
# Decision: we do more than a naive monthly average because the data guide says
# the daily-to-monthly transformation is part of the feature engineering
# challenge. Mean, volatility, range, first/last movement, and trading-day count
# preserve more signal about supply-chain stress within each month.
bdi_daily <- read_clean_csv("01_baltic_dry_index_daily.csv") %>%
  mutate(year_month = make_month(date))

bdi_monthly <- bdi_daily %>%
  group_by(year_month) %>%
  summarise(
    bdi_close_mean = mean(bdi_close, na.rm = TRUE),
    bdi_close_sd = sd(bdi_close, na.rm = TRUE),
    bdi_close_min = min(bdi_close, na.rm = TRUE),
    bdi_close_max = max(bdi_close, na.rm = TRUE),
    bdi_close_first = first(bdi_close),
    bdi_close_last = last(bdi_close),
    bdi_high_mean = mean(bdi_high, na.rm = TRUE),
    bdi_low_mean = mean(bdi_low, na.rm = TRUE),
    bdi_trading_days = n(),
    .groups = "drop"
  ) %>%
  mutate(
    bdi_close_range = bdi_close_max - bdi_close_min,
    bdi_close_change_abs = bdi_close_last - bdi_close_first,
    bdi_close_change_pct = ifelse(
      bdi_close_first == 0,
      NA_real_,
      (bdi_close_last / bdi_close_first - 1) * 100
    )
  )

# Dataset 2: Brent crude, already monthly.
# Decision: keep the price level and add month-on-month and year-on-year
# percentage changes. Food inflation may respond to both absolute fuel costs and
# sudden oil-price shocks.
brent_monthly <- read_clean_csv("02_brent_crude_monthly.csv") %>%
  transmute(
    year_month = make_month(date),
    brent_usd_per_barrel
  ) %>%
  arrange(year_month) %>%
  mutate(
    brent_mom_pct = safe_pct_change(brent_usd_per_barrel, 1),
    brent_yoy_pct = safe_pct_change(brent_usd_per_barrel, 12)
  )

# Dataset 3: Botswana policy rate, already monthly.
# Decision: include the level and changes over 1 and 12 months. The level
# describes monetary conditions; changes capture tightening or easing.
policy_monthly <- read_clean_csv("03_botswana_policy_rate.csv") %>%
  transmute(
    year_month = make_month(date),
    policy_rate
  ) %>%
  arrange(year_month) %>%
  mutate(
    policy_rate_change_1m = policy_rate - lag(policy_rate, 1),
    policy_rate_change_12m = policy_rate - lag(policy_rate, 12)
  )

# Dataset 4: Botswana FAO price data, long format.
# Decision: pivot to wide so each month has one target row and separate columns
# for each FAO indicator. Item 23014 is explicitly renamed as the target to make
# modelling code less error-prone.
fao_botswana_wide <- read_clean_csv("04_fao_botswana_prices.csv") %>%
  mutate(
    year_month = make_month(date),
    indicator = paste0("fao_cp_", item_code)
  ) %>%
  select(year_month, indicator, value) %>%
  pivot_wider(names_from = indicator, values_from = value) %>%
  arrange(year_month) %>%
  mutate(
    fao_food_index_mom_pct = safe_pct_change(fao_cp_23013, 1),
    fao_food_index_yoy_pct_calc = safe_pct_change(fao_cp_23013, 12),
    target_food_price_inflation = fao_cp_23014
  )

# Dataset 5: cross-country HCP file.
# Pivot country-indicator rows into columns. Comparator countries can
# be useful spillover features; for example, South African food inflation may
# lead Botswana through trade links.
hcp_cross_country_wide <- read_clean_csv("05_human_capital_project.csv") %>%
  mutate(
    year_month = make_month(date),
    feature_name = paste0(
      "hcp_",
      tolower(ref_area),
      "_",
      tolower(indicator)
    )
  ) %>%
  select(year_month, feature_name, value) %>%
  pivot_wider(names_from = feature_name, values_from = value) %>%
  arrange(year_month)

# Main join.
# Decision: full_join keeps all months available from any source. In this data
# all five sources cover Jan 2000-Dec 2023 after aggregation, but full_join is
# robust if a file later has a slightly different range.
merged_monthly <- fao_botswana_wide %>%
  full_join(bdi_monthly, by = "year_month") %>%
  full_join(brent_monthly, by = "year_month") %>%
  full_join(policy_monthly, by = "year_month") %>%
  full_join(hcp_cross_country_wide, by = "year_month") %>%
  arrange(year_month) %>%
  mutate(
    year = lubridate::year(year_month),
    month = lubridate::month(year_month),
    # Cyclical month encoding tells ML models that December and January are
    # neighbours. A plain month number would incorrectly make them far apart.
    month_sin = sin(2 * pi * month / 12),
    month_cos = cos(2 * pi * month / 12)
  ) %>%
  relocate(year_month, year, month, month_sin, month_cos, target_food_price_inflation)

numeric_features <- merged_monthly %>%
  select(where(is.numeric)) %>%
  select(-year, -month, -target_food_price_inflation) %>%
  names()

readr::write_csv(merged_monthly, file.path(processed_dir, "merged_monthly_features.csv"))

# Diagnostics are intentionally written as a CSV so we can quickly verify
# that the merge produced the expected 288 monthly rows before modelling.
diagnostics <- tibble(
  dataset = c(
    "bdi_daily",
    "bdi_monthly",
    "brent_monthly",
    "policy_monthly",
    "fao_botswana_wide",
    "hcp_cross_country_wide",
    "merged_monthly",
    "modelling_table"
  ),
  rows = c(
    nrow(bdi_daily),
    nrow(bdi_monthly),
    nrow(brent_monthly),
    nrow(policy_monthly),
    nrow(fao_botswana_wide),
    nrow(hcp_cross_country_wide),
    nrow(merged_monthly),
    nrow(modelling_table)
  ),
  columns = c(
    ncol(bdi_daily),
    ncol(bdi_monthly),
    ncol(brent_monthly),
    ncol(policy_monthly),
    ncol(fao_botswana_wide),
    ncol(hcp_cross_country_wide),
    ncol(merged_monthly),
    ncol(modelling_table)
  ),
  min_month = c(
    min(bdi_daily$year_month),
    min(bdi_monthly$year_month),
    min(brent_monthly$year_month),
    min(policy_monthly$year_month),
    min(fao_botswana_wide$year_month),
    min(hcp_cross_country_wide$year_month),
    min(merged_monthly$year_month),
    min(modelling_table$year_month)
  ),
  max_month = c(
    max(bdi_daily$year_month),
    max(bdi_monthly$year_month),
    max(brent_monthly$year_month),
    max(policy_monthly$year_month),
    max(fao_botswana_wide$year_month),
    max(hcp_cross_country_wide$year_month),
    max(merged_monthly$year_month),
    max(modelling_table$year_month)
  )
)
readr::write_csv(diagnostics, file.path(processed_dir, "merge_diagnostics.csv"))

data_dictionary <- tibble::tribble(
  ~column_pattern, ~type, ~meaning, ~recommended_use,
  "year_month", "Date", "Month of observation, stored as the first day of the month.", "Primary join key and time-series index.",
  "year", "Integer", "Calendar year extracted from year_month.", "Trend, split, or reporting feature.",
  "month", "Integer", "Calendar month number from 1 to 12.", "Seasonality feature.",
  "month_sin, month_cos", "Numeric", "Cyclical encoding of month.", "Seasonality features for machine learning models.",
  "target_food_price_inflation", "Numeric", "Botswana food price inflation, equal to FAO item 23014.", "Main target variable to forecast.",
  "fao_cp_23012", "Numeric", "Botswana general consumer price index, 2015 equals 100.", "Inflation and price-level feature.",
  "fao_cp_23013", "Numeric", "Botswana food consumer price index, 2015 equals 100.", "Core food price-level feature.",
  "fao_cp_23014", "Numeric", "Original FAO food price inflation field.", "Same value as target_food_price_inflation.",
  "fao_food_index_mom_pct", "Numeric", "Month-on-month percentage change in Botswana food CPI.", "Momentum feature.",
  "fao_food_index_yoy_pct_calc", "Numeric", "Calculated year-on-year percentage change in Botswana food CPI.", "Audit feature for FAO_CP_23014.",
  "bdi_close_mean", "Numeric", "Monthly average Baltic Dry Index close.", "Shipping cost / supply-chain feature.",
  "bdi_close_sd", "Numeric", "Within-month standard deviation of BDI close.", "Shipping volatility feature.",
  "bdi_close_min, bdi_close_max", "Numeric", "Monthly minimum and maximum BDI close.", "Stress and range features.",
  "bdi_close_first, bdi_close_last", "Numeric", "First and last BDI close observed in the month.", "Monthly direction features.",
  "bdi_close_range", "Numeric", "Monthly BDI max minus min.", "Shipping volatility feature.",
  "bdi_close_change_abs", "Numeric", "Last BDI close minus first BDI close within a month.", "Shipping momentum feature.",
  "bdi_close_change_pct", "Numeric", "Percentage change from first to last BDI close within a month.", "Shipping momentum feature.",
  "bdi_high_mean, bdi_low_mean", "Numeric", "Monthly average of BDI daily highs and lows.", "Alternative shipping pressure features.",
  "bdi_trading_days", "Integer", "Number of BDI trading-day observations in the month.", "Data quality / calendar feature.",
  "brent_usd_per_barrel", "Numeric", "Monthly Brent crude oil price in US dollars per barrel.", "Fuel and transport-cost feature.",
  "brent_mom_pct", "Numeric", "Month-on-month percentage change in Brent.", "Oil momentum feature.",
  "brent_yoy_pct", "Numeric", "Year-on-year percentage change in Brent.", "Oil shock feature.",
  "policy_rate", "Numeric", "Bank of Botswana policy interest rate in percent.", "Monetary-policy feature.",
  "policy_rate_change_1m", "Numeric", "One-month change in the policy rate.", "Policy tightening/easing feature.",
  "policy_rate_change_12m", "Numeric", "Twelve-month change in the policy rate.", "Policy stance feature.",
  "hcp_<country>_fao_cp_23012", "Numeric", "General CPI for Botswana or comparator countries.", "Cross-country price-pressure feature.",
  "hcp_<country>_fao_cp_23013", "Numeric", "Food CPI for Botswana or comparator countries.", "Cross-country food-price feature.",
  "hcp_<country>_fao_cp_23014", "Numeric", "Food price inflation for Botswana or comparator countries.", "Cross-country inflation spillover feature.",
  "*_lag1, *_lag2, *_lag3, *_lag6, *_lag12", "Numeric", "Lagged value of the source column by 1, 2, 3, 6, or 12 months.", "Forecasting-safe features when predicting future months.",
  "*_roll3_mean, *_roll6_mean, *_roll12_mean", "Numeric", "Trailing rolling average over 3, 6, or 12 months.", "Smoothing and trend features."
)

readr::write_csv(data_dictionary, file.path(processed_dir, "data_dictionary.csv"))


# Modelling table.
# Decision: create common lags used in macro/food-price forecasting:
# 1-3 months for short transmission, 6 months for medium policy/economic lag,
# and 12 months for seasonality/year-on-year comparison.
#
# The output still includes same-month raw variables for exploration. For a
# strict 2024 forecast, we prefer lagged variables
# because same-month 2024 Brent/BDI/policy values are not
# provided in the challenge data.
modelling_table <- merged_monthly %>%
  add_lags(
    vars = c(
      "target_food_price_inflation",
      "fao_cp_23012",
      "fao_cp_23013",
      numeric_features
    ) %>% unique(),
    lags = c(1, 2, 3, 6, 12)
  ) %>%
  add_rolling(
    vars = c(
      "target_food_price_inflation",
      "fao_cp_23013",
      "bdi_close_mean",
      "brent_usd_per_barrel",
      "policy_rate"
    ),
    windows = c(3, 6, 12)
  ) %>%
  filter(!is.na(target_food_price_inflation)) %>%
  arrange(year_month)

readr::write_csv(modelling_table, file.path(processed_dir, "modelling_table_with_lags.csv"))


