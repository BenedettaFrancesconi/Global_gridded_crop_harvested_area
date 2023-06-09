# Cropland validation
# Compare the distribution of cropland within each country in GAEZ+_2015 to HYDE 2015

# Danielle S Grogan
# 2021-01

##################################################################################################################
### LIBRARIES AND SOURCE FILES ###
library(ggplot2)
library(raster)
library(rgdal)
library(rgeos)
library(RColorBrewer)
library(gridExtra)
library(grid)
library(tidyr)
library("ggplotify")

##################################################################################################################
### Linear regression: summary tables and plots ###

lr.summary = function(h.data, g.data, sp.name, varname){
  out.table = data.frame(matrix(nr=1, nc=6))
  colnames(out.table) = c("spatial_unit", 
                          "R2", "slope", "signif", "sigma", "RMSE")
  out.table$spatial_unit = sp.name
  
  df = as.data.frame(merge(h.data, g.data, by = "sp_ID"))
  colnames(df)[2:3] = c("hyde", "gaez")
  
  s = summary(lm(df$gaez ~ df$hyde))
  
  out.table$R2     = s$r.squared
  out.table$slope  = s$coefficients[2,1]
  out.table$signif = s$coefficients[2,4]
  out.table$sigma  = s$sigma
  out.table$RMSE = sqrt(mean(s$residuals^2, na.rm=T))
  
  out.table
}

##################################################################################################################
### Calculate GAEZ+ 2015 maximum physical cropland area extent based on harvested area ###
##################################################################################################################

# p = "path to GAEZ+_2015 Annual Harvest Area data".  This data can be downloaded from: https://doi.org/10.7910/DVN/KAGRFI

all.files = dir(p, pattern = "GAEZAct2015", full.names = T)
irr.files = subset(all.files, grepl("Irrigated", all.files))
rfd.files = subset(all.files, grepl("Rainfed", all.files))

irr.harv.brk = do.call(stack,
                       lapply(irr.files, raster))  # unit: 1000 ha 

rfd.harv.brk = do.call(stack,
                       lapply(rfd.files, raster))  # unit: 1000 ha 

irr.harv.sum = stackApply(irr.harv.brk, indices = rep(1, nlayers(irr.harv.brk)), fun=sum)
rfd.harv.sum = stackApply(rfd.harv.brk, indices = rep(1, nlayers(rfd.harv.brk)), fun=sum)

cell.area = raster::area(irr.harv.sum)  # unit: km2
cell.area.1000ha = cell.area/10         # unit: 1000 ha

# take the minimum of harvested area and cell area
irr.stack = stack(irr.harv.sum, cell.area.1000ha)
min.irr = stackApply(irr.stack, indices=c(1,1), fun=min)

rfd.stack = stack(rfd.harv.sum, cell.area.1000ha)
min.rfd = stackApply(rfd.stack, indices=c(1,1), fun=min)

# total cropland
cropland = min.irr + min.rfd
crop.stack = stack(cropland, cell.area.1000ha)
max.cropland = stackApply(crop.stack, indices=c(1,1), fun=min)   # unit: 1000 ha
cropland.sum = sum(as.matrix(max.cropland), na.rm=T)*10 # unit:km2 

# write maximum cropland extent total to file
writeRaster(max.cropland, "results/cropland_max_km2.tif", format = "GTiff", overwrite=T)

##################################################################################################################
### Cropland Data to Aggregate ###
##################################################################################################################

# hyde.path = "path to HYDE v3.2 data"  download data from: https://dataportaal.pbl.nl/downloads/HYDE/
# gaez.path = "path to GAEZ+2015 crop physical area data"  download data from: https://doi.org/10.13019/J2BH-VB41

# total cropland (alternative calculation)
cropland.g = raster("results/cropland_max_km2.tif")               # GEAZ physical cropland, in km2 
cropland.h = raster(file.path(hyde.path, "cropland2015AD.asc"))   # HYDE physical cropland, km2

# irrigated land
irr.g.frac = raster(file.path(gaez.path, "GAEZ_Irrigated.tif "))  # gaez irrigated land, fraction of grid cell
irr.g = raster::area(irr.g.frac) * irr.g.frac                     # gaez cropland, km2
irr.h = raster(file.path(hyde.path, "tot_irri2015AD.asc"))        # HYDE irrigated land, km2

