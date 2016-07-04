// Copyright 2016 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * @name Suspicious unused loop iteration variable
 * @description A loop iteration variable is unused, which suggests an error.
 * @kind problem
 * @problem.severity error
 */

import python
import Definition

predicate is_increment(Stmt s) {
    /* x += n */
    s.(AugAssign).getValue() instanceof IntegerLiteral  
    or
    /* x = x + n */
    exists(Name t, BinaryExpr add |
        t = s.(AssignStmt).getTarget(0) and
        add = s.(AssignStmt).getValue() and
        add.getLeft().(Name).getVariable() = t.getVariable() and
        add.getRight() instanceof IntegerLiteral
    )
}

predicate counting_loop(For f) {
    is_increment(f.getAStmt())
}

predicate empty_loop(For f) {
    not exists(f.getStmt(1)) and f.getStmt(0) instanceof Pass
}

predicate one_item_only(For f) {
    not exists(Continue c | f.contains(c)) and
    exists(Stmt s | 
        s = f.getBody().getLastItem() |
        s instanceof Return
        or
        s instanceof Break
    )
}

predicate points_to_call_to_range(ControlFlowNode f) {
    /* (x)range is a function in Py2 and a class in Py3, so we must treat it as a plain object */ 
    exists(Object range, Object call |
        range = builtin_object("range") or
        range = builtin_object("xrange")
    |
        f.refersTo(call) and
        call.(CallNode).getFunction().refersTo(range)
    )
    or
    /* In case points-to fails due to 'from six.moves import range' or similar. */
    exists(string range |
        f.getNode().(Call).getFunc().(Name).getId() = range |
        range = "range" or range = "xrange"
    )
}

/** Whether n is a use of a variable that is a not effectively a constant. */
predicate use_of_non_constant(Name n) {
    exists(Variable var |
        n.uses(var) and
        /* use is local */
        not n.getScope() instanceof Module and
        /* variable is not global */
        not var.getScope() instanceof Module |
        /* Defined more than once (dynamically) */
        strictcount(Name def | def.defines(var)) > 1 or
        exists(For f, Name def | f.contains(def) and def.defines(var)) or
        exists(While w, Name def | w.contains(def) and def.defines(var))
    )
}

/** Whether loop body is implicitly repeating something N times.
 * E.g. queue.add(None)
 */
predicate implicit_repeat(For f) {
    not exists(f.getStmt(1)) and
    exists(ImmutableLiteral imm |
        f.getStmt(0).contains(imm)
    ) and
    not exists(Name n | f.getBody().contains(n) and use_of_non_constant(n))
}

from For f, Variable v

where f.getTarget() = v.getAnAccess() and
      not f.getAStmt().contains(v.getAnAccess()) and
      not points_to_call_to_range(f.getIter().getAFlowNode()) and
      not name_acceptable_for_unused_variable(v) and
      not f.getScope().getName() = "genexpr" and
      not empty_loop(f) and
      not one_item_only(f) and
      not counting_loop(f) and
      not implicit_repeat(f)

select f, "For loop variable " + v.getId() + " is not used in the loop body"
 