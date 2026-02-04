import json
from pathlib import Path
from argparse import ArgumentParser
from dimacs_parser import DimacsParser
from model_timer import Timer
from dpll import DPLL, DPLL2

def main(args):
    input_file = args.input_file
    
    if not input_file:
        print("Usage: python3 src/main.py <cnf file>")
        return

    path = Path(input_file)
    filename = path.name
    
    timer = Timer()
    timer.start()
    
    try:
        instance = DimacsParser.parse_cnf_file(input_file)
        if instance:
            print(instance, end="")
    except Exception as e:
        print(f"Error: {e}")
    
    dpll = DPLL(instance)
    dpll.run_dpll(dpll.root)
    solution = dpll.solution
    # dpll = DPLL2()
    # solution = dpll.run_dpll(instance)
    
    timer.stop()

    result = "--"
    if solution is not None:
        result = ""
        for var in instance.vars:
            result += str(var) + " "
            result += "true " if solution[var] else "false "
        
    printSol = {
        "Instance": filename,
        "Time": f"{timer.getTime():.2f}",
        "Result": result
    }
    
    print(json.dumps(printSol))

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("input_file", type=str)
    args = parser.parse_args()
    main(args)