# rainfed land
rfd.g.frac = raster(file.path(gaez.path, "GAEZ_Rainfed.tif "))  # gaez cropland, fraction of grid cell
rfd.g = raster::area(rfd.g.frac) * rfd.g.frac                   # gaez cropland, km2
rfd.h = raster(file.path(hyde.path, "tot_rainfed2015AD.asc"))   # HYDE cropland, km2

# rice_irr
rice_irr.g = raster(file.path(gaez.path, "/GAEZ_Rice_Irrigated.tif"))*10  # gaez irr rice, x10 to convert from 1000ha to km2
rice_irr.h = raster(file.path(hyde.path, "ir_rice2015AD.asc"))   # HYDE irr rice, km2

# rice_rfd
rice_rfd.g = raster(file.path(gaez.path, "GAEZ_Rice_Rainfed.tif"))*10  # gaez irr rice, x10 to convert from 1000ha to km2
rice_rfd.h = raster(file.path(hyde.path, "rf_rice2015AD.asc"))   # HYDE irr rice, km2


# stack data for efficient extraction & aggregation
gaez.stack = stack(cropland.g, irr.g, rfd.g, rice_irr.g, rice_rfd.g)
hyde.stack = stack(cropland.h, irr.h, rfd.h, rice_irr.h, rice_rfd.h)
names(gaez.stack) = names(hyde.stack) = c("cropland", "irr", "rfd", "rice_irr", "rice_rfd")

##################################################################################################################
### Spatial data ###
##################################################################################################################
# Administrative unit boundaries can be downloaded from: 
#     Urbano,  Ferdinando (2018):  Global  administrative  boundaries.  
#     European  Commission,  Joint  Research  Centre  (JRC)[Dataset] 
#     PID: http://data.europa.eu/89h/jrc-10112-10004

# Subbasins are derived from the Hydrosheds 5-minute data product:
#   Lehner B, Verdin K, Jarvis A. 2008. New global hydrography derived from spaceborne elevation data. 
#   Eos, Transactions, AGU, 89(10): 93-94.
# subbasins are the result of the code watershed_regions.pl (available in github repository wsag/GAEZ-_2015_code)


# Subbasins
subbasins.poly = readOGR(dsn="data/subbasins", layer="subbasins")
sp.area = raster::area(subbasins.poly)*1e-6 
subbasins.poly$area = sp.area

# administrative units
admin = readOGR(dsn="data/gaul1_asap/", layer="gaul1_asap")
sp.area = raster::area(admin)*1e-6 
admin$area = sp.area

##################################################################################################################
### Spatial aggregation ###
##################################################################################################################

aggregate_stack = function(stk, shp, shp.nm, csv.nm){
  
  # aggregate
  agg.g = raster::extract(stk, shp, fun=sum, na.rm=T, sp=T)
  
  # normalize by area
  cropland.norm = agg.g$cropland / agg.g$area
  irr.norm      = agg.g$irr      / agg.g$area
  rfd.norm      = agg.g$rfd      / agg.g$area
  rice_irr.norm = agg.g$rice_irr / agg.g$area
  rice_rfd.norm = agg.g$rice_rfd / agg.g$area
  
  agg.g$crop.norm      = cropland.norm
  agg.g$irr.norm       = irr.norm
  agg.g$rfd.norm       = rfd.norm
  agg.g$rice_irr.norm  = rice_irr.norm
  agg.g$rice_rfd.norm  = rice_rfd.norm
  
  # save shapefile
  writeOGR(agg.g, 
           dsn   = paste("data/", shp.nm, sep=""), 
           layer = shp.nm, 
           driver="ESRI Shapefile", 
           overwrite_layer = T)
  
  # save to csv
  write.csv(agg.g@data, paste("results/cropland_validation/", csv.nm, sep=""), row.names=F)
}

##################################################################################################################

### Subbasins ###
# GAEZ
aggregate_stack(stk    = gaez.stack, 
                shp    = subbasins.poly, 
                shp.nm = "subbasins_gaez_norm", 
                csv.nm = "subbasins_gaez_norm.csv")

