# =============================================================================
# 21_fig_control.R
# Figure 1: Party recommendation rates in the control condition, by model.
#
# Output: draft/figures/fig_control.pdf
# =============================================================================

source(here::here("code", "00_constants.R"))

cm_panel <- readRDS(file.path(out_data_dir, "cm_panel.rds"))

# --- Filter to control condition; include valid party + Refusal, exclude NA/Error ---
# Compute shares with Refusal included in denominator, then drop Refusal from plot
ctrl_data <- cm_panel %>%
  filter(policy_treatment == "Control", !is.na(party)) %>%
  group_by(model) %>%
  mutate(total = n()) %>%
  ungroup() %>%
  group_by(model, party, total) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(
    share = n / total * 100,
    model = factor(model, levels = model_levels),
    party_label = factor(
      party_display[as.character(party)],
      levels = party_display[cm_party_levels]
    )
  )

# --- Faceted bar plot ---
p <- ggplot(ctrl_data, aes(x = model, y = share, fill = model)) +
  geom_col(width = 0.7, color = "white", linewidth = 0.2) +
  facet_wrap(~party_label, ncol = 3) +
  scale_fill_manual(values = model_colors, breaks = model_levels) +
  scale_x_discrete(labels = NULL) +
  scale_y_continuous(
    limits = c(0, NA),
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    x    = NULL,
    y    = "Recommendation rate (%)",
    fill = NULL
  ) +
  theme_bw(base_size = 9) +
  theme(
    axis.ticks.x       = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    legend.position    = "bottom",
    strip.text         = element_text(face = "bold", size = 8),
    strip.background   = element_rect(fill = "gray95", color = "gray70")
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(file.path(out_fig_dir, "fig_control.pdf"), p,
       width = 7, height = 8)
cat("Saved: figures/fig_control.pdf\n")
