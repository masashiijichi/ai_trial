# =============================================================================
# 01_clean_cross_model.R
# Load raw cross-model CSVs, extract parties, detect refusals,
# translate variables, and save cleaned data.
#
# Input:  data-out/cross_model/japan2026_election_*_wave_*.csv
# Output: data-modified/cross_model_clean.csv
# =============================================================================

source(here::here("code", "00_constants.R"))

# --- NOTE: GPT-4o Mini coverage ---
# GPT-4o Mini lacks T=-6 (no CSV file; data collection started from T=-5).
# T=-1 (2026-02-07): all responses are NA (technical export error).
# T=-1 is excluded below at the raw-data stage so downstream scripts
# do not need their own exclusion logic.

# --- 1. Load all cross-model CSVs ---
all_files <- list.files(cm_data_dir, pattern = "\\.csv$", full.names = TRUE)
cat("Found", length(all_files), "cross-model CSV files.\n")

raw_list <- map(all_files, function(path) {
  fname <- basename(path)
  m <- case_when(
    str_detect(fname, "gpt4omini")    ~ "GPT-4o Mini",
    str_detect(fname, "gpt5mini")     ~ "GPT-5 Mini",
    str_detect(fname, "gemini")       ~ "Gemini 2.5 Flash",
    str_detect(fname, "grok_web_x")   ~ "Grok 4.1 Fast (Web+X)",
    str_detect(fname, "grok_webonly") ~ "Grok 4.1 Fast (Web-only)",
    TRUE ~ NA_character_
  )
  if (is.na(m)) return(NULL)
  df <- read_csv(path, show_col_types = FALSE)
  resp_col <- intersect(c("gpt_response", "gemini_response", "grok_response"), names(df))
  df %>%
    rename(response = !!sym(resp_col[1])) %>%
    mutate(model = m)
})

raw_data <- bind_rows(compact(raw_list)) %>%
  filter(!(model == "GPT-4o Mini" & wave_date == "2026-02-07"))
cat("Total raw observations:", nrow(raw_data), "\n")

# --- 2. Extract party names and detect refusals ---
cm_clean <- raw_data %>%
  mutate(
    party_raw     = str_extract(response, "^[^\n.。]+"),
    party_raw     = na_if(party_raw, ""),
    party_raw     = str_remove_all(party_raw, "\\*"),
    party_raw     = str_remove_all(party_raw, "^#+\\s*"),
    party_raw     = str_trim(party_raw),
    party_matched = map_chr(party_raw, match_party),
    party = case_when(
      !is.na(party_matched)         ~ party_matched,
      !is_technical_error(response) ~ "Refusal",
      TRUE                          ~ NA_character_
    ),
    response_type = case_when(
      !is.na(party_matched)         ~ "Valid Party",
      !is_technical_error(response) ~ "Refusal",
      TRUE                          ~ "NA/Error"
    )
  )

# --- 3. Translate variables ---
cm_clean <- cm_clean %>%
  mutate(
    gender = case_when(
      gender == "男性" ~ "Male",
      gender == "女性" ~ "Female",
      TRUE ~ gender
    ),
    region    = region_map[region],
    area_type = case_when(
      area_type == "都市部" ~ "Urban",
      area_type == "地方部" ~ "Rural",
      TRUE ~ area_type
    ),
    policy_issue = policy_map[policy_issue],
    policy_stance = case_when(
      policy_stance == "control" ~ "Control",
      policy_stance == "賛成" & policy_issue %in% pro_is_right ~ "Right",
      policy_stance == "賛成" ~ "Left",
      policy_stance == "反対" & policy_issue %in% pro_is_right ~ "Left",
      policy_stance == "反対" ~ "Right",
      TRUE ~ policy_stance
    ),
    policy_treatment = if_else(
      policy_stance == "Control", "Control",
      paste0(policy_issue, ": ", policy_stance)
    ),
    wave       = as.character(wave_id),
    days_until = as.numeric(as.Date(wave_date) - election_date)
  )

# --- 4. Set factor levels ---
cm_clean <- cm_clean %>%
  mutate(
    gender           = factor(gender, levels = c("Male", "Female")),
    region           = factor(region, levels = region_levels),
    area_type        = factor(area_type, levels = c("Urban", "Rural")),
    policy_treatment = factor(policy_treatment, levels = policy_treatment_levels),
    party            = factor(party, levels = cm_party_levels),
    model            = factor(model, levels = model_levels),
    wave             = factor(wave)
  )

# --- 5. Select final columns and save ---
cm_out <- cm_clean %>%
  select(
    model, gender, region, area_type,
    policy_issue, policy_stance, policy_treatment,
    party, response_type,
    wave, wave_date, days_until
  )

out_path <- file.path(out_data_dir, "cross_model_clean.csv")
write_csv(cm_out, out_path)
cat("Saved:", out_path, "\n")
cat("Observations:", nrow(cm_out), "\n")
cat("Models:", paste(levels(cm_out$model), collapse = ", "), "\n")
cat("Waves:", n_distinct(cm_out$wave), "\n")

# --- Summary ---
cat("\n=== Response type breakdown ===\n")
cm_out %>%
  count(model, response_type) %>%
  pivot_wider(names_from = response_type, values_from = n, values_fill = 0) %>%
  print()
