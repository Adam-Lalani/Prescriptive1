class Node:
    def __init__(self, id_to_clause, var_to_clause_ids, sat_vars_to_assignment, unit_clauses, pure_vars):
        self.id_to_clause = id_to_clause
        self.var_to_clause_ids = var_to_clause_ids
        self.sat_vars_to_assignment = sat_vars_to_assignment
        self.unit_clauses = unit_clauses
        self.pure_vars = pure_vars