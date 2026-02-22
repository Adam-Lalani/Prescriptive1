########################################
E_BADARGS=65
if [ $# -lt 3 ] || [ $# -gt 5 ]
then
        echo "Usage: `basename $0` <inputFolder/> <timeLimit> <logFile> [--race] [solver1,solver2,...]"
        echo "Description:"
        echo -e "\t This script makes calls to ./run.sh for all the files in the given inputFolder/"
        echo -e "\t Each run is subject to the given time limit in seconds."
        echo -e "\t Last line of each run is appended to the given logFile."
        echo -e "\t If a run fails, due to the time limit or other error, the file name is appended to the logFile with --'s as time and result."
        echo -e "\t If the logFile already exists, the run is aborted."
        echo -e "\t Use --race flag to run multiple solvers in parallel (optional)."
        echo -e "\t Provide solvers as comma-separated list: dpll,cdcl_vsids,cdcl_vsids_luby"
        echo ""
        echo "Examples:"
        echo -e "\t `basename $0` input/ 300 results.log dpll"
        echo -e "\t `basename $0` input/ 300 results.log --race dpll,cdcl_vsids"
        exit $E_BADARGS
fi

# Parameters
inputFolder=$1
timeLimit=$2
logFile=$3

# Parse optional race flag and solvers
race_flag=""
solvers="dpll"  # default solver

if [ $# -eq 4 ]; then
    if [ "$4" == "--race" ]; then
        race_flag="--race"
        solvers="dpll"  # default when only --race is provided
    else
        solvers=$4
    fi
elif [ $# -eq 5 ]; then
    race_flag="$4"
    solvers=$5
fi

# Append slash to the end of inputFolder if it does not have it
lastChar="${inputFolder: -1}"
if [ "$lastChar" != "/" ]; then
    inputFolder=$inputFolder/
fi

# Terminate if the log file already exists
[ -f $logFile ] && echo "Logfile $logFile already exists, terminating." && exit 1

# Create the log file
touch $logFile

# Build solver arguments
solver_args=""
IFS=',' read -ra SOLVER_ARRAY <<< "$solvers"
for s in "${SOLVER_ARRAY[@]}"; do
    solver_args="$solver_args --solver $s"
done

# Run on every file, get the last line, append to log file (each run limited to timeLimit seconds)
for f in $inputFolder*.*
do
        fullFileName=$(realpath "$f")
        echo "Running $fullFileName with: $race_flag $solver_args"
        timeout $timeLimit ./run.sh $race_flag $solver_args "$fullFileName" > output4.tmp
        returnValue="$?"
        if [[ "$returnValue" = 0 ]]; then                                       # Run is successful
                cat output4.tmp | tail -1 >> $logFile                           # Record the last line as solution
        else                                                                    # Run failed, record the instanceName with no solution
                echo Error
                instance=$(basename "$fullFileName")    
                echo "{\"Instance\": \"$instance\", \"Time\": \"--\", \"Result\": \"--\"}" >> $logFile  
        fi
        rm -f output4.tmp
done