# HYDE
aggregate_stack(stk    = hyde.stack, 
                shp    = subbasins.poly, 
                shp.nm = "subbasins_hyde_norm", 
                csv.nm = "subbasins_hyde_norm.csv")


### Admin ###
# GAEZ
aggregate_stack(stk    = gaez.stack, 
                shp    = admin, 
                shp.nm = "admin1_gaez_norm", 
                csv.nm = "admin1_gaez_norm.csv")

# HYDE
aggregate_stack(stk    = hyde.stack, 
                shp    = admin, 
                shp.nm = "admin1_hyde_norm", 
                csv.nm = "admin1_hyde_norm.csv")


##################################################################################################################
### Linear validation of aggregated data ###
##################################################################################################################

var.longnm = c("cropland.km2", 
               "irrland.km2", 
               "rfdland.km2", 
               "rice_irr.km2", 
               "rice_rfd.km2")

# Subbasins
sub.g = readOGR("data/subbasins_gaez_norm/", "subbasins_gaez_norm")
sub.h = readOGR("data/subbasins_hyde_norm/", "subbasins_hyde_norm")

# loop through stack layers
val.summary = as.data.frame(matrix(nr=length(var.longnm), nc=7))
val.summary[,1] = var.longnm
colnames(val.summary) = c("variable", 
                          "spatial_unit", 
                          "R2", "slope", "signif", "sigma", "RMSE")
for(i in 3:7){
  g.data =  as.data.frame(cbind(sub.g$h__5__S, sub.g@data[,i]))
  h.data =  as.data.frame(cbind(sub.h$h__5__S, sub.h@data[,i]))
  colnames(g.data)[1] = colnames(h.data)[1] = "sp_ID"
  val.summary[i-2, 2:7] = lr.summary(h.data, g.data, sp.name = "subbasin", varname = var.longnm[i-2])
}
# unit conversion: from km2 to million ha
unit_conv = 100*1e-6
val.summary$RMSE.Mha = val.summary$RMSE*unit_conv
write.csv(val.summary, "results/cropland_validation/Subbasin_GAEZ_HYDE_validation_summary.csv")


# Admin
sub.g = readOGR("data/admin1_gaez_norm/", "admin1_gaez_norm")
sub.h = readOGR("data/admin1_hyde_norm/", "admin1_hyde_norm")

# loop through stack layers
val.summary = as.data.frame(matrix(nr=length(var.longnm), nc=7))
val.summary[,1] = var.longnm
colnames(val.summary) = c("variable", 
                          "spatial_unit", 
                          "R2", "slope", "signif", "sigma", "RMSE")
for(i in 14:18){
  g.data =  as.data.frame(cbind(sub.g$asap1_d, sub.g@data[,i]))
  h.data =  as.data.frame(cbind(sub.h$asap1_d, sub.h@data[,i]))
  colnames(g.data)[1] = colnames(h.data)[1] = "sp_ID"
  val.summary[i-13, 2:7] = lr.summary(h.data, g.data, sp.name = "admin1", varname = var.longnm[i-13])
}
# unit conversion: from km2 to million ha
unit_conv = 100*1e-6
val.summary$RMSE.Mha = val.summary$RMSE*unit_conv
write.csv(val.summary, "results/cropland_validation/Admin1_GAEZ_HYDE_validation_summary.csv")


# Grid cell
val.summary = as.data.frame(matrix(nr=length(var.longnm), nc=7))
val.summary[,1] = var.longnm
colnames(val.summary) = c("variable", 
                          "spatial_unit", 
                          "R2", "slope", "signif", "sigma", "RMSE")

for(i in 1:5){
  g.data = as.data.frame(cbind( seq(from = 1, 
                                    to   = length(values(subset(gaez.stack, i)))), 
                                values(subset(gaez.stack, i))))
  h.data = as.data.frame(cbind( seq(from = 1, 
                                    to   = length(values(subset(hyde.stack, i)))), 
                                values(subset(hyde.stack, i))))
  colnames(g.data)[1] = colnames(h.data)[1] = "sp_ID"
  
  val.summary[i, 2:7] = lr.summary(h.data, g.data, sp.name = "grid_cell", varname = var.longnm[i])
}
# unit conversion: from km2 to 1,000 ha (NOTE: This is a different unit than above)
unit_conv = 100*1e-3
val.summary$RMSE.1000ha = val.summary$RMSE*unit_conv
write.csv(val.summary, "results/cropland_validation/GridCell_GAEZ_HYDE_validation_summary.csv")

