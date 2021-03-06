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
 * Provides a class `DataFlowNode` for working with a data flow graph-based
 * program representation.
 *
 * We distinguish between _local flow_ and _non-local flow_.
 *
 * Local flow only considers data flow within an expression (for example,
 * from the operands of a `&&` expression to the expression itself), flow
 * through local variables, and flow from the arguments of an immediately
 * invoked function expression to its parameters. Captured variables are
 * treated flow-insensitively, that is, all assignments are considered to
 * flow into all uses.
 *
 * Non-local flow considers data flow through global variables.
 *
 * Flow through object properties or function calls is not modelled (except
 * for immediately invoked functions as explained above).
 */

import Expr

/**
 * An expression or function/class declaration, viewed as a node in a data flow graph.
 */
class DataFlowNode extends @exprorstmt {
  DataFlowNode() {
    this instanceof Expr or
    this instanceof FunctionDeclStmt or
    this instanceof ClassDefinition
  }

  /**
   * Gets another flow node from which data may flow to this node in one local step.
   */
  DataFlowNode localFlowPred() {
    // to be overridden by subclasses
    none()
  }

  /**
   * Gets another flow node from which data may flow to this node in one non-local step.
   */
  DataFlowNode nonLocalFlowPred() {
    // to be overridden by subclasses
    none()
  }

  /**
   * Gets another flow node from which data may flow to this node in one step,
   * either locally or non-locally.
   */
  DataFlowNode flowPred() {
    result = localFlowPred() or result = nonLocalFlowPred()
  }

  /**
   * Gets a source flow node (that is, a node without a `localFlowPred()`) from which data
   * may flow to this node in zero or more local steps.
   */
  cached
  DataFlowNode getALocalSource() {
    isLocalSource(result) and
    (
      result = this
      or
      locallyReachable(result, this)
    )
  }

  /**
   * Gets a source flow node (that is, a node without a `flowPred()`) from which data
   * may flow to this node in zero or more steps, considering both local and non-local flow.
   */
  DataFlowNode getASource() {
    if exists(flowPred()) then
      result = flowPred().getASource()
    else
      result = this
  }

  /**
   * Holds if the flow information for this node is incomplete.
   *
   * This predicate holds if there may be a source flow node from which data flows into
   * this node, but that node is not a result of `getASource()` due to analysis incompleteness.
   * The parameter `cause` is bound to a string describing the source of incompleteness.
   *
   * For example, since this analysis is intra-procedural, data flow from actual arguments
   * to formal parameters is not modeled. Hence, if `p` is an access to a parameter,
   * `p.getASource()` does _not_ return the corresponding argument, and
   * `p.isIncomplete("call")` holds.
   */
  predicate isIncomplete(DataFlowIncompleteness cause) {
    none()
  }

  /** Gets a textual representation of this element. */
  string toString() { result = this.(ASTNode).toString() }

  /** Gets the location of the AST node underlying this data flow node. */
  Location getLocation() { result = this.(ASTNode).getLocation() }
}

/** Holds if `nd` is a local source, that is, it has no local data flow predecessor. */
private predicate isLocalSource(DataFlowNode nd) {
  not exists(nd.localFlowPred())
}

/** Holds if data may flom from `nd` to `succ` in one local step. */
private predicate localFlow(DataFlowNode nd, DataFlowNode succ) {
  nd = succ.localFlowPred()
}

/**
 * Holds if `snk` is reachable from `src` in one or more local steps, where `src`
 * itself is reachable from a local source in zere or more local steps.
 */
private predicate locallyReachable(DataFlowNode src, DataFlowNode snk) =
  boundedFastTC(localFlow/2, isLocalSource/1)(src, snk)

/**
 * A classification of flows that are not modeled, or only modeled incompletely, by
 * `DataFlowNode`.
 */
