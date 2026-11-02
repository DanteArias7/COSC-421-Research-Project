# 01_clean_ddinter.R
# Combines the DDInter files into one de-duplicated, undirected edge list.
#
# Input:  data/raw/ddinter/ddinter_downloads_code_*.csv
#         columns: DDInterID_A, Drug_A, DDInterID_B, Drug_B, Level
# Output: data/processed/ddinter_drugs.csv  (one row per DDInter drug)
#         data/processed/ddinter_edges.csv  (one row per unordered drug pair)

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

# Used only to pick the most severe level when a pair appears more than once.
# Edge weights for analysis are set in 03_build_network.R.
severity_levels <- c(Unknown = 0, Minor = 1, Moderate = 2, Major = 3)

files <- list.files("data/raw/ddinter", pattern = "^ddinter_downloads_code_.*\\.csv$",
                    full.names = TRUE)
stopifnot("No DDInter files found -- run scripts/00_download.R" = length(files) > 0)

raw <- bind_rows(lapply(files, read_csv, col_types = cols(.default = col_character())))
message(sprintf("Read %d rows from %d files", nrow(raw), length(files)))

unexpected <- setdiff(unique(raw$Level), names(severity_levels))
if (length(unexpected) > 0) stop("Unexpected Level values: ", paste(unexpected, collapse = ", "))

# ---- Drugs (nodes) -----------------------------------------------------------
drugs <- bind_rows(
  raw |> select(ddinter_id = DDInterID_A, name = Drug_A),
  raw |> select(ddinter_id = DDInterID_B, name = Drug_B)
) |>
  distinct()

# Each ID should have exactly one name; fail loudly if not.
dup_ids <- drugs |> count(ddinter_id) |> filter(n > 1)
if (nrow(dup_ids) > 0) stop("Some DDInter IDs have more than one name: ",
                            paste(head(dup_ids$ddinter_id), collapse = ", "))

# ---- Edges -------------------------------------------------------------------
# Put each pair in a fixed order (by ID) so A-B and B-A are the same edge,
# then collapse duplicates that appear across files, keeping the most severe level.
edges <- raw |>
  filter(DDInterID_A != DDInterID_B) |>
  mutate(
    id_numA = as.integer(str_remove(DDInterID_A, "^DDInter")),
    id_numB = as.integer(str_remove(DDInterID_B, "^DDInter")),
    from    = if_else(id_numA <= id_numB, DDInterID_A, DDInterID_B),
    to      = if_else(id_numA <= id_numB, DDInterID_B, DDInterID_A),
    rank    = severity_levels[Level]
  ) |>
  group_by(from, to) |>
  summarise(
    severity      = names(severity_levels)[max(rank) + 1],
    n_levels_seen = n_distinct(Level),        # >1 means the files disagreed
    .groups = "drop"
  )

# ---- Save + summary ----------------------------------------------------------
write_csv(drugs |> arrange(ddinter_id), "data/processed/ddinter_drugs.csv")
write_csv(edges |> select(from, to, severity), "data/processed/ddinter_edges.csv")

message(sprintf("Drugs: %d   Unique pairs: %d   (raw rows: %d)",
                nrow(drugs), nrow(edges), nrow(raw)))
message(sprintf("Pairs whose files disagreed on severity: %d", sum(edges$n_levels_seen > 1)))
print(count(edges, severity))
