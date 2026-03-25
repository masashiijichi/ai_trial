library(tidyverse)

# --- Paths ---
proj_root   <- here::here()
cm_data_dir <- file.path(proj_root, "data-out", "cross_model")
out_data_dir <- file.path(proj_root, "data-modified")
out_fig_dir  <- file.path(proj_root, "draft", "figures")
out_val_dir  <- file.path(proj_root, "values")

dir.create(out_data_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(out_fig_dir,  showWarnings = FALSE, recursive = TRUE)
dir.create(out_val_dir,  showWarnings = FALSE, recursive = TRUE)

# --- Election date ---
election_date <- as.Date("2026-02-08")

# --- Party regex map (Japanese -> English) ---
party_regex_map <- tribble(
  ~pattern,                                ~party_en,
  "自由民主|自民",                         "LDP",
  "中道|立憲|公明",                        "Centrist Reform",
  "維新",                                  "Innovation",
  "国民民主",                              "DPP",
  "共産",                                  "JCP",
  "れいわ|新選組",                         "Reiwa",
  "参政",                                  "Sanseito",
  "保守党|日本保守",                       "Conservative",
  "社民|社会民主",                         "SDP",
  "みらい",                                "Team Mirai",
  "減税日本|ゆうこく",                     "Tax Cut Coalition"
)

match_party <- function(raw_text, anchored = FALSE) {
  if (is.na(raw_text) || raw_text == "" || raw_text == "CONNECTION_ERROR") {
    return(NA_character_)
  }
  for (i in seq_len(nrow(party_regex_map))) {
    pat <- if (anchored) paste0("^", party_regex_map$pattern[i]) else party_regex_map$pattern[i]
    if (str_detect(raw_text, regex(pat, ignore_case = TRUE))) {
      return(party_regex_map$party_en[i])
    }
  }
  NA_character_
}

is_technical_error <- function(text) {
  is.na(text) | !str_detect(coalesce(text, ""), "[\\p{Hiragana}\\p{Katakana}\\p{Han}]")
}

# --- Translation maps ---
region_map <- c(
  "北海道" = "Hokkaido", "東北" = "Tohoku",
  "北関東" = "Kita-Kanto", "南関東" = "Minami-Kanto", "東京" = "Tokyo",
  "北陸・信越" = "Hokuriku-Shinetsu", "東海" = "Tokai", "近畿" = "Kinki",
  "中国" = "Chugoku", "四国" = "Shikoku", "九州" = "Kyushu"
)

policy_map <- c(
  "消費税" = "Consumption Tax", "防衛費" = "Defense Spending",
  "外国人労働者" = "Foreign Workers", "永住許可" = "Permanent Residency",
  "対中関係" = "China Relations", "スパイ防止法" = "Espionage Law",
  "憲法改正" = "Constitutional Amendment", "議員定数削減" = "Diet Seat Reduction",
  "社会保険料" = "Social Insurance", "企業献金" = "Corporate Donations",
  "夫婦別姓" = "Dual Surnames", "原発" = "Nuclear Power",
  "none" = "None"
)

pro_is_right <- c(
  "Defense Spending", "Permanent Residency", "Espionage Law",
  "Constitutional Amendment", "Diet Seat Reduction",
  "Social Insurance", "Nuclear Power"
)

# --- Policy treatment factor levels ---
policy_issues_en <- c(
  "Consumption Tax", "Defense Spending", "Foreign Workers",
  "Permanent Residency", "China Relations", "Espionage Law",
  "Constitutional Amendment", "Diet Seat Reduction",
  "Social Insurance", "Corporate Donations",
  "Dual Surnames", "Nuclear Power"
)

policy_treatment_levels <- c(
  "Control",
  as.vector(t(outer(policy_issues_en, c(": Right", ": Left"), paste0)))
)

policy_label_order <- rev(c(
  "Consumption Tax: Right", "Consumption Tax: Left",
  "Defense Spending: Right", "Defense Spending: Left",
  "Foreign Workers: Right", "Foreign Workers: Left",
  "Permanent Residency: Right", "Permanent Residency: Left",
  "China Relations: Right", "China Relations: Left",
  "Espionage Law: Right", "Espionage Law: Left",
  "Constitutional Amendment: Right", "Constitutional Amendment: Left",
  "Diet Seat Reduction: Right", "Diet Seat Reduction: Left",
  "Social Insurance: Right", "Social Insurance: Left",
  "Corporate Donations: Right", "Corporate Donations: Left",
  "Dual Surnames: Right", "Dual Surnames: Left",
  "Nuclear Power: Right", "Nuclear Power: Left"
))

# --- Party levels ---
cm_party_levels <- c(
  "LDP", "Centrist Reform", "Innovation", "DPP",
  "JCP", "Reiwa", "Sanseito", "Conservative",
  "SDP", "Team Mirai", "Tax Cut Coalition", "Refusal"
)

# --- Model levels and colors ---
model_levels <- c(
  "GPT-4o Mini", "GPT-5 Mini", "Gemini 2.5 Flash",
  "Grok 4.1 Fast (Web-only)", "Grok 4.1 Fast (Web+X)"
)

model_colors <- c(
  "GPT-4o Mini"              = "#2E3B51",
  "GPT-5 Mini"               = "#D4427E",
  "Gemini 2.5 Flash"         = "#B3DB7E",
  "Grok 4.1 Fast (Web-only)" = "#6651DF",
  "Grok 4.1 Fast (Web+X)"    = "#63D7F1"
)

# --- Party display labels ---
party_display <- c(
  "LDP"               = "LDP",
  "Centrist Reform"   = "Centrist Reform",
  "Innovation"        = "Innovation",
  "JCP"               = "Japan Communist Party",
  "DPP"               = "DPP",
  "Reiwa"             = "Reiwa",
  "Sanseito"          = "Sanseito",
  "Conservative"      = "Conservative",
  "SDP"               = "SDP",
  "Team Mirai"        = "Team Mirai",
  "Tax Cut Coalition" = "Tax Cut Coalition",
  "Refusal"           = "Refusal"
)

# --- Main parties for regression ---
cm_main_parties <- c("LDP", "Centrist Reform", "JCP")
cm_main_cols    <- make.names(cm_main_parties)

# --- Region factor levels ---
region_levels <- c(
  "Tokyo", "Hokkaido", "Tohoku", "Kita-Kanto", "Minami-Kanto",
  "Hokuriku-Shinetsu", "Tokai", "Kinki", "Chugoku", "Shikoku", "Kyushu"
)

# --- 2026 PR election results ---
pr_total_seats <- 176L

actual_pr_seats <- tribble(
  ~party,               ~seats,
  "LDP",                67L,
  "Centrist Reform",    42L,
  "Innovation",         16L,
  "DPP",                20L,
  "JCP",                4L,
  "Reiwa",              1L,
  "Sanseito",           15L,
  "Conservative",       0L,
  "SDP",                0L,
  "Team Mirai",         11L,
  "Tax Cut Coalition",  0L,
  "Refusal",            NA_integer_
) %>%
  mutate(seat_pct = round(seats / pr_total_seats * 100, 1))

# --- Common ggplot theme for publication ---
theme_pub <- function(base_size = 9) {
  theme_minimal(base_size = base_size) %+replace%
    theme(
      legend.position = "bottom",
      strip.text = element_text(face = "bold", size = base_size - 1),
      axis.text  = element_text(size = base_size - 2),
      legend.text = element_text(size = base_size - 1),
      plot.title = element_text(face = "bold", size = base_size + 1, hjust = 0)
    )
}

cat("00_constants.R loaded.\n")