class DataFlowIncompleteness extends string {
  DataFlowIncompleteness() {
    this = "call" or   // lack of inter-procedural analysis
    this = "heap" or   // lack of heap modeling
    this = "import" or // lack of module import/export modeling
    this = "global" or // incomplete modeling of global object
    this = "yield" or  // lack of yield/async/await modeling
    this = "eval"      // lack of reflection modeling
  }
}

/**
 * A variable access, viewed as a data flow node.
 */
private class VarAccessFlow extends DataFlowNode, @varaccess {
  VarAccessFlow() { this instanceof RValue }

  /**
   * Gets a data flow node representing a local variable definition to which
   * this access may refer.
   */
  private VarDefFlow getALocalDef() {
    // flow-sensitive handling of un-captured variables
    localDefinitionReaches(_, result, this)
    or
    // flow-insensitive handling for captured ones
    exists (LocalVariable lv | lv.isCaptured() |
      lv = result.getAVariable() and
      this = lv.getAnAccess()
    )
  }

  override DataFlowNode localFlowPred() {
    // flow through local variable
    result = getALocalDef().getSourceNode() or

    // flow through IIFE
    exists (ImmediatelyInvokedFunctionExpr iife, SimpleParameter parm |
      isIIFEParameterAccess(iife, parm) and
      iife.argumentPassing(parm, (Expr)result)
    )
  }

  /**
   * Holds if this is an access to parameter `parm` of immediately invoked
   * function expression `iife`.
   */
  private predicate isIIFEParameterAccess(ImmediatelyInvokedFunctionExpr iife, SimpleParameter p) {
    this = p.getVariable().getAnAccess() and
    p = iife.getAParameter()
  }

  override DataFlowNode nonLocalFlowPred() {
    exists (GlobalVariable v, VarDefFlow def |
      v = def.getAVariable() and
      result = def.getSourceNode() and
      this = v.getAnAccess()
    )
  }

  override predicate isIncomplete(DataFlowIncompleteness cause) {
    this.(VarUse).getADef().(VarDefFlow).isIncomplete(cause) or
    exists (Variable v | this = v.getAnAccess() |
      v.isGlobal() and cause = "global" or
      v instanceof ArgumentsVariable and cause = "call" or
      any(DirectEval e).mayAffect(v) and cause = "eval"
    )
  }
}

/**
 * A variable definition, viewed as a contributor to the data flow graph.
 */
private class VarDefFlow extends VarDef {
  /**
   * Gets a data flow node representing the value assigned by this
   * definition.
   */
  DataFlowNode getSourceNode() {
    // follow one step of the def-use chain, but only for definitions where
    // the lhs is a simple variable reference (as opposed to a destructuring
    // pattern)
    result = getSource() and getTarget() instanceof VarRef or

    // for compound assignments and updates there isn't an explicit source,
    // so we stop there
    result = (CompoundAssignExpr)this or
    result = (UpdateExpr)this
  }

  /**
   * Holds if this definition is analysed imprecisely due to `cause`.
   */
  predicate isIncomplete(DataFlowIncompleteness cause) {
    this instanceof Parameter and cause = "call" or
    this instanceof ImportSpecifier and cause = "import" or
    exists (EnhancedForLoop efl | this = efl.getIteratorExpr()) and cause = "heap" or
    exists (ComprehensionBlock cb | this = cb.getIterator()) and cause = "yield" or
    getTarget() instanceof DestructuringPattern and cause = "heap"
  }
}

/** A parenthesized expression, viewed as a data flow node. */
private class ParExprFlow extends DataFlowNode, @parexpr {
  override DataFlowNode localFlowPred() {
    result = this.(ParExpr).getExpression()
  }
}

/** A sequence expression, viewed as a data flow node. */
private class SeqExprFlow extends DataFlowNode, @seqexpr {
  override DataFlowNode localFlowPred() {
    result = this.(SeqExpr).getLastOperand()
  }
}

/** A short-circuiting logical expression, viewed as a data flow node. */
private class LogicalBinaryExprFlow extends DataFlowNode, @binaryexpr {
  LogicalBinaryExprFlow() { this instanceof LogicalBinaryExpr }

