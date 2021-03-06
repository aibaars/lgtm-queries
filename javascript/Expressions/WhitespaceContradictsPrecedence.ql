// Copyright 2017 Semmle Ltd.
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
 * @name Whitespace contradicts operator precedence
 * @description Nested expressions where the formatting contradicts the grouping enforced by operator precedence
 *              are difficult to read and may even indicate a bug.
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 *       correctness
 * @precision high
 */

import javascript

/**
 * A nested associative expression.
 *
 * That is, a binary expression of the form `x op y`, which is itself an operand
 * (say, the left) of another binary expression `(x op y) op' z` such that
 * `(x op y) op' z = x op (y op' z)`, disregarding overflow.
 */
class AssocNestedExpr extends BinaryExpr {
  AssocNestedExpr() {
    exists(BinaryExpr parent, int idx | this = parent.getChildExpr(idx) |
      // +, *, &&, || and the bitwise operations are associative
      ((this instanceof AddExpr or this instanceof MulExpr or
        this instanceof BitwiseExpr or this instanceof LogicalBinaryExpr) and
        parent.getOperator() = this.getOperator())
      or
      // (x*y)/z = x*(y/z)
      (this instanceof MulExpr and parent instanceof DivExpr and idx = 0)
      or
      // (x/y)%z = x/(y%z)
      (this instanceof DivExpr and parent instanceof ModExpr and idx = 0)
      or
      // (x+y)-z = x+(y-z)
      (this instanceof AddExpr and parent instanceof SubExpr and idx = 0))
  }
}

/**
 * A binary expression nested inside another binary expression where the relative
 * precedence of the two operators is unlikely to cause confusion.
 */
class HarmlessNestedExpr extends BinaryExpr {
  HarmlessNestedExpr() {
    exists(BinaryExpr parent | this = parent.getAChildExpr() |
      (parent instanceof Comparison and (this instanceof ArithmeticExpr or this instanceof ShiftExpr))
      or
      (parent instanceof LogicalExpr and this instanceof Comparison))
  }
}

/** Holds if the right operand of `expr` starts on line `line`, at column `col`. */
predicate startOfBinaryRhs(BinaryExpr expr, int line, int col) {
  exists(Location rloc | rloc = expr.getRightOperand().getLocation() |
    rloc.getStartLine() = line and rloc.getStartColumn() = col
  )
}

/** Holds if the left operand of `expr` ends on line `line`, at column `col`. */
predicate endOfBinaryLhs(BinaryExpr expr, int line, int col) {
  exists(Location lloc | lloc = expr.getLeftOperand().getLocation() |
    lloc.getEndLine() = line and lloc.getEndColumn() = col
  )
}

/** Gets the number of whitespace characters around the operator of `expr`. */
int operatorWS(BinaryExpr expr) {
  exists(int line, int lcol, int rcol |
    endOfBinaryLhs(expr, line, lcol) and
    startOfBinaryRhs(expr, line, rcol) and
    result = rcol - lcol + 1 - expr.getOperator().length()
  )
}

/**
 * Holds if `inner` is an operand of `outer`, and the relative precedence
 * may not be immediately clear, but is important for the semantics of
 * the expression (that is, the operators are not associative).
 */
predicate interestingNesting(BinaryExpr inner, BinaryExpr outer) {
  inner = outer.getAChildExpr() and
  not inner instanceof AssocNestedExpr and
  not inner instanceof HarmlessNestedExpr
}

from BinaryExpr inner, BinaryExpr outer, int wsouter, int wsinner
where interestingNesting(inner, outer) and
      wsinner = operatorWS(inner) and wsouter = operatorWS(outer) and
      wsinner % 2 = 0 and wsouter % 2 = 0 and
      wsinner > wsouter and
      not outer.getTopLevel().isMinified()
select outer, "Whitespace around nested operators contradicts precedence."