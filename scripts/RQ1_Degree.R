# RQ1_Degree.R

# RQ1: Do OTC drugs have more or fewer interactions than prescription drugs?

setwd("/Users/aaronhong/Documents/COSC-421-Research-Project")
d <- read.csv("data/final/drugs.csv")

d <- d[d$group %in% c("OTC", "Prescription"), ]
aggregate(degree ~ group, d, function(x) c(n = length(x), mean = mean(x), median = median(x)))
boxplot(degree ~ group, d, ylab = "Number of interactions")
wilcox.test(degree ~ group, d)

