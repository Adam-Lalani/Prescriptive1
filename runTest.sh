#!/bin/bash
#SBATCH -n 1
#SBATCH -N 1
#SBATCH -t 1:00:00
#SBATCH --mem=64G
#SBATCH -o rerun_1597_081.out
#SBATCH -e rerun_1597_081.out

module purge
unset LD_LIBRARY_PATH
module load cuda cudnn julia

export PATH="$HOME/.juliaup/bin:$PATH"
julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'

SOLVER="cdcl_vsids_luby"

timeout 350 ./run.sh --solver "$SOLVER" input/C1597_081.cnf
echo "Exit code: $?"

