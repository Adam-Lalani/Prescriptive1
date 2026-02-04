from collections import defaultdict
from typing import List, Set
import copy
from objects import Node

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
        # check if every clause is true -> return true
        if current_node.var_to_clause_ids == {}:
            self.solution = current_node.sat_vars_to_assignment
            return

        # check if empty clause is left -> return false
        # FLAG: def not fast enough... do i need this?
        if current_node is None:
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
        
        branch_var = self.heuristic(list(current_node.var_to_clause_ids.keys()))

        return self.run_dpll(self.update_node(current_node, branch_var)) or self.run_dpll(self.update_node(current_node, -branch_var))

    def find_pure_symbol(self, node):
        for var in node.pure_vars:
            next_node = self.update_node(node, var)
            if next_node:
                next_node.pure_vars.remove(var)
                return next_node

    def find_unit_clause(self, node):
        for c_id in node.unit_clauses:
            next_node = self.update_node(node, next(iter(node.id_to_clause[c_id])))
            if next_node:
                next_node.unit_clauses.remove(c_id)
                return next_node

    def heuristic(self, unsat_vars):
        return unsat_vars[0]

    def update_node(self, node, var):
        new_node = copy.deepcopy(node)

        new_node.sat_vars_to_assignment[abs(var)] = (var >= 0)
        
        # remove clauses for current variable (being true automatically makes its clauses true)
        for c_id in node.var_to_clause_ids[var]:
            c = new_node.id_to_clause[c_id]
            # remove clause for all other variables too
            for v in c:
                if v != var:
                    new_node.var_to_clause_ids[v].remove(c_id)
                    
                    # check if variable no longer has clauses
                    if len(new_node.var_to_clause_ids[v]) == 0:
                        del new_node.var_to_clause_ids[v]

                        if -v in new_node.var_to_clause_ids:
                            new_node.pure_vars.add(-v)
            
            del new_node.id_to_clause[c_id]

        # remove opposite variable from clauses (being false means other variables must be true)
        for c_id in node.var_to_clause_ids[-var]:
            c = new_node.id_to_clause[c_id]
            if len(c) == 1:
                # found empty clause
                return None
            else:
                c.remove(-var)
                if len(c) == 1:
                    new_node.unit_clauses.add(c_id)

        
        del new_node.var_to_clause_ids[var]

        return new_node



