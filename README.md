# OTC Drug Interaction Network (COSC 421)

## Start here: the 3 files you need (`data/final/`)

| File | What it is | Use for |
|---|---|---|
| `drugs.csv` | One row per drug (1,971) | RQ1, RQ2 |
| `interactions.csv` | One row per interacting pair (234,981), with drug names | Browsing / checking |
| `network.rds` | The network to analyse: `g <- readRDS("data/final/network.rds")` | RQ3, RQ4 |

**`drugs.csv` columns**
- `name`: drug name
- `group`: `OTC` (49 OTC medicines people swallow), `Prescription` (everything not sold OTC
  in Canada, 1,889), or `Excluded (topical OTC)` (33 drugs only sold OTC as creams/shampoos/eye drops/nasal sprays, left out)
- `atc_group` / `atc_group_name`: what the drug treats (e.g. `C` = Cardiovascular system); blank
  if the drug isn't sold in Canada
- `degree`: how many drugs it interacts with
- `weighted_degree`: same, weighted by severity (Major = 3, Moderate = 2, Minor = 1, Unknown = 1)

**`network.rds`**: 1,959 drugs, 234,959 interactions, all 49 OTC drugs (the largest connected
piece; 12 isolated drugs dropped). Vertices are drug names; vertex attributes are the
`drugs.csv` columns; edge attributes are `severity` and `weight`.

## ATC groups

ATC (Anatomical Therapeutic Chemical) codes classify drugs by the body system they act on.
The `atc_group` column is the first letter of a drug's ATC code, taken from Health Canada.

| Code | Group | Drugs | OTC drugs | OTC examples |
|---|---|---|---|---|
| A | Alimentary tract and metabolism | 105 | 18 | omeprazole, loperamide, famotidine |
| B | Blood and blood forming organs | 69 | 1 | magnesium sulfate |
| C | Cardiovascular system | 95 | 1 | phenylephrine |
| D | Dermatologicals | 44 | 1 | mineral oil |
| G | Genito-urinary system and sex hormones | 46 | 1 | levonorgestrel |
| H | Systemic hormonal preparations (excl. sex hormones and insulins) | 28 | 0 | |
| J | Anti-infectives for systemic use | 103 | 1 | fluconazole |
| L | Antineoplastic and immunomodulating agents | 243 | 0 | |
| M | Musculo-skeletal system | 35 | 4 | ibuprofen, naproxen |
| N | Nervous system | 171 | 7 | acetaminophen, acetylsalicylic acid (aspirin) |
| P | Antiparasitic products, insecticides and repellents | 11 | 1 | pyrantel |
| R | Respiratory system | 56 | 12 | cetirizine, loratadine, dextromethorphan |
| S | Sensory organs | 44 | 1 | zinc sulfate |
| V | Various | 36 | 2 | methylene blue |
| (blank) | No ATC group: not sold in Canada | 885 | 0 | |
| **Total** | | **1,971** | **49** | |

- A (digestive) and R (respiratory/allergy) hold over half the OTC drugs (30 of 49).
- Drugs sold OTC only in combination products get the combination's code, e.g. pseudoephedrine
  is in N (via cold-medicine combinations) rather than R.
- The 885 drugs with no group can't be assigned to a group in RQ4.

## Limitations (for the report)
- `Prescription` includes drugs not sold in Canada at all (no ATC group) as DDInter is a international database.
- **OTC status and ATC groups come from Health Canada's Drug Product Database**, matched to DDInter
  by ingredient name (14 names matched by hand in `data/manual/manual_crosswalk.csv`).
- Data snapshot: DDInter A/B/D/H/L/P/R/V and Health Canada downloaded 2026-10-27; DDInter
  C/G/J/M/N/S downloaded 2026-10-29.

## What the scripts do (plain English)

You don't need to open the scripts to use the data; `data/final/` has it all. Each script does one job, run in order:

```
00 download → 01 clean interactions → 02 add OTC labels → 03 build final files
```

