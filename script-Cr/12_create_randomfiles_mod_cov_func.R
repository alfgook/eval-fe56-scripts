#
# DESCRIPTION OF STEP
#
# Use the 2nd order Taylor approximation of
# the posterior to create a sample of 
# TALYS parameter sets. Extend the paramters
# to a new energy grid (necessary for the 
# energy dependent parameters)
# Perform the respective
# calculations and save the results.
#

#################################################
#       SCRIPT Setup
##################################################

args = commandArgs(trailingOnly=TRUE)

if(length(args)==1) {
  print(paste0("Setting as config file: ", args[1]))
  source(args[1])
} else if (length(args) > 1) {
  stop("Script only accepts one argument.", call.=FALSE)
}

talysHnds <- createTalysHandlers()

#################################################
#       SCRIPT PARAMETERS
##################################################

library(parallel)
library(mvnfast)

scriptnr <- 12L
overwrite <- TRUE

##################################################
#       OUTPUT FROM PREVIOUS STEPS
##################################################

#extNeedsDt <- read_object(2, "extNeedsDt")
optParamDt <- read_object(10, "optParamDt")
needsDt <- read_object(1, "needsDt")
optGpDt <- read_object(6, "optGpDt")
Sexp <- read_object(10, "Sexp")
optSysDt_allpars <- read_object(10, "optSysDt_allpars")
finalPars <- read_object(11, "finalPars")
finalParCovmat <- read_object(11, "finalParCovmat")

##################################################
#       START OF SCRIPT
##################################################
print("-----------------------------------------------------")
print("----------------------script 12----------------------")
print("-----------------------------------------------------")

# before we do anything;
# check that we can create the directory pointed to by savePathTalys
# and that it does not already exists, to prevent overwriting stuff
#savePathTalys <- "/TMC/alf/eval-fe56-singularity/outdata-hyper-par-prior-test-new-energy-grid-test3/12"
stopifnot(dir.create(savePathTalys), showWarnings=TRUE, recursive=TRUE)
print(paste0("Storing talys results in: ", savePathTalys))

# where to save output data (don't overwrite the old stuff)
#outdataPath <- file.path(workdir, "outdata-hyper-par-prior-test-new-energy-grid-3")
#dir.create(outdataPath, recursive=TRUE, showWarnings=FALSE)

# define objects to be returned
outputObjectNames <- c("allParsets", "allResults","allParamDt","extNeedsDt","allSysDt","energyGridForParamsFull")
check_output_objects(scriptnr, outputObjectNames)

# something does not add up with the parameter transformation
# here (as copied from step08 in Georgs code) we apply the 
# parameter transformation to the result of the LM algorithm
# however the LM algorithm never sees the parameter transformation
# this is hidden inside of talys$fun and talys$jac

# create the data table of final parameters
finalParamDt <- copy(optParamDt)
finalParamDt[PARNAME %in% optSysDt_allpars$PARNAME, ADJUSTABLE:=TRUE]
setkey(finalParamDt, IDX)
# finalParamDt[ADJUSTABLE == TRUE, POSTVAL := paramTrafo$fun(finalPars)]
# IMPORTANT NOTE: POSTUNC is still with respect to transformed parameters
# finalParamDt[ADJUSTABLE == TRUE, POSTUNC := sqrt(diag(finalParCovmat))]

# extend the energy range of energy dependent parameter grid
energyGridForParams_extension <- energyGridrandomFiles[energyGridrandomFiles>max(energyGridForParams)]
energyGridForParams_extension <- energyGridForParams_extension[seq(3,length(energyGridForParams_extension),by=3)]
energyGridForParams_extension <- c(energyGridForParams_extension,220)

# store in output file
energyGridForParamsFull <- c(energyGridForParams,energyGridForParams_extension)

# retrieve the names of the parameters to extend
# add the energy dependent parameter specifications

endepParname_extension <- paste0(rep(enParDt[,par],each=length(energyGridForParams_extension)),"(",energyGridForParams_extension,") ",rep(enParDt[,proj],each=length(energyGridForParams_extension)))


endepInpList_extension <- as.list(rep(1, length(endepParname_extension)))
names(endepInpList_extension) <- endepParname_extension

# create a data table with the extended parameters
extParamDt <- data.table(PROJECTILE = unique(optParamDt$PROJECTILE),
                      ELEMENT = unique(optParamDt$ELEMENT),
                      MASS = unique(optParamDt$MASS),
                      PARNAME = names(endepInpList_extension),
                      PARVAL = endepInpList_extension,
                      ADJUSTABLE = TRUE,
                      PARUNC = 0.5)

# merge the existing and extended parameter data tables
allParamDt <- rbind(finalParamDt,extParamDt,fill=TRUE)
allParamDt[,IDX := seq_len(.N)]

# create a data table of systematics for the extended parameters
expIDs <- paste0("TALYS-",str_remove(endepParname_extension,"\\(.+\\)"))
energies <- unlist(regmatches(endepParname_extension,gregexpr("\\(.+\\)",endepParname_extension)))
energies <- as.numeric(substring(energies,2,nchar(energies)-1))

