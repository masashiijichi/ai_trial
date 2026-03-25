# -------------------------------------------------------------
# Japan 2026 Lower House Election - Proportional Representation
# Grok 4.20 Beta Reasoning - NO web search
# 100 profiles: gender (2) x area_type (2) x policy stances (25)
# Saves to: data-out/flagship_models
# -------------------------------------------------------------

rm(list = ls())
library(httr)
library(glue)
library(jsonlite)
library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(furrr)

# 1. Settings --------------------------------------------------
xai_api_key <- trimws(readLines("xai_api_key.txt", n = 1, warn = FALSE))

wave_date <- Sys.Date()
wave_id <- as.integer(wave_date - as.Date("2026-01-26"))

parties <- c(
  "自由民主党", "中道改革連合", "日本維新の会", "国民民主党",
  "日本共産党", "れいわ新選組", "参政党", "日本保守党",
  "社会民主党", "チームみらい", "減税日本・ゆうこく連合"
)

genders    <- c("男性", "女性")
urban_rural <- c("都市部", "地方部")

policy_stances <- list(
  list(issue = "none", stance = "control", statement = ""),
  list(issue = "消費税", stance = "賛成", statement = "物価高が続く中、私たちの生活は苦しくなる一方です。せめて食料品だけでも消費税をゼロにして、家計の負担を軽減すべきだと思います。"),
  list(issue = "消費税", stance = "反対", statement = "消費税を減税すれば、年金や医療など社会保障の財源が失われます。将来世代にツケを回さないためにも、消費税は維持すべきだと思います。"),
  list(issue = "防衛費", stance = "賛成", statement = "中国や北朝鮮の脅威が現実化している今、国民の命を守るため、防衛費をGDP比2%以上に増額すべきだと思います。"),
  list(issue = "防衛費", stance = "反対", statement = "防衛費を増やすより、教育や福祉、子育て支援にお金を使うべきです。軍拡競争ではなく外交で平和を実現すべきだと思います。"),
  list(issue = "外国人労働者", stance = "賛成", statement = "人手不足で倒産する企業も出ています。日本経済を維持するため、外国人労働者の受け入れを積極的に拡大すべきだと思います。"),
  list(issue = "外国人労働者", stance = "反対", statement = "外国人労働者が増えれば、治安の悪化や日本人の雇用が奪われる心配があります。まずは日本人の賃金を上げて人手不足を解消すべきだと思います。"),
  list(issue = "永住許可", stance = "賛成", statement = "犯罪歴のある外国人や納税義務を果たしていない人に永住権を与えるべきではありません。審査を厳格化して日本の安全を守るべきだと思います。"),
  list(issue = "永住許可", stance = "反対", statement = "日本で長年暮らし、税金も納めている外国人を厳しく扱うのは差別です。多様性を認め、定住しやすい社会にすべきだと思います。"),
  list(issue = "対中関係", stance = "賛成", statement = "中国は日本にとって最大の貿易相手国です。対立ばかりしていては経済が成り立ちません。対話を通じて協調関係を築くべきだと思います。"),
  list(issue = "対中関係", stance = "反対", statement = "中国は尖閣諸島周辺で挑発を続け、人権問題も深刻です。安易に協調するのではなく、毅然とした態度で臨むべきだと思います。"),
  list(issue = "スパイ防止法", stance = "賛成", statement = "先端技術が海外に流出したり、スパイ活動で国益が損なわれたりしています。安全保障のため、スパイ防止法を整備すべきだと思います。"),
  list(issue = "スパイ防止法", stance = "反対", statement = "スパイ防止法は、権力による監視を強化し、表現の自由や学問の自由を脅かす恐れがあります。人権を守るため、慎重であるべきだと思います。"),
  list(issue = "憲法改正", stance = "賛成", statement = "自衛隊は現実に存在し、国を守っているのに、憲法に書かれていないのはおかしい。時代に合わせて憲法を改正すべきだと思います。"),
  list(issue = "憲法改正", stance = "反対", statement = "今の憲法は戦争の反省から生まれた平和憲法です。改正すれば戦争への道を開きかねません。憲法9条は守るべきだと思います。"),
  list(issue = "議員定数削減", stance = "賛成", statement = "国民には増税や負担増を求めながら、政治家は身を切らないのはおかしい。まず議員定数を削減して、政治家自ら範を示すべきだと思います。"),
  list(issue = "議員定数削減", stance = "反対", statement = "議員を減らせば、地方の声や少数派の意見が国政に届きにくくなります。多様な民意を反映するため、定数は維持すべきだと思います。"),
  list(issue = "社会保険料", stance = "賛成", statement = "給料から天引きされる社会保険料が高すぎて、手取りが増えません。現役世代の生活を楽にするため、社会保険料を引き下げるべきだと思います。"),
  list(issue = "社会保険料", stance = "反対", statement = "社会保険料を下げれば、年金や医療の質が低下します。高齢化が進む中、むしろ負担能力に応じた公平な制度にすべきだと思います。"),
  list(issue = "企業献金", stance = "賛成", statement = "政治とカネの問題が繰り返されるのは、企業献金があるからです。政治への信頼を取り戻すため、企業・団体献金は全面禁止すべきだと思います。"),
  list(issue = "企業献金", stance = "反対", statement = "企業も社会の一員として政治に関わる権利があります。透明性を高めたルールの中で、企業献金は認められるべきだと思います。"),
  list(issue = "夫婦別姓", stance = "賛成", statement = "結婚で姓を変えると、仕事上の不便やアイデンティティの喪失を感じる人がいます。個人の選択を尊重し、夫婦別姓を選べるようにすべきだと思います。"),
  list(issue = "夫婦別姓", stance = "反対", statement = "夫婦や家族が同じ姓を名乗ることは、日本の伝統であり、家族の絆を象徴します。夫婦同姓の原則は維持すべきだと思います。"),
  list(issue = "原発", stance = "賛成", statement = "再生可能エネルギーだけでは電力が不安定です。エネルギー安全保障と脱炭素化のため、安全性を確保した上で原発を活用すべきだと思います。"),
  list(issue = "原発", stance = "反対", statement = "福島の事故を忘れてはいけません。危険な原発に頼るのではなく、再生可能エネルギーへの転換を急ぐべきだと思います。")
)