| Script | What it did | Result |
|---|---|---|
| `00_download.R` | Go to DDInter and Health Canada and save copies of their files. | 14 DDInter files + Health Canada database in `data/raw/` |
| `01_clean_ddinter.R` | Turn 14 messy files into one clean list of unique drug pairs (duplicates and A+B / B+A repeats removed, most severe level kept). | 1,971 drugs, 234,981 pairs |
| `02_clean_dpd.R` | Look up every drug in Health Canada's database and record whether it's sold OTC and what it treats (ATC group). | OTC + ATC label for each drug |
| `03_build_network.R` | Put it all together into the 3 files the team uses, with severity weights and interaction counts. | `drugs.csv`, `interactions.csv`, `network.rds` |


- `02_clean_dpd.R` is the longest because matching names is fiddly: "IBUPROFEN SODIUM" must
  match "Ibuprofen", "PYRILAMINE" must match "Mepyramine" (via the manual list), and
  "Diclofenac (topical)" mustn't inherit the label from diclofenac pills.
- The settings at the top of `03_build_network.R` are the team's decisions (severity weights,
  excluding topical OTC products). It's the only file anyone would normally edit.
- Who touches them: only the technical lead reruns them, when the data or a team decision
  changes. Everyone else uses `data/final/`.

---

## For the technical lead: rebuilding the data

Run from the project root, in order (requires readr, dplyr, stringr, tidyr, igraph):

```
Rscript scripts/00_download.R      # downloads DDInter 2.0 + Health Canada DPD -> data/raw/ (once)
Rscript scripts/01_clean_ddinter.R # merges DDInter files -> data/processed/ddinter_drugs.csv, ddinter_edges.csv
Rscript scripts/02_clean_dpd.R     # adds OTC + ATC labels -> data/processed/drug_labels.csv
Rscript scripts/03_build_network.R # -> data/final/ (the 3 team files)
```

Team decisions (severity weights, Unknown handling, OTC rule) are settings at the top of
`03_build_network.R`.

`data/processed/` holds intermediate files the team doesn't need. Two are useful for checking:
- `drug_labels.csv`: per drug, which Health Canada ingredient it matched (`dpd_names`), how
  (`match_method`), its route (`node_route`) and OTC flags
- `unmatched_otc_ingredients.csv`: OTC ingredients that matched no DDInter drug

Never edit data files by hand: fix a script or `data/manual/manual_crosswalk.csv` and rerun.

## Detailed data decisions
- **DDInter:** all 14 ATC-group files. Pairs appearing in several files (or as A-B and B-A) are
  merged, keeping the most severe level (the files never disagreed).
- **OTC rule:** a drug is OTC if any marketed human Health Canada product containing it has
  schedule "NON-PRESCRIPTION DRUGS", including combination products (`otc_any`). The stricter
  single-ingredient version (`otc_single`) misses classic OTC drugs sold only in combos
  (pseudoephedrine, doxylamine).
- **Routes:** DDInter has separate nodes per route (e.g. "Diclofenac" vs "Diclofenac (topical)").
  Bracketed topical/ophthalmic/nasal/otic nodes are labelled only from Health Canada products with
  that route; a bare name with such siblings is the systemic form; a bare name without siblings
  uses all routes. Disinfectant-only products are excluded.
- **Systemic OTC only:** drugs whose only OTC products are topical/eye/nasal/ear (33, e.g.
  Diclofenac (topical), Fluticasone (nasal), and ketoconazole, which is OTC only as Nizoral
  shampoo while DDInter's interactions are for the pills) form their own "Excluded (topical OTC)"
  group, since the project is about OTC medicines taken alongside prescriptions. Clotrimazole is
  excluded by hand (`TOPICAL_ONLY_OVERRIDE`): its only "oral" OTC products are kits pairing a
  fluconazole pill with clotrimazole cream. Turn off with `OTC_SYSTEMIC_ONLY <- FALSE`.
- **ATC code:** most common ATC among single-ingredient Canadian products for the drug's route,
  falling back to combination products (`atc_from_combo` in `drug_labels.csv`; only the group
  letter is reliable then). Blank for drugs not marketed in Canada.
- **Manual crosswalk:** 14 Health Canada -> DDInter name fixes in
  `data/manual/manual_crosswalk.csv`, with deliberately unmapped cases listed at the bottom.
- **Weights:** Major 3, Moderate 2, Minor 1, Unknown 1.
