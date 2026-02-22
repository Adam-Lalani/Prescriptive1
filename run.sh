#!/bin/bash

########################################
############# CSCI 2951-O ##############
########################################
E_BADARGS=65
if [ $# -lt 1 ]
then
	echo "Usage: `basename $0` [--solver <name>] <input>"
	exit $E_BADARGS
fi

# run the solver — forward all arguments to main.jl
set -e
<<<<<<< Updated upstream
# export JULIA_NUM_THREADS=2
=======
export JULIA_NUM_THREADS=2
>>>>>>> Stashed changes
julia --project=. src/main_processes.jl "$@"
