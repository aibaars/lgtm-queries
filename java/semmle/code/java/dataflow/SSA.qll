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
 * Library for SSA representation (Static Single Assignment form).
 *
 * An SSA variable consists of the pair of a `LocalScopeVariable` and an `SsaDefinition`.
 * Each SSA variable is defined either by a phi node, a parameter definition, or a `VariableUpdate`.
 */

import java
private import DefUse

/** Whether `n` updates the locally scoped variable `v`. */
private predicate variableUpdate(LocalScopeVariable v, ControlFlowNode n, BasicBlock b, int i) {
  exists(VariableUpdate a | a = n | a.getDestVar() = v) and b.getNode(i) = n
}

/** The definition point of a nested class in the parent scope. */
private ControlFlowNode parentDef(NestedClass nc) {
  nc.(AnonymousClass).getClassInstanceExpr() = result or
  nc.(LocalClass).getLocalClassDeclStmt() = result
}

/**
 * The enclosing type of a nested class.
 *
 * Differs from `RefType.getEnclosingType()` by including anonymous classes defined by lambdas.
 */
private RefType desugaredGetEnclosingType(NestedClass inner) {
  exists(ControlFlowNode node |
    node = parentDef(inner) and
    node.getEnclosingCallable().getDeclaringType() = result
  )
}

/**
 * The control flow node at which the variable is read to get the value for
 * a `VarAccess` inside a closure.
 */
private ControlFlowNode parentAccess(VarAccess va) {
  exists(LocalScopeVariable v, Callable inner, Callable outer, NestedClass innerclass |
    va.getVariable() = v and
    inner = va.getEnclosingCallable() and
    (outer = v.(LocalVariableDecl).getCallable() or outer = v.(Parameter).getCallable()) and
    inner != outer and
    inner.getDeclaringType() = innerclass and
    result = parentDef(desugaredGetEnclosingType*(innerclass)) and
    result.getEnclosingStmt().getEnclosingCallable() = outer
  )
}

/** A `VarAccess` `use` of `v` in `b` at index `i`. */
private predicate variableUse(LocalScopeVariable v, RValue use, BasicBlock b, int i) {
  exists(ControlFlowNode n |
    v.getAnAccess() = use and b.getNode(i) = n
    |
    n = use or n = parentAccess(use)
  )
}

/*
 * Liveness analysis to restrict the size of the SSA representation.
 */

cached
private predicate liveAtEntry(LocalScopeVariable v, BasicBlock b) {
  exists (int i | variableUse(v, _, b, i) |
    not exists (int j | variableUpdate(v, _, b, j) | j < i))
  or
  liveAtExit(v, b) and not variableUpdate(v, _, b, _)
}
private predicate liveAtExit(LocalScopeVariable v, BasicBlock b) {
  liveAtEntry(v, b.getABBSuccessor())
}

/** A phi node for `v` at the beginning of basic block `b`. */
cached
private predicate phiNode(LocalScopeVariable v, BasicBlock b) {
  liveAtEntry(v, b) and
  exists(BasicBlock def | dominanceFrontier(def, b) |
    variableUpdate(v, _, def, _) or phiNode(v, def)
  )
}

/**
 * A definition of an SSA variable occurring at the specified position.
 * This is either a phi node, a `VariableUpdate`, or a parameter.
 */
cached
private predicate ssaDef(LocalScopeVariable v, ControlFlowNode n, BasicBlock b, int i) {
  phiNode(v, b) and b = n and i = 0 or
  variableUpdate(v, n, b, i) or
  v.(Parameter).getCallable().getBody() = b and b = n and i = 0
}

/*
 * The construction of SSA form ensures that each use of a variable is
 * dominated by its definition. A definition of an SSA variable therefore
 * reaches a `ControlFlowNode` if it is the _closest_ SSA variable definition
 * that dominates the node. If two definitions dominate a node then one must
 * dominate the other, so therefore the definition of _closest_ is given by the
 * dominator tree. Thus, reaching definitions can be calculated in terms of
 * dominance.
 */