  override DataFlowNode localFlowPred() {
    result = this.(LogicalBinaryExpr).getAnOperand()
  }
}

/** An assignment expression, viewed as a data flow node. */
private class AssignExprFlow extends DataFlowNode, @assignexpr {
  override DataFlowNode localFlowPred() {
    result = this.(AssignExpr).getRhs()
  }
}

/** A conditional expression, viewed as a data flow node. */
private class ConditionalExprFlow extends DataFlowNode, @conditionalexpr {
  override DataFlowNode localFlowPred() {
    result = this.(ConditionalExpr).getABranch()
  }
}

/**
 * A data flow node whose value involves inter-procedural flow,
 * and which hence is analyzed incompletely.
 */
private class InterProcFlow extends DataFlowNode, @expr {
  InterProcFlow() {
    this instanceof InvokeExpr or
    this instanceof ThisExpr or
    this instanceof SuperExpr or
    this instanceof NewTargetExpr
  }

  override predicate isIncomplete(DataFlowIncompleteness cause) { cause = "call" }
}

/**
 * A property access, viewed as a data flow node.
 */
private class PropAccessFlow extends DataFlowNode, @propaccess {
  override predicate isIncomplete(DataFlowIncompleteness cause) { cause = "heap" }
}

/**
 * A data flow node whose value involves co-routines or promises,
 * and which hence is analyzed incompletely.
 */
private class IteratorFlow extends DataFlowNode, @expr {
  IteratorFlow() {
    this instanceof YieldExpr or
    this instanceof AwaitExpr or
    this instanceof FunctionSentExpr
  }

  override predicate isIncomplete(DataFlowIncompleteness cause) { cause = "yield" }
}

/**
 * A data flow node that reads or writes an object property.
 */
abstract class PropRefNode extends DataFlowNode {
  /**
   * Gets the data flow node corresponding to the base object
   * whose property is read from or written to.
   */
  abstract DataFlowNode getBase();

  /**
   * Gets the name of the property being read or written,
   * if it can be statically determined.
   *
   * This predicate is undefined for dynamic property references
   * such as `e[computePropertyName()]` and for spread/rest
   * properties.
   */
  abstract string getPropertyName();
}

/**
 * A data flow node that writes to an object property.
 */
abstract class PropWriteNode extends PropRefNode {
  /**
   * Gets the data flow node corresponding to the value being written,
   * if it can be statically determined.
   *
   * This predicate is undefined for spread properties, accessor
   * properties, and most uses of `Object.defineProperty`.
   */
  abstract DataFlowNode getRhs();
}

/**
 * A property assignment, viewed as a data flow node.
 */
private class PropAssignNode extends PropWriteNode, @propaccess {
  PropAssignNode() { this instanceof LValue }
  override DataFlowNode getBase() { result = this.(PropAccess).getBase() }
  override string getPropertyName() { result = this.(PropAccess).getPropertyName() }
  override DataFlowNode getRhs() { result = this.(LValue).getRhs() }
}

/**
 * A property of an object literal, viewed as a data flow node that writes
 * to the corresponding property.
 */
private class PropInitNode extends PropWriteNode, @expr {
  PropInitNode() { exists (Property vp | this = vp.getNameExpr()) }
  /** Gets the property that this node wraps. */
  private Property getProperty() { this = result.getNameExpr() }
  override DataFlowNode getBase() { result = getProperty().getObjectExpr() }
  override string getPropertyName() { result = getProperty().getName() }
  override DataFlowNode getRhs() { result = getProperty().(ValueProperty).getInit() }
}

/**
 * A call to `Object.defineProperty`, viewed as a data flow node that
 * writes to the corresponding property.
 */