extSysDt <- data.table( IDX=NA,
                        EXPID=expIDs,
                        DIDX=NA,
                        ERRTYPE="talyspar_endep",
                        GPTYPE="sqrexp",
                        DATA=1,
                        UNC=0.5,
                        REFDATA=1,
                        ORIGIDX=NA,
                        EN=energies,
                        PARNAME=endepParname_extension
  )
extSysDt[,IDX := seq_len(.N)+nrow(optSysDt_allpars)]
extSysDt[,DIDX := seq_len(.N)+nrow(optSysDt_allpars)]

# Here is where the 'magic' happens
# I replace the EN values by their index
energies <- unique(extSysDt[ERRTYPE=="talyspar_endep",EN])
extSysDt[,EN:=match(EN,energies)+length(energyGridForParams),by=EN]

# merge the existing and extended systematics data tables
allSysDt <- rbind(optSysDt_allpars,extSysDt,fill=TRUE)

# create data table with needs specified by the new energy grid
extNeedsDt <- needsDt[,{
  stopifnot(all(L2 == 0) & all(L3 == 0))
  list(L1 = defineEnergyGrid(L1, energyGridrandomFiles, enPolicy="compgrid"),
       L2 = 0, L3 = 0, V1 = 0)
}, by=c("PROJECTILE", "ELEMENT", "MASS", "REAC")]

extNeedsDt[, IDX := seq_len(.N)]


# now consider also the insensitive parameters
# available for variations
allParamDt[PARNAME %in% allSysDt$PARNAME, ADJUSTABLE:=TRUE]

# set energy grid for random-files
parval <- as.list(allParamDt[, PARVAL])
parval[[1]] <- as.vector(energyGridrandomFiles)
allParamDt[, PARVAL:= parval]

# We need another parameter transformation here since the full parameter
# vector is different from the optimized parameter vector
adjParNamesFull <- allParamDt[ADJUSTABLE==TRUE,PARNAME]
for( i in 1:nrow(parRanges) ) {
  allParamDt[grepl(parRanges[i]$keyword,PARNAME),PARMIN:=parRanges[i]$min]
  allParamDt[grepl(parRanges[i]$keyword,PARNAME),PARMAX:=parRanges[i]$max]
}

# set the parameter transformation to be centered at the prior mean/mode
# the ranges of the parameters are the ones specified in the TALYS manual
paramTrafo <- parameterTransform(
                  x0 = unlist(allParamDt[ADJUSTABLE==TRUE,PARVAL]),
                  delta = allParamDt[ADJUSTABLE==TRUE,unlist(PARVAL) - PARMIN])

#############################################################################
# extend the finalPars and finalParCovmat to the extended parameter set
#############################################################################

# start by recreating the prior covariance matrix for all parameters
# including the extended energy range
# Observe that all parameters and their covariance matrices is in the 
# untransformed (internal) parameter space (they can take on any real value)
# as they are passed to TALYS via talys_wrapper.R they are transformed to 
# the external parameter space, limited by the allowed ranges of talys

gpHandler <- createSysCompGPHandler()
sysCompHandler <- createSysCompHandler()
sysCompHandler$addGPHandler(gpHandler)

print("Building the covariance matrices...")
# Prior covariance matrix including extended parameters
P <- sysCompHandler$cov(allSysDt, optGpDt, ret.mat = TRUE)
expSel <- allSysDt[, !grepl("TALYS-", EXPID)]
talysSel <- !expSel
P0_all <- P[talysSel, talysSel]

# update the block in the covariance matrix related to the optimized parameters
# this is the posterior covariance matrix
optpars_indices <- optSysDt_allpars[, sort(IDX)]
#P0_all[optpars_indices,optpars_indices] <- finalParCovmat
P0_opt_opt <- P0_all[optpars_indices,optpars_indices]

# block of the prior covariance matrix
# correlating optimized and extended parameters
P0_opt_ext <- P0_all[-optpars_indices,optpars_indices]

# block of the prior covariance matrix correlating
# related to the extended parameters
P0_ext_ext <- P0_all[-optpars_indices,-optpars_indices]


# update extended energy range parameters

# prior mean of optimized parameters
p0_opt <- unlist(finalParamDt[ADJUSTABLE==TRUE, PARVAL])

# prior mean of extra parameters
p0_extra <- unlist(extParamDt[, PARVAL]) # these are transformed parameters
#p0_extra <- paramTrafo$invfun(p0_extra)

# conditional covariance matrix for extra parameters (doesn't depend on the value of p_opt)
P1_ext_ext <- P0_ext_ext - P0_opt_ext %*% solve(P0_opt_opt,t(P0_opt_ext))

# calculate the inverse of P0_opt_opt, which will be used many times during the sampling
P0_opt_opt_inv <- solve(P0_opt_opt)

# symmetrize P1_ext_ext
stopifnot(max(abs(P1_ext_ext - t(P1_ext_ext))) < 1.e-09)
P1_ext_ext <- 0.5*(P1_ext_ext + t(P1_ext_ext))

print("...done!")

