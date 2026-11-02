# 02_clean_dpd.R
# Labels each DDInter drug with OTC status and an ATC code using Health Canada's
# Drug Product Database (marketed products), matching on ingredient name.
#
# Input:  data/raw/dpd/marketed/{drug,ingred,schedule,ther,route}.txt
#         data/processed/ddinter_drugs.csv          (from 01_clean_ddinter.R)
#         data/manual/manual_crosswalk.csv          (hand-made name fixes)
# Output: data/processed/drug_labels.csv            (one row per DDInter drug)
#         data/processed/unmatched_otc_ingredients.csv  (review these by hand!)
#
# OTC rule (from the proposal): a drug is OTC if ANY marketed human product
# containing it has schedule "NON-PRESCRIPTION DRUGS" (i.e. OTC). Two versions are kept:
#   otc_any    - counts combination products (e.g. low-dose codeine combos)
#   otc_single - counts single-ingredient products only (stricter)
#
# Route matters: DDInter has separate nodes like "Diclofenac" and "Diclofenac
# (topical)". A node with a route in brackets (topical/ophthalmic/nasal/otic) is
# only labelled from DPD products with that route; a bare name that HAS such
# siblings is treated as the systemic form; a bare name without siblings uses
# all routes. The same applies to the ATC code.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
})

dpd_dir <- "data/raw/dpd/marketed"

# DPD files have no header row; column names are from Health Canada's
# "Read file" documentation for the data extract.
dpd_cols <- list(
  drug = c("DRUG_CODE", "PRODUCT_CATEGORIZATION", "CLASS", "DRUG_IDENTIFICATION_NUMBER",
           "BRAND_NAME", "DESCRIPTOR", "PEDIATRIC_FLAG", "ACCESSION_NUMBER", "NUMBER_OF_AIS",
           "LAST_UPDATE_DATE", "AI_GROUP_NO", "CLASS_F", "BRAND_NAME_F", "DESCRIPTOR_F"),
  ingred = c("DRUG_CODE", "ACTIVE_INGREDIENT_CODE", "INGREDIENT", "INGREDIENT_SUPPLIED_IND",
             "STRENGTH", "STRENGTH_UNIT", "STRENGTH_TYPE", "DOSAGE_VALUE", "BASE",
             "DOSAGE_UNIT", "NOTES", "INGREDIENT_F", "STRENGTH_UNIT_F", "STRENGTH_TYPE_F",
             "DOSAGE_UNIT_F"),
  schedule = c("DRUG_CODE", "SCHEDULE", "SCHEDULE_F"),
  ther = c("DRUG_CODE", "TC_ATC_NUMBER", "TC_ATC", "TC_AHFS_NUMBER", "TC_AHFS",
           "TC_ATC_F", "TC_AHFS_F"),
  route = c("DRUG_CODE", "ROUTE_OF_ADMINISTRATION_CODE", "ROUTE_OF_ADMINISTRATION",
            "ROUTE_OF_ADMINISTRATION_F")
)

read_dpd <- function(table) {
  path <- file.path(dpd_dir, paste0(table, ".txt"))
  stopifnot("DPD files missing -- run scripts/00_download.R" = file.exists(path))
  df <- read_csv(path, col_names = FALSE, col_types = cols(.default = col_character()))
  names(df) <- dpd_cols[[table]][seq_len(ncol(df))]
  df |> mutate(across(everything(), str_squish))
}

drug     <- read_dpd("drug")
ingred   <- read_dpd("ingred")
schedule <- read_dpd("schedule")
ther     <- read_dpd("ther")
route    <- read_dpd("route")

message("DPD schedule values:")
print(count(schedule, SCHEDULE, sort = TRUE))

# ---- Name normalisation ------------------------------------------------------
# DPD writes e.g. "DIPHENHYDRAMINE HYDROCHLORIDE" or "DOXYCYCLINE (DOXYCYCLINE HYCLATE)";
# DDInter writes "Diphenhydramine". `key` is the lower-cased name with any
# bracketed part removed; `base` additionally drops trailing salt/hydrate words.
salt_words <- c("hydrochloride", "dihydrochloride", "hcl", "hydrobromide", "sulfate",
                "sulphate", "bisulfate", "maleate", "citrate", "tartrate", "bitartrate",
                "succinate", "fumarate", "mesylate", "besylate", "phosphate", "acetate",
                "sodium", "potassium", "calcium", "magnesium", "monohydrate", "dihydrate",
                "trihydrate", "hemihydrate", "sesquihydrate", "anhydrous", "hyclate",
                "bromide", "nitrate", "lactate", "gluconate", "propionate", "dipropionate",
                "valerate", "pamoate", "tromethamine", "disodium", "monosodium")

name_key <- function(x) {
  x |>
    str_to_lower() |>
    str_remove_all("\\(.*?\\)") |>
    str_replace_all("aluminium", "aluminum") |>
    str_replace_all("[^a-z0-9 \\-]", " ") |>
    str_squish()
}