##################################################################################################################
### Plots ###
##################################################################################################################

# Subbasins
sub.g = readOGR("data/subbasins_gaez_norm/", "subbasins_gaez_norm")
sub.h = readOGR("data/subbasins_hyde_norm/", "subbasins_hyde_norm")

# Admin
adm.g = readOGR("data/admin1_gaez_norm/", "admin1_gaez_norm")
adm.h = readOGR("data/admin1_hyde_norm/", "admin1_hyde_norm")

### Combine into large, long-format data frame
# unit conversion: from km2 to million ha
unit_conv = 100*1e-6

# subbasins, GAEZ
sub.g.wide = as.data.frame(cbind(sub.g$h__5__S, 
                                 unit_conv*sub.g$croplnd, 
                                 unit_conv*sub.g$irr, 
                                 unit_conv*sub.g$rfd, 
                                 unit_conv*as.numeric(sub.g$rice_rr), 
                                 unit_conv*as.numeric(sub.g$ric_rfd)))
colnames(sub.g.wide) = c("unit_ID", 
                         "Cropland", "Irrigated", "Rainfed", 
                         "Irrigated Rice", "Rainfed Rice")
sub.g.long = gather(data = sub.g.wide, 
                    key = "variable",
                    value = "GAEZ (Mha)", 
                    "Cropland":"Rainfed Rice")
sub.g.long$sp_unit = "Basin"


# subbasins, HYDE
sub.h.wide = as.data.frame(cbind(sub.h$h__5__S, 
                                 unit_conv*sub.h$croplnd, 
                                 unit_conv*sub.h$irr, 
                                 unit_conv*sub.h$rfd,
                                 unit_conv*sub.h$rice_rr,
                                 unit_conv*sub.h$ric_rfd))
colnames(sub.h.wide) =c("unit_ID", 
                        "Cropland", "Irrigated", "Rainfed", 
                        "Irrigated Rice", "Rainfed Rice")
sub.h.long = gather(data = sub.h.wide, 
                    key = "variable",
                    value = "HYDE (Mha)", 
                    "Cropland":"Rainfed Rice")
sub.h.long$sp_unit = "Basin"


# Admin, GAEZ
adm.g.wide = as.data.frame(cbind(adm.g$asap1_d, 
                                 unit_conv*adm.g$croplnd, 
                                 unit_conv*adm.g$irr, 
                                 unit_conv*adm.g$rfd,
                                 unit_conv*adm.g$rice_rr,
                                 unit_conv*adm.g$ric_rfd))
colnames(adm.g.wide) =c("unit_ID", 
                        "Cropland", "Irrigated", "Rainfed", 
                        "Irrigated Rice", "Rainfed Rice")
adm.g.long = gather(data = adm.g.wide, 
                    key = "variable",
                    value = "GAEZ (Mha)", 
                    "Cropland":"Rainfed Rice")
adm.g.long$sp_unit = "Administrative"


# Admin, HYDE
adm.h.wide = as.data.frame(cbind(adm.h$asap1_d, 
                                 unit_conv*adm.h$croplnd, 
                                 unit_conv*adm.h$irr, 
                                 unit_conv*adm.h$rfd,
                                 unit_conv*adm.h$rice_rr,
                                 unit_conv*adm.h$ric_rfd))
colnames(adm.h.wide) =c("unit_ID", 
                        "Cropland", "Irrigated", "Rainfed", 
                        "Irrigated Rice", "Rainfed Rice")
adm.h.long = gather(data = adm.h.wide, 
                    key = "variable",
                    value = "HYDE (Mha)", 
                    "Cropland":"Rainfed Rice")
adm.h.long$sp_unit = "Administrative"