print("sampling the optimized parameters...")
# create samples of parameter sets
# first sample the optimized parameters from the posterior mean & covariance matrix
#opt_par_samples <- sample_mvn(numTalysFiles,finalPars,finalParCovmat) # this takes some time (few seconds)

if(!exists("numTalysParSamples")) numTalysParSamples <- numTalysFiles

# set the seed for the random number generator
# to have a reproducible creation of TALYS parameter sets
set.seed(talysFilesSeed)
nbr_cores_for_rmvn <- min(detectCores(),32)
print(paste0("number of cores used for rmvn: ",nbr_cores_for_rmvn," | talysFilesSeed = ", talysFilesSeed))

chol_finalParCovmat <- chol(finalParCovmat)
opt_par_samples <- t(as.matrix(rmvn(numTalysParSamples, finalPars, chol_finalParCovmat, ncores = nbr_cores_for_rmvn, isChol = TRUE)))
print("...done!")


# sample from the conditional covariance matrix of the extra parameters, with mean_vector = 0
# observe that the conditional covariance matrix does not depend on the particular value
# of the optimized parameter vector
print("sampling the extra parameters...")
chol_P1_ext_ext <- chol(P1_ext_ext)
ext_par_samples <- t(as.matrix(rmvn(numTalysParSamples, rep(0,length(p0_extra)), chol_P1_ext_ext, ncores = nbr_cores_for_rmvn, isChol = TRUE)))
print("...done!")

# define function to calculate the the conditional mean for each
# sample of the optimized parameters
P0_opt_ext_mult_P0_opt_opt_inv <- P0_opt_ext %*% P0_opt_opt_inv
conditional_mean_shift <- function(optParset)
{
  p0_extra + as.vector(P0_opt_ext_mult_P0_opt_opt_inv %*% (optParset-p0_opt))
}

# for each sample of the optimized paramter vector, add the conditional mean to the 
# sampled (with mean = 0) extra parameter vector
ext_par_samples <- ext_par_samples + apply(opt_par_samples,2,conditional_mean_shift)


# calculate the mean of the sampled extra parameters
#ext_pars_mean <- matrix(rowMeans(ext_par_samples),ncol=1)
ext_pars_mean <- matrix(conditional_mean_shift(finalPars),ncol=1)

# bind the sampled optimized and extra parameter vectors to samples of 
# the full parameter vector
variedParsets <- rbind(opt_par_samples,ext_par_samples)

# bind the mean optimized parameter vector with the sample-mean of the
# extra parameter vector to create a full 'best estimate' parameter vector
optParset <- rbind(as.matrix(finalPars),ext_pars_mean)

# bind together the 'best estimate' and the samples for the TALYS calculation
allParsets <- cbind(optParset, variedParsets[,1:numTalysFiles])

# make sure we have the endf='y' parameter in the parameter data.table

if(!nrow(allParamDt[grepl("endf",PARNAME)])) {
  arow <- copy(optParamDt[1])
  arow[1,PARNAME:='endf']
  arow[1,PARVAL:='y']
  allParamDt <- rbind(allParamDt,arow)
}
# perform calculations and save the result
#talysHnds$remHnd$ssh$execBash(paste0("mkdir -p '", pathTalys, "'; echo endofcommand"))
# see step 07_tune_talyspars.R for more explanation
# about setting up the talys handler
talys <- talysHnds$talysOptHnd
talys$setPars(allParamDt)
talys$setParTrafo(paramTrafo$fun, paramTrafo$jac)
talys$setNeeds(extNeedsDt)
talys$setSexp(Sexp) # 
# talys$setMask(mask) # do not apply mask to the random file creation
if(!exists("talys_finite_diff")) talys_finite_diff <- 0.01
talys$setEps(talys_finite_diff)
 

cat("ncol(allParsets) = ",ncol(allParsets),"\n")
cat("nrow(allParsets) = ",nrow(allParsets),"\n")

cat("Started calculations at", as.character(Sys.time()), "\n")  
allResults <- talys$fun(allParsets, applySexp = FALSE, ret.dt=FALSE, saveDir = savePathTalys)
cat("Finished calculations at", as.character(Sys.time()), "\n")
# 

# # save the needed files for reference
save_output_objects(scriptnr, outputObjectNames, overwrite)

adjParNames <- allParamDt[ADJUSTABLE==TRUE,PARNAME]
for( i in 1:nrow(parRanges) ) {
  allParamDt[grepl(parRanges[i]$keyword,PARNAME),PARMIN:=parRanges[i]$min]
  allParamDt[grepl(parRanges[i]$keyword,PARNAME),PARMAX:=parRanges[i]$max]
}

# set the parameter transformation to be centered at the prior mean/mode
# the ranges of the parameters are the ones specified in the TALYS manual
paramTrafo <- parameterTransform(
                  x0 = unlist(allParamDt[ADJUSTABLE==TRUE,PARVAL]),
                  delta = allParamDt[ADJUSTABLE==TRUE,unlist(PARVAL) - PARMIN])


# save the sampled parameters in a human readable data table
allParamDt[ADJUSTABLE == TRUE, POST_MODE := paramTrafo$fun(optParset)]

save_output_objects(scriptnr, "allParamDt", overwrite)