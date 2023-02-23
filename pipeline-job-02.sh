#!/bin/bash -l

# this job script is specifical for step 05 of the pipeline

#SBATCH -A naiss2023-22-58

#SBATCH -p node -N 5
#SBATCH -t 01:20:00
#SBATCH -J job-02-ND-pipeline

BASE_DIR=/proj/naiss2023-22-58
SIF_FILE=$BASE_DIR/ND-eval-pipeline/NDeval-pipeline-no-stdout-redirect-new.sif
SCRIPT_DIR=$BASE_DIR/ND-eval-pipeline/eval-fe56-scripts/script-Cr
CONFIG_FILE=$BASE_DIR/ND-eval-pipeline/eval-fe56-scripts/config/config-Cr52-mod-cov-func-try2.R

module load openmpi/4.0.2
mpirun -np 100 apptainer exec --bind $BASE_DIR $SIF_FILE Rscript --vanilla $SCRIPT_DIR/05_create_reference_jacobian.R $CONFIG_FILE