# Grid Cell, GAEZ
km2_to_1000ha = 100/1000
gcell.g.wide = as.data.frame(cbind(seq(1:nrow(values(gaez.stack))), km2_to_1000ha*values(gaez.stack)))
colnames(gcell.g.wide) =c("unit_ID", 
                          "Cropland", "Irrigated", "Rainfed", 
                          "Irrigated Rice", "Rainfed Rice")
gcell.g.long = gather(data = gcell.g.wide, 
                      key = "variable",
                      value = "GAEZ (1000 ha)", 
                      "Cropland":"Rainfed Rice")
gcell.g.long$sp_unit = "Grid Cell"

# Grid Cell, Hyde
gcell.h.wide = as.data.frame(cbind(seq(1:nrow(values(hyde.stack))), km2_to_1000ha*values(hyde.stack)))
colnames(gcell.h.wide) =c("unit_ID", 
                          "Cropland", "Irrigated", "Rainfed", 
                          "Irrigated Rice", "Rainfed Rice")
gcell.h.long = gather(data = gcell.h.wide, 
                      key = "variable",
                      value = "HYDE (1000 ha)", 
                      "Cropland":"Rainfed Rice")
gcell.h.long$sp_unit = "Grid Cell"

# merge GAEZ
gaez.all = rbind(sub.g.long, adm.g.long)

# merge HYDE
hyde.all = rbind(sub.h.long, adm.h.long)

# merge both
df = merge(gaez.all, hyde.all)

#####################################################################################
### FIGURE 7

df.allCrops = subset(df, df$variable %in% c("Cropland", "Irrigated", "Rainfed"))
p <- ggplot(data = df.allCrops, aes(x = `HYDE (Mha)`, y = `GAEZ (Mha)`)) +
  geom_point(size=0.5) +
  geom_smooth(method = "lm", formula = y ~ x) +
  geom_abline(slope=1, intercept=0, color='grey', lwd=0.4)+
  theme_light(base_size = 14) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0))
p1 = p + facet_grid(variable ~ sp_unit)
p1
ggsave(paste("results/figures/cropland_validation/GAEZ_vs_HYDE_allCropland_agg_panels.png", sep=""),
       plot = p1,
       width = 6, height = 6, units = "in",
       dpi = 300)
write.csv(df.allCrops, "results/cropland_validation/GAEZ_vs_HYDE_allCropland_data.csv")

#####################################################################################
### FIGURE 8

# make separate panel for rice aggregates
df.rice = subset(df, df$variable %in% c("Irrigated Rice", "Rainfed Rice"))
p <- ggplot(data = df.rice, aes(x = `HYDE (Mha)`, y = `GAEZ (Mha)`)) +
  geom_point(size=0.5) +
  geom_smooth(method = "lm", formula = y ~ x) +
  geom_abline(slope=1, intercept=0, color='grey', lwd=0.4)+
  theme_light(base_size = 14) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0))
p1 = p + facet_grid(variable ~ sp_unit)
p1

ggsave(paste("results/figures/cropland_validation/GAEZ_vs_HYDE_Rice_agg_panels.png", sep=""),
       plot = p1,
       width = 6, height = 4, units = "in",
       dpi = 300)
write.csv(df.rice, "results/cropland_validation/GAEZ_vs_HYDE_Rice_agg_data.csv")

##################################################################################
### FIGURE 9

# make panels for all crops and rice, grid cell
df.grid = merge(gcell.g.long, gcell.h.long)
p <- ggplot(data = df.grid, aes(x = `HYDE (1000 ha)`, y = `GAEZ (1000 ha)`)) +
  geom_point(size=0.5) +
  geom_smooth(method = "lm", formula = y ~ x) +
  geom_abline(slope=1, intercept=0, color='grey', lwd=0.4)+
  theme_light(base_size = 14) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0))
p1 = p + facet_grid(~factor(variable, levels = c("Cropland", "Irrigated", "Rainfed", "Irrigated Rice", "Rainfed Rice")))

ggsave(paste("results/figures/cropland_validation/GAEZ_vs_HYDE_gridCell_panels_v2.png", sep=""),
       plot = p1,
       width = 10, height = 3, units = "in",
       dpi = 300)

