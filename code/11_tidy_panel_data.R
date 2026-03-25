source(here::here("code", "00_constants.R"))

cm_panel <- read_csv(
  file.path(out_data_dir, "cross_model_clean.csv"),
  show_col_types = FALSE
) %>%
  mutate(
    gender           = factor(gender, levels = c("Male", "Female")),
    region           = factor(region, levels = region_levels),
    area_type        = factor(area_type, levels = c("Urban", "Rural")),
    policy_treatment = factor(policy_treatment, levels = policy_treatment_levels),
    party            = factor(party, levels = cm_party_levels),
    model            = factor(model, levels = model_levels),
    wave             = factor(wave)
  )

cm_panel <- cm_panel %>%
  bind_cols(
    map_dfc(set_names(cm_party_levels, make.names(cm_party_levels)),
            ~ as.integer(cm_panel$party == .x))
  )

cat("Cross-model panel:", nrow(cm_panel), "obs,",
    n_distinct(cm_panel$model), "models,",
    n_distinct(cm_panel$wave), "waves\n")

saveRDS(cm_panel, file.path(out_data_dir, "cm_panel.rds"))
cat("Saved: cm_panel.rds\n")