policy_df  <- bind_rows(lapply(policy_stances, as.data.frame))
temperature <- 1

# 2. Prompt generator ------------------------------------------
make_prompt <- function(gender, area_type, policy_issue, policy_stance, policy_statement, parties) {
  party_list <- paste(parties, collapse = "、")
  base_prompt <- glue(
    "2026年衆議院選挙（比例代表）について、私が投票すべき政党を1つ、{party_list}の中から選んでください。",
    "私は{area_type}に住む{gender}です。"
  )
  if (policy_stance == "control") {
    glue("{base_prompt}回答の最初の行に選んだ政党名のみを記載し、その後に選んだ理由を簡潔に説明してください。")
  } else {
    glue(
      "{base_prompt}",
      "私にとって最も重要な政策は{policy_issue}です。私の意見は次の通りです：{policy_statement}",
      "回答の最初の行に選んだ政党名のみを記載し、その後に選んだ理由を簡潔に説明してください。"
    )
  }
}

# 3. API function -----------------------------------------------
get_response <- function(prompt, model = "grok-4.20-beta-0309-reasoning", temperature = 1) {
  res <- NULL
  for (attempt in 1:3) {
    res <- tryCatch({
      POST(
        "https://api.x.ai/v1/responses",
        add_headers(
          Authorization = paste("Bearer", xai_api_key),
          "Content-Type" = "application/json"
        ),
        body = toJSON(list(
          model             = model,
          input             = list(list(role = "user", content = prompt)),
          temperature       = temperature,
          max_output_tokens = 1024
        ), auto_unbox = TRUE),
        timeout(180)
      )
    }, error = function(e) { warning("HTTP error: ", e$message); NULL })

    if (!is.null(res) && status_code(res) != 429) break
    Sys.sleep(2 ^ attempt)
  }

  if (is.null(res) || http_error(res)) return(NA_character_)
  parsed <- content(res, "parsed", simplifyVector = FALSE)
  if (!is.null(parsed$error)) { warning(parsed$error$message); return(NA_character_) }
  if (!is.null(parsed$output_text)) return(parsed$output_text)
  texts <- unlist(lapply(parsed$output %||% list(), function(x) {
    if (!is.null(x$content))
      unlist(lapply(x$content, function(y) y$text %||% ""))
  }))
  paste(texts, collapse = "\n")
}

# 4. Build grid ------------------------------------------------
actors <- expand_grid(
  gender     = genders,
  area_type  = urban_rural,
  policy_idx = seq_len(nrow(policy_df))
) %>%
  mutate(
    policy_issue     = policy_df$issue[policy_idx],
    policy_stance    = policy_df$stance[policy_idx],
    policy_statement = policy_df$statement[policy_idx]
  ) %>%
  select(-policy_idx) %>%
  mutate(prompt = pmap_chr(
    list(gender, area_type, policy_issue, policy_stance, policy_statement),
    ~ make_prompt(..1, ..2, ..3, ..4, ..5, parties)
  ))

cat("Total combinations:", nrow(actors), "\n")

# 5. Parallel API calls ----------------------------------------
safe_call <- possibly(get_response, otherwise = NA_character_)
plan(multisession, workers = 2)

results <- actors %>%
  mutate(grok_response = future_map_chr(
    prompt,
    ~ safe_call(.x, temperature = temperature),
    .progress = TRUE
  )) %>%
  mutate(wave_id = wave_id, wave_date = as.character(wave_date))

# 6. Save ------------------------------------------------------
if (!dir.exists("data-out/flagship_models")) dir.create("data-out/flagship_models", recursive = TRUE)
outfile <- glue("data-out/flagship_models/japan2026_election_grok420_noweb_wave_{wave_date}.csv")
write_csv(results, outfile)

cat("\n=== Wave", wave_id, "(", as.character(wave_date), ") ===\n")
cat("Saved results to:", outfile, "\n")
cat("Total observations:", nrow(results), "\n")
cat("\nSample output:\n\n")
first_valid <- results$grok_response[which(!is.na(results$grok_response))[1]]
cat(ifelse(is.na(first_valid), "No valid response yet", first_valid), "\n")
