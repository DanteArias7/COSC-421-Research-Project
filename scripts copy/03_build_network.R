# 03_build_network.R
# Builds the final, analysis-ready files the whole team works from.
#
# Input:  data/processed/drug_labels.csv, data/processed/ddinter_edges.csv
# Output: data/final/drugs.csv         one row per drug, 7 plain columns
#         data/final/interactions.csv  one row per interacting pair, with drug names
#         data/final/network.rds       the network to analyse (igraph; readRDS())

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(igraph)
})

# ---- Team decisions (record these in the methods section) --------------------
SEVERITY_WEIGHTS  <- c(Major = 3, Moderate = 2, Minor = 1)
INCLUDE_UNKNOWN   <- TRUE       # keep "Unknown"-severity edges?
UNKNOWN_WEIGHT    <- 1          # their weight, if kept
OTC_RULE          <- "otc_any"  # or "otc_single" (single-ingredient products only)
OTC_SYSTEMIC_ONLY <- TRUE       # TRUE: topical/eye/nasal/ear OTC products are put in
                                # their own "Excluded (topical OTC)" group

atc_names <- c(
  A = "Alimentary tract and metabolism", B = "Blood and blood forming organs",
  C = "Cardiovascular system", D = "Dermatologicals",
  G = "Genito-urinary system and sex hormones",
  H = "Systemic hormonal preparations", J = "Antiinfectives for systemic use",
  L = "Antineoplastic and immunomodulating agents", M = "Musculo-skeletal system",
  N = "Nervous system", P = "Antiparasitic products", R = "Respiratory system",
  S = "Sensory organs", V = "Various"
)

labels <- read_csv("data/processed/drug_labels.csv", show_col_types = FALSE)
weights <- c(SEVERITY_WEIGHTS, Unknown = UNKNOWN_WEIGHT)

edges <- read_csv("data/processed/ddinter_edges.csv", show_col_types = FALSE) |>
  filter(INCLUDE_UNKNOWN | severity != "Unknown") |>
  mutate(weight = unname(weights[severity]))

# ---- drugs.csv ---------------------------------------------------------------
deg <- bind_rows(edges |> transmute(id = from, weight), edges |> transmute(id = to, weight)) |>
  group_by(id) |>
  summarise(degree = n(), weighted_degree = sum(weight), .groups = "drop")

drugs <- labels |>
  inner_join(deg, by = c("ddinter_id" = "id")) |>   # drops drugs left with no edges
  mutate(
    is_otc = .data[[OTC_RULE]],
    local  = node_route %in% c("topical", "ophthalmic", "nasal", "otic")
  ) |>
  transmute(
    id = ddinter_id,
    name,
    group = case_when(
      is_otc & local & OTC_SYSTEMIC_ONLY ~ "Excluded (topical OTC)",
      is_otc                             ~ "OTC",
      TRUE                               ~ "Prescription"
    ),
    atc_group,
    atc_group_name = unname(atc_names[atc_group]),
    degree,
    weighted_degree
  ) |>
  arrange(name)

# ---- interactions.csv --------------------------------------------------------
id_to_name <- setNames(drugs$name, drugs$id)
interactions <- edges |>
  transmute(drug_a = id_to_name[from], drug_b = id_to_name[to], severity, weight) |>
  arrange(drug_a, drug_b)

# ---- network.rds -------------------------------------------------------------
# Largest connected piece only -- what eigenvector centrality and communities need.
# Vertices are labelled by drug name ("Ibuprofen", not an ID).
stopifnot("Drug names are not unique" = !anyDuplicated(drugs$name))
g <- graph_from_data_frame(interactions, directed = FALSE,
                           vertices = drugs |> select(name, everything()))
stopifnot(!any_multiple(g), !any_loop(g))
comp <- components(g)
g <- induced_subgraph(g, comp$membership == which.max(comp$csize))

dir.create("data/final", showWarnings = FALSE)
write_csv(drugs, "data/final/drugs.csv")
write_csv(interactions, "data/final/interactions.csv")
saveRDS(g, "data/final/network.rds")

# ---- Summary -----------------------------------------------------------------
message("drugs.csv: ", nrow(drugs), " drugs")
print(count(drugs, group))
message("interactions.csv: ", nrow(interactions), " pairs")
message(sprintf("network.rds: %d drugs, %d interactions (OTC drugs in it: %d of %d)",
                vcount(g), ecount(g), sum(V(g)$group == "OTC"), sum(drugs$group == "OTC")))
