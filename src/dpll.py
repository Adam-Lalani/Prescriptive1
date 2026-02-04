from collections import defaultdict
from typing import List, Set, Dict, Optional
import copy
from objects import Node
from sat_instance import SATInstance

class DPLL:
    def __init__(self, instance):
        self.instance = instance

        # mapping of unique ids to clauses
        init_id_to_clause = defaultdict(set)
        # mapping of a variable to a set of unique clause ids 
        init_var_to_clause_ids = defaultdict(set)

        init_pure_vars = set()
        init_unit_clauses = set()

        for i, clause in enumerate(instance.clauses):
            init_id_to_clause[i] = clause
            for var in clause:
                init_var_to_clause_ids[var].add(i)

                if len(clause) == 1:
                    init_unit_clauses.add(i)

        for var in instance.vars:
            if var in init_var_to_clause_ids:
                if -var in init_var_to_clause_ids:
                    continue
                else:
                    init_pure_vars.add(var)
            else:
                init_pure_vars.add(-var)

        self.root = Node(init_id_to_clause, init_var_to_clause_ids, defaultdict(bool), init_unit_clauses, init_pure_vars)
        self.solution = None

    def run_dpll(self, current_node):
        # check if empty clause is left -> return false
        # FLAG: def not fast enough... do i need this?
        if current_node is None:
            return
        
        # check if every clause is true -> return true
        if current_node.var_to_clause_ids == {}:
            self.solution = current_node.sat_vars_to_assignment
            return

        # run aff/neg inference -> return dpll() w/ inference
        next_node = self.find_pure_symbol(current_node)
        if next_node:
            return self.run_dpll(next_node)

        # run unit clause inference -> return dpll() w/ inference
        next_node = self.find_unit_clause(current_node)
        if next_node:
            return self.run_dpll(next_node)

        # return dpll() w/ symbol = true OR dpll() w/ symbol = false
        
        branch_var = self.heuristic(current_node)

        return self.run_dpll(self.update_node(current_node, branch_var)) or self.run_dpll(self.update_node(current_node, -branch_var))

    def find_pure_symbol(self, node):
        literals = set()
        for clause in node.id_to_clause.values():
            literals |= clause

        for lit in literals:
            if -lit not in literals:
                return self.update_node(node, lit)

    def find_unit_clause(self, node):
        for _, clause in node.id_to_clause.items():
            if len(clause) == 1:
                var = next(iter(clause))
                return self.update_node(node, var)

    def heuristic(self, node):
        return next(iter(node.var_to_clause_ids))

    def update_node(self, node, lit):
        new_node = copy.deepcopy(node)
        var = abs(lit)
        val = lit > 0
        new_node.sat_vars_to_assignment[var] = val

        # Satisfy clauses containing lit
        for c_id in new_node.var_to_clause_ids[lit]:
            clause = new_node.id_to_clause[c_id]
            for l in clause:
                if l != lit:
                    new_node.var_to_clause_ids[l].discard(c_id)
            del new_node.id_to_clause[c_id]

        # Remove ¬lit from remaining clauses
        for c_id in new_node.var_to_clause_ids[-lit]:
            clause = new_node.id_to_clause[c_id]
            clause.remove(-lit)
            if len(clause) == 0:
                return None  # empty clause → UNSAT

        # Remove lit mappings
        new_node.var_to_clause_ids.pop(lit, None)
        new_node.var_to_clause_ids.pop(-lit, None)

        return new_node

class DPLL2:
    def __init__(self):
        pass

    def run_dpll(self, instance, assignment: Optional[Dict[int, bool]] = None) -> Optional[Dict[int, bool]]:
        """
        DPLL SAT solver for SATInstance.
        Returns a satisfying assignment or None if UNSAT.
        """
        if assignment is None:
            assignment = {}

        # Simplify clauses under current assignment
        def simplify(clauses, assignment):
            new_clauses = []
            for clause in clauses:
                # clause is satisfied?
                if any(
                    (lit > 0 and assignment.get(abs(lit)) is True) or
                    (lit < 0 and assignment.get(abs(lit)) is False)
                    for lit in clause
                ):
                    continue

                # remove falsified literals
                new_clause = {
                    lit for lit in clause
                    if abs(lit) not in assignment
                }

                new_clauses.append(new_clause)
            return new_clauses

        clauses = simplify(instance.clauses, assignment)

        # All clauses satisfied → SAT
        if not clauses:
            return self.complete_assignment(instance, assignment)

        # Empty clause → UNSAT
        if any(len(clause) == 0 for clause in clauses):
            return None

        # -------- Unit propagation --------
        for clause in clauses:
            if len(clause) == 1:
                lit = next(iter(clause))
                var = abs(lit)
                val = lit > 0

                if var in assignment and assignment[var] != val:
                    return None

                assignment[var] = val
                new_instance = SATInstance(
                    instance.numVars,
                    instance.numClauses,
                    instance.vars,
                    clauses
                )
                return self.run_dpll(new_instance, assignment)

        # -------- Pure literal elimination --------
        all_literals = set().union(*clauses)
        for lit in all_literals:
            if -lit not in all_literals:
                var = abs(lit)
                assignment[var] = lit > 0
                new_instance = SATInstance(
                    instance.numVars,
                    instance.numClauses,
                    instance.vars,
                    clauses
                )
                return self.run_dpll(new_instance, assignment)

        # -------- Branching --------
        # pick a variable from the first clause
        lit = next(iter(next(iter(clauses))))
        var = abs(lit)

        for val in (True, False):
            new_assignment = assignment.copy()
            new_assignment[var] = val

            new_instance = SATInstance(
                instance.numVars,
                instance.numClauses,
                instance.vars,
                clauses
            )

            result = self.run_dpll(new_instance, new_assignment)
            if result is not None:
                return result

        return None
    
    def complete_assignment(self, instance, assignment):
        full = assignment.copy()
        for v in instance.vars:
            if v not in full:
                full[v] = True   # arbitrary choice
        return full

