# check_coverage.R
# Optional check (not part of the pipeline): how much could DDInter's file layout
# bias drug degrees? Run from the project root after 03_build_network.R:
#   Rscript scripts/check_coverage.R
#
# Each DDInter file holds every interaction of the drugs in its ATC group. A drug
# whose pairs all appear in one common file belongs to that group, so its list is
# complete ("covered"). ~220 drugs have no group; pairs between two of them could
# be missing. We compare each drug's full degree with a degree counting only
# covered partners (which the gap cannot affect). If the two agree, the gap is
# negligible.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

files <- list.files("data/raw/ddinter", pattern = "^ddinter_downloads_code_.*\\.csv$",
                    full.names = TRUE)
raw <- bind_rows(lapply(files, function(f) {
  read_csv(f, col_types = cols(.default = col_character())) |>
    mutate(file = sub(".*code_(.)\\.csv$", "\\1", f))
}))

pairs <- raw |>
  filter(DDInterID_A != DDInterID_B) |>
  mutate(a = pmin(DDInterID_A, DDInterID_B), b = pmax(DDInterID_A, DDInterID_B)) |>
  group_by(a, b) |>
  summarise(files = list(unique(file)), .groups = "drop")

drug_pairs <- bind_rows(
  pairs |> transmute(id = a, partner = b, files),
  pairs |> transmute(id = b, partner = a, files)
)

coverage <- drug_pairs |>
  group_by(id) |>
  summarise(covered = length(Reduce(intersect, files)) > 0, degree_all = n(), .groups = "drop")

covered_ids <- coverage$id[coverage$covered]
coverage <- coverage |>
  left_join(drug_pairs |> filter(partner %in% covered_ids) |> count(id, name = "degree_covered"),
            by = "id") |>
  mutate(degree_covered = coalesce(degree_covered, 0L))

otc_ids <- read_csv("data/final/drugs.csv", show_col_types = FALSE) |>
  filter(group == "OTC") |>
  pull(id)
otc <- coverage |> filter(id %in% otc_ids)

message(sprintf("Drugs not fully covered: %d of %d", sum(!coverage$covered), nrow(coverage)))
message(sprintf("Correlation, full vs covered-only degree (all drugs): %.4f",
                cor(coverage$degree_all, coverage$degree_covered)))
message(sprintf("Rank correlation, %d OTC drugs: %.4f", nrow(otc),
                cor(otc$degree_all, otc$degree_covered, method = "spearman")))
message(sprintf("OTC drugs whose degree changes at all: %d", sum(otc$degree_all != otc$degree_covered)))
