#!/bin/bash -l

# submit a series of slurm jobs to perform the different steps in the pipeline, when one
# job depends on the results of another, make sure that they are executed in the correct
# sequence using the dependency flag of sbatch

# JOBID_01=$(sbatch script-global-fit/global-fit-job-01.sh) &&
# JOBID_02=$(sbatch --dependency=afterok:${JOBID_01##* } script-global-fit/global-fit-job-02.sh) &&
# JOBID_03=$(sbatch --dependency=afterok:${JOBID_02##* } script-global-fit/global-fit-job-03.sh) &&
# JOBID_04=$(sbatch --dependency=afterok:${JOBID_03##* } script-global-fit/global-fit-job-04.sh) &&
# JOBID_05=$(sbatch --dependency=afterok:${JOBID_04##* } script-global-fit/global-fit-job-05.sh) &&
# JOBID_06=$(sbatch --dependency=afterok:${JOBID_05##* } script-global-fit/global-fit-job-06.sh)
# 
# echo $JOBID_01
# echo $JOBID_02
# echo $JOBID_03
# echo $JOBID_04
# echo $JOBID_05
# echo $JOBID_06

JOBID_04=$(sbatch script-global-fit/global-fit-job-04.sh) &&
JOBID_05=$(sbatch --dependency=afterok:${JOBID_04##* } script-global-fit/global-fit-job-05.sh) &&
JOBID_06=$(sbatch --dependency=afterok:${JOBID_05##* } script-global-fit/global-fit-job-06.sh)

echo $JOBID_04
echo $JOBID_05
echo $JOBID_06