name_base <- function(key) {
  vapply(key, function(k) {
    words <- str_split(k, " ")[[1]]
    # Strip salt words from the end, but always keep at least one word, so
    # "calcium carbonate" stays intact while "naproxen sodium" -> "naproxen".
    while (length(words) > 1 && words[length(words)] %in% salt_words) {
      words <- words[-length(words)]
    }
    paste(words, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

# ---- Product-level table (human products only) -------------------------------
products <- drug |>
  filter(CLASS == "Human") |>
  transmute(DRUG_CODE, n_ais = as.integer(NUMBER_OF_AIS)) |>
  left_join(
    schedule |>
      group_by(DRUG_CODE) |>
      # The extract labels OTC products "NON-PRESCRIPTION DRUGS" (older extracts used
      # "OTC"). "ETHICAL" (mostly IV fluids / hospital products) is not counted.
      summarise(is_otc_product = any(toupper(SCHEDULE) %in% c("OTC", "NON-PRESCRIPTION DRUGS")),
                schedules = paste(sort(unique(SCHEDULE)), collapse = ";"),
                .groups = "drop"),
    by = "DRUG_CODE"
  ) |>
  mutate(is_otc_product = coalesce(is_otc_product, FALSE))

# Route class per product. Disinfectant routes are dropped (not taken by people),
# so disinfectant-only products drop out of the analysis.
product_route <- route |>
  mutate(r = toupper(ROUTE_OF_ADMINISTRATION),
         route_class = case_when(
           str_starts(r, "DISINFECTANT") ~ NA_character_,
           r == "OPHTHALMIC" ~ "ophthalmic",
           r == "NASAL"      ~ "nasal",
           r == "OTIC"       ~ "otic",
           str_starts(r, "TOPICAL") | r %in% c("PERCUTANEOUS", "VAGINAL", "DENTAL") ~ "topical",
           TRUE ~ "systemic"
         )) |>
  filter(!is.na(route_class)) |>
  distinct(DRUG_CODE, route_class)

# ATC per product (one product can have several codes; keep the full 7-char ones).
product_atc <- ther |>
  filter(!is.na(TC_ATC_NUMBER), nchar(TC_ATC_NUMBER) >= 1) |>
  distinct(DRUG_CODE, TC_ATC_NUMBER)

# ---- Ingredient-level table --------------------------------------------------
ing_products <- ingred |>
  distinct(DRUG_CODE, INGREDIENT) |>
  inner_join(products, by = "DRUG_CODE") |>
  inner_join(product_route, by = "DRUG_CODE", relationship = "many-to-many") |>
  mutate(key = name_key(INGREDIENT))

# Most common ATC code among SINGLE-ingredient products, per ingredient
# (and optionally route); combination products carry combination ATC codes.
# Falls back to combination products for ingredients only sold in combos
# (e.g. pseudoephedrine) -- their code is a combo code, but the group letter holds.
most_common_atc <- function(df, ...) {
  df |>
    inner_join(product_atc, by = "DRUG_CODE", relationship = "many-to-many") |>
    distinct(DRUG_CODE, TC_ATC_NUMBER, n_ais, ...) |>
    count(..., single = n_ais == 1, TC_ATC_NUMBER) |>
    arrange(desc(single), desc(n)) |>
    group_by(...) |>
    slice(1) |>
    ungroup() |>
    transmute(..., atc_code = TC_ATC_NUMBER, atc_from_combo = !single)
}
ing_atc <- most_common_atc(ing_products, key)

# OTC flags + ATC per ingredient AND route class (used for labelling nodes).
dpd_ing_route <- ing_products |>
  group_by(key, route_class) |>
  summarise(otc_any    = any(is_otc_product),
            otc_single = any(is_otc_product & n_ais == 1),
            .groups = "drop") |>
  left_join(most_common_atc(ing_products, key, route_class), by = c("key", "route_class"))

dpd_ingredients <- ing_products |>
  group_by(key) |>
  summarise(
    dpd_names    = paste(sort(unique(INGREDIENT)), collapse = " | "),
    n_products   = n_distinct(DRUG_CODE),
    n_otc        = n_distinct(DRUG_CODE[is_otc_product]),
    otc_any      = any(is_otc_product),
    otc_single   = any(is_otc_product & n_ais == 1),
    .groups = "drop"
  ) |>
  left_join(ing_atc, by = "key") |>
  mutate(base = name_base(key))

# ---- Match DDInter drugs to DPD ingredients ----------------------------------
ddinter <- read_csv("data/processed/ddinter_drugs.csv", col_types = cols(.default = col_character())) |>
  mutate(key = name_key(name), base = name_base(key)) |>
  mutate(
    bracket = str_match(str_to_lower(name), "\\(([a-z ]+)\\)")[, 2],
    bracket = recode(bracket, topiclal = "topical"),   # typo in DDInter
    node_route = case_when(
      bracket %in% c("topical", "ophthalmic", "nasal", "otic") ~ bracket,
      TRUE ~ "systemic"
    )
  ) |>
  group_by(key) |>
  mutate(node_route = if_else(node_route == "systemic" & n() == 1, "any", node_route)) |>
  ungroup() |>
  select(-bracket)

crosswalk_path <- "data/manual/manual_crosswalk.csv"
crosswalk <- if (file.exists(crosswalk_path)) {
  read_csv(crosswalk_path, col_types = cols(.default = col_character()), comment = "#") |>
    filter(!is.na(dpd_ingredient), !is.na(ddinter_name)) |>
    transmute(dpd_key = name_key(dpd_ingredient), ddinter_key = name_key(ddinter_name))
} else {
  tibble(dpd_key = character(), ddinter_key = character())
}

# Each DPD ingredient is linked to at most one DDInter drug, trying in order:
#   1. manual crosswalk   2. exact key   3. DPD base = DDInter key   4. base = base
# Several DPD ingredients may link to the same DDInter drug (different salts);
# their OTC flags are combined with any().
links <- bind_rows(
  crosswalk |> transmute(dpd_key, ddinter_key, method = "1_manual"),
  dpd_ingredients |> inner_join(ddinter, by = "key", relationship = "many-to-many") |>
    transmute(dpd_key = key, ddinter_key = key, method = "2_exact"),
  dpd_ingredients |> inner_join(ddinter, by = c("base" = "key"), relationship = "many-to-many") |>
    transmute(dpd_key = key, ddinter_key = base, method = "3_dpd_salt_stripped"),
  dpd_ingredients |> inner_join(ddinter, by = "base", suffix = c("_dpd", "_dd"),
                                  relationship = "many-to-many") |>
    transmute(dpd_key = key_dpd, ddinter_key = key_dd, method = "4_both_salt_stripped")
) |>
  arrange(method) |>
  distinct(dpd_key, .keep_all = TRUE)

drug_labels <- ddinter |>
  # many-to-many: several DPD salts can link to one drug, and DDInter variants
  # that differ only in brackets (e.g. "Insulin human (...)") share a key.
  left_join(links, by = c("key" = "ddinter_key"), relationship = "many-to-many") |>
  left_join(dpd_ingredients |> select(key, dpd_names), by = c("dpd_key" = "key")) |>
  left_join(dpd_ing_route, by = c("dpd_key" = "key"), relationship = "many-to-many") |>
  mutate(route_ok = node_route == "any" | route_class == node_route) |>
  group_by(ddinter_id, name, node_route) |>
  summarise(
    in_dpd       = any(!is.na(dpd_key)),
    otc_any      = any(otc_any & route_ok, na.rm = TRUE),
    otc_single   = any(otc_single & route_ok, na.rm = TRUE),
    # ATC from a route-matched product: single-ingredient codes first, then the
    # closest name match.
    best           = list(order(atc_from_combo, method)[route_ok[order(atc_from_combo, method)] %in% TRUE &
                                                        !is.na(atc_code[order(atc_from_combo, method)])]),
    atc_from_combo = atc_from_combo[best[[1]][1]],
    atc_code       = atc_code[best[[1]][1]],
    match_method = paste(sort(unique(na.omit(method))), collapse = ";"),
    dpd_names    = paste(unique(na.omit(dpd_names)), collapse = " | "),
    .groups = "drop"
  ) |>
  select(-best) |>
  mutate(
    atc_code   = na_if(atc_code, ""),
    atc_group  = str_sub(atc_code, 1, 1),
    match_method = na_if(match_method, "")
  )

write_csv(drug_labels, "data/processed/drug_labels.csv")

# OTC ingredients that never matched a DDInter drug. Some are genuinely absent
# from DDInter (vitamins, sunscreens...), others need a manual_crosswalk row.
unmatched_otc <- dpd_ingredients |>
  filter(otc_any, !key %in% links$dpd_key) |>
  arrange(desc(n_otc)) |>
  select(dpd_names, key, base, n_otc, otc_single, atc_code)
write_csv(unmatched_otc, "data/processed/unmatched_otc_ingredients.csv")

# ---- Summary -----------------------------------------------------------------
message(sprintf("DDInter drugs: %d | matched to DPD: %d | OTC (any): %d | OTC (single): %d | with ATC: %d",
                nrow(drug_labels), sum(drug_labels$in_dpd), sum(drug_labels$otc_any),
                sum(drug_labels$otc_single), sum(!is.na(drug_labels$atc_code))))
message(sprintf("OTC DPD ingredients not matched to DDInter: %d (see data/processed/unmatched_otc_ingredients.csv)",
                nrow(unmatched_otc)))
print(count(links, method))
