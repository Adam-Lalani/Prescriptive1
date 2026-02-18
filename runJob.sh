#!/bin/bash
#SBATCH -p gpu --gres=gpu:2
#SBATCH --account=carney-tserre-condo
#SBATCH --partition=gpu
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -t 24:00:00
#SBATCH --mem=100G
#SBATCH -o job_mindy.out
#SBATCH -e job_mindy.out


conda deactivate
module purge
unset LD_LIBRARY_PATH
module load cudnn cuda
module load julia
source venv/bin/activate

export PATH="$HOME/.juliaup/bin:$PATH"

./runAll.sh input 1 results.log
