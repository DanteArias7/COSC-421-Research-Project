# 00_download.R
# Downloads the raw data into data/raw/. Run from the project root:
#   Rscript scripts/00_download.R
# Raw files are never edited by hand -- all cleaning happens in later scripts.

options(timeout = 600)

# ---- DDInter 2.0 -------------------------------------------------------------
# DDInter publishes one file per ATC group (all 14). A pair appears in a file
# if at least one of its two drugs belongs to that group.
ddinter_codes <- c("A", "B", "C", "D", "G", "H", "J", "L", "M", "N", "P", "R", "S", "V")
ddinter_base  <- "https://ddinter2.scbdd.com/static/media/download/"

dir.create("data/raw/ddinter", recursive = TRUE, showWarnings = FALSE)
for (code in ddinter_codes) {
  fname <- sprintf("ddinter_downloads_code_%s.csv", code)
  dest  <- file.path("data/raw/ddinter", fname)
  if (!file.exists(dest)) {
    message("Downloading ", fname)
    download.file(paste0(ddinter_base, fname), dest, mode = "wb")
  }
}

# ---- Health Canada Drug Product Database ------------------------------------
# allfiles.zip = currently marketed products (what the proposal's OTC rule uses).
dpd_url  <- "https://www.canada.ca/content/dam/hc-sc/documents/services/drug-product-database/allfiles.zip"
dpd_zip  <- "data/raw/dpd/allfiles.zip"

dir.create("data/raw/dpd", recursive = TRUE, showWarnings = FALSE)
if (!file.exists(dpd_zip)) {
  message("Downloading DPD allfiles.zip")
  download.file(dpd_url, dpd_zip, mode = "wb")
}
unzip(dpd_zip, exdir = "data/raw/dpd/marketed")

# Record when the data was pulled (DPD is updated nightly, so cite this date).
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M %Z"), "data/raw/DOWNLOADED_ON.txt")
message("Done. Files in data/raw/")