/**
 * A ranking of the indices `i` at which there is an SSA definition or use of
 * `v` in the basic block `b`.
 *
 * Basic block indices are translated to rank indices in order to skip
 * irrelevant indices at which there is no definition or use when traversing
 * basic blocks.
 */
private predicate defUseRank(LocalScopeVariable v, BasicBlock b, int rankix, int i) {
  i = rank[rankix](int j | ssaDef(v, _, b, j) or variableUse(v, _, b, j))
}

/** The maximum rank index for the given variable and basic block. */
private int lastRank(LocalScopeVariable v, BasicBlock b) {
  result = max(int rankix | defUseRank(v, b, rankix, _))
}

/** A definition of an SSA variable occurring at the specified rank index in basic block `b`. */
private predicate ssaDefRank(LocalScopeVariable v, SsaDefinition def, BasicBlock b, int rankix) {
  exists(int i |
    ssaDef(v, def, b, i) and
    defUseRank(v, b, rankix, i)
  )
}

/** The SSA definition reaches the rank index `rankix` in its own basic block `b`. */
private predicate ssaDefReachesRank(LocalScopeVariable v, SsaDefinition def, BasicBlock b, int rankix) {
  ssaDefRank(v, def, b, rankix) or
  ssaDefReachesRank(v, def, b, rankix-1) and rankix <= lastRank(v, b) and not ssaDefRank(v, _, b, rankix)
}

/**
 * The SSA definition of `v` at `def` reaches the end of a basic block `b`, at
 * which point it is still live, without crossing another SSA definition of `v`.
 */
private predicate ssaDefReachesEndOfBlock(LocalScopeVariable v, SsaDefinition def, BasicBlock b) {
  liveAtExit(v, b) and
  (
    ssaDefReachesRank(v, def, b, lastRank(v, b)) or
    exists(BasicBlock idom |
      bbIDominates(idom, b) and // It is sufficient to traverse the dominator graph, cf. discussion above.
      ssaDefReachesEndOfBlock(v, def, idom) and
      not ssaDef(v, _, b, _)
    )
  )
}

/**
 * The SSA definition of `v` at `def` reaches `use` in the same basic block
 * without crossing another SSA definition of `v`.
 */
private predicate ssaDefReachesUseWithinBlock(LocalScopeVariable v, SsaDefinition def, RValue use) {
  exists(BasicBlock b, int rankix, int i |
    ssaDefReachesRank(v, def, b, rankix) and
    defUseRank(v, b, rankix, i) and
    variableUse(v, use, b, i)
  )
}

/**
 * The SSA definition of `v` at `def` reaches `use` without crossing another
 * SSA definition of `v`.
 */
cached private predicate ssaDefReachesUse(LocalScopeVariable v, SsaDefinition def, RValue use) {
  ssaDefReachesUseWithinBlock(v, def, use) or
  exists(BasicBlock b |
    variableUse(v, use, b, _) and
    ssaDefReachesEndOfBlock(v, def, b.getABBPredecessor()) and
    not ssaDefReachesUseWithinBlock(v, _, use)
  )
}

/**
 * A definition of one or more SSA variables.
 *
 * An SSA variable is effectively the pair of a definition and the (non-SSA) variable that it defines.
 * Each SSA variable is defined either by a phi node, a parameter definition, or a `VariableUpdate`.
 *
 * Note that all the methods on `SsaDefinition` taking a variable `v` implies `v = getAVariable()`.
 */
class SsaDefinition extends ControlFlowNode {
  SsaDefinition() {
    ssaDef(_, this, _, _)
  }

  /** A variable defined by this definition. */
  LocalScopeVariable getAVariable() {
    ssaDef(result, this, _, _)
  }

