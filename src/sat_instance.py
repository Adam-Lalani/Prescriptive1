from dataclasses import dataclass, field
from typing import List, Set

@dataclass
class SATInstance:
    numVars: int
    numClauses: int
    vars: Set[int] = field(default_factory=set)
    clauses: List[Set[int]] = field(default_factory=list)

    def add_variable(self, literal: int):
        self.vars.add(abs(literal))

    def add_clause(self, clause: Set[int]):
        self.clauses.append(clause)

    def __str__(self):
        out = []
        out.append(f"Number of variables: {self.numVars}")
        out.append(f"Number of clauses: {self.numClauses}")
        out.append(f"Variables: {self.vars}")
        for i, clause in enumerate(self.clauses):
            out.append(f"Clause {i}: {clause}")
        return "\n".join(out) + "\n"