private class ObjectDefinePropNode extends PropWriteNode, @callexpr {
  ObjectDefinePropNode() { this instanceof CallToObjectDefineProperty }
  override DataFlowNode getBase() { result = this.(CallToObjectDefineProperty).getBaseObject() }
  override string getPropertyName() {
    result = this.(CallToObjectDefineProperty).getPropertyName()
  }
  override DataFlowNode getRhs() {
    exists (ObjectExpr propdesc |
      propdesc = this.(CallToObjectDefineProperty).getPropertyDescriptor() and
      result = propdesc.getPropertyByName("value").getInit()
    )
  }
}

/**
 * A static member definition, viewed as a data flow node that adds
 * a property to the class.
 */
private class StaticMemberAsWrite extends PropWriteNode, @expr {
  StaticMemberAsWrite() {
    exists (MemberDefinition md | md.isStatic() and this = md.getNameExpr())
  }
  /** Gets the member definition that this node wraps. */
  private MemberDefinition getMember() { this = result.getNameExpr() }
  override DataFlowNode getBase() { result = getMember().getDeclaringClass().getDefinition() }
  override string getPropertyName() { result = getMember().getName() }
  override DataFlowNode getRhs() { result = getMember().getInit() }
}

/**
 * A spread property of an object literal, viewed as a data flow node that writes
 * properties of the object literal.
 */
private class SpreadPropertyAsWrite extends PropWriteNode, @expr {
  SpreadPropertyAsWrite() { exists (SpreadProperty prop | this = prop.getInit()) }
  override DataFlowNode getBase() { result.(ObjectExpr).getAProperty().getInit() = this }
  override string getPropertyName() { none() }
  override DataFlowNode getRhs() { none() }
}


/**
 * A JSX attribute, viewed as a data flow node that writes properties to
 * the JSX element it is in.
 */
private class JSXAttributeAsWrite extends PropWriteNode, @identifier {
  JSXAttributeAsWrite() { exists (JSXAttribute attr | this = attr.getNameExpr()) }
  /** Gets the JSX attribute that this node wraps. */
  private JSXAttribute getAttribute() { result.getNameExpr() = this }
  override DataFlowNode getBase() { result = getAttribute().getElement() }
  override string getPropertyName() { result = this.(Identifier).getName() }
  override DataFlowNode getRhs() { result = getAttribute().getValue() }
}

/**
 * A data flow node that reads an object property.
 */
abstract class PropReadNode extends PropRefNode {
  /**
   * Gets the default value of this property read, if any.
   */
  abstract DataFlowNode getDefault();
}

/**
 * A property access in rvalue position.
 */
private class PropAccessReadNode extends PropReadNode, @propaccess {
  PropAccessReadNode() { this instanceof RValue }
  override DataFlowNode getBase() { result = this.(PropAccess).getBase() }
  override string getPropertyName() { result = this.(PropAccess).getPropertyName() }
  override DataFlowNode getDefault() { none() }
}

/**
 * A property pattern viewed as a property read; for instance, in
 * `var { p: q } = o`, `p` is a read of property `p` of `o`.
 */
private class PropPatternReadNode extends PropReadNode, @expr {
  PropPatternReadNode() { this = any(PropertyPattern p).getNameExpr() }
  /** Gets the property pattern that this node wraps. */
  private PropertyPattern getPropertyPattern() { this = result.getNameExpr() }
  override DataFlowNode getBase() {
    exists (VarDef d |
      d.getTarget() = getPropertyPattern().getObjectPattern() and
      result = d.getSource()
    )
  }
  override string getPropertyName() { result = getPropertyPattern().getName() }
  override DataFlowNode getDefault() { result = getPropertyPattern().getDefault() }
}

/**
 * A rest pattern viewed as a property read; for instance, in
 * `var { ...ps } = o`, `ps` is a read of all properties of `o`.
 */
private class RestPropertyAsRead extends PropReadNode {
  RestPropertyAsRead() { this = any(ObjectPattern p).getRest() }
  override DataFlowNode getBase() {
    exists (VarDef d |
      d.getTarget().(ObjectPattern).getRest() = this and
      result = d.getSource()
    )
  }
  override string getPropertyName() { none() }
  override DataFlowNode getDefault() { none() }
}
