#!/bin/bash
#SBATCH -n 4
#SBATCH -N 1
#SBATCH -t 10:00:00
#SBATCH --mem=64G
#SBATCH -o cvl22_mindy.out
#SBATCH -e cvl22_mindy.out

module purge
unset LD_LIBRARY_PATH
module load cuda cudnn julia

export PATH="$HOME/.juliaup/bin:$PATH"
# Ensure project deps (e.g. JSON) are installed on this node
julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'

#     "dpll", "dpll_bad"  "cdcl_basic" "cdcl_vsids" "cdcl_vsids_luby" 
SOLVER="cdcl_vsids"
./runAll.sh input 300 "${SOLVER}-results.log" "$SOLVER"