  /** A string representation of the SSA variable. */
  string toString(LocalScopeVariable v) {
    isPhiNode(v) and result = "SSA phi(" + v.getName() + ")" or
    isParameterDefinition((Parameter)v) and result = "SSA param(" + v.getName() + ")" or
    isVariableUpdate(v) and result = "SSA def(" + v.getName() + ")"
  }

  /** An access of the SSA variable. */
  RValue getAUse(LocalScopeVariable v) {
    ssaDefReachesUse(v, this, result)
  }

  /** Whether the SSA variable is defined by a phi node. */
  predicate isPhiNode(LocalScopeVariable v) {
    phiNode(v, this)
  }

  /** An input to the phi node defining the SSA variable if `isPhiNode(v)`. */
  cached SsaDefinition getAPhiInput(LocalScopeVariable v) {
    phiNode(v, this) and
    exists (BasicBlock phiPred |
      this.(BasicBlock).getABBPredecessor() = phiPred and
      ssaDefReachesEndOfBlock(v, result, phiPred)
    )
  }

  /** Whether the SSA variable is a parameter defined by its initial value in the callable. */
  predicate isParameterDefinition(Parameter v) {
    this = v.getCallable().getBody()
  }

  /** Whether the SSA variable is defined by a `VariableUpdate`. */
  predicate isVariableUpdate(LocalScopeVariable v) {
    exists (getDefiningExpr(v))
  }

  /** The `VariableUpdate` defining the SSA variable. */
  VariableUpdate getDefiningExpr(LocalScopeVariable v) {
    result = this and result.getDestVar() = v
  }

  predicate isLiveAtEndOfBlock(LocalScopeVariable v, BasicBlock b) {
    ssaDefReachesEndOfBlock(v, this, b)
  }

  /** The reflexive, transitive closure of `getAPhiInput`. */
  SsaDefinition getAPhiInputStar(LocalScopeVariable v) {
    result = this and v = this.getAVariable() or
    result = getAPhiInput(v).getAPhiInputStar(v)
  }

  /** A definition that ultimately defines this variable and is not itself a phi node. */
  SsaDefinition getAnUltimateDefinition(LocalScopeVariable v) {
    result = this.getAPhiInputStar(v) and not result.isPhiNode(v)
  }
}

library class RefTypeCastExpr extends CastExpr {
  RefTypeCastExpr() { this.getType() instanceof RefType }
}

/**
 * An expression that has the same value as the given SSA variable.
 *
 * The `VarAccess` represents the access to `v` that `result` has the same value as.
 */
Expr sameValue(SsaDefinition ssa, LocalScopeVariable v, VarAccess va) {
  result = ssa.getAUse(v) and result = va or
  result.(AssignExpr).getDest() = va and result = ssa.getDefiningExpr(v) or
  result.(AssignExpr).getSource() = sameValue(ssa, v, va) or
  result.(ParExpr).getExpr() = sameValue(ssa, v, va) or
  result.(RefTypeCastExpr).getExpr() = sameValue(ssa, v, va)
}

/**
 * There exists a path from `def` to `use` without passing through another
 * `VariableUpdate` of the `LocalScopeVariable` that they both refer to.
 *
 * Other paths may also exist, so the SSA variables in `def` and `use` can be different.
 */
predicate defUsePair(VariableUpdate def, RValue use) {
  exists (SsaDefinition ssa, LocalScopeVariable v |
    ssa.getAUse(v) = use and ssa.getAnUltimateDefinition(v).getDefiningExpr(v) = def
  )
}

/**
 * There exists a path from the entry-point of the callable to `use` without
 * passing through a `VariableUpdate` of the parameter `p` that `use` refers to.
 *
 * Other paths may also exist, so the SSA variables can be different.
 */
predicate parameterDefUsePair(Parameter p, RValue use) {
  exists (SsaDefinition ssa |
    ssa.getAUse(p) = use and ssa.getAnUltimateDefinition(p).isParameterDefinition(p)
  )
}
