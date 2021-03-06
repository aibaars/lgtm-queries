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
 * A library for working with Java Reflection.
 */

import java
import JDKAnnotations
import Serializability
import semmle.code.java.dataflow.DefUse

predicate reflectivelyRead(Field f){
  f instanceof SerializableField or
  f.getAnAnnotation() instanceof ReflectiveAccessAnnotation or
  referencedInXmlFile(f)
}

predicate reflectivelyWritten(Field f){
  f instanceof DeserializableField or
  f.getAnAnnotation() instanceof ReflectiveAccessAnnotation or
  referencedInXmlFile(f)
}

/**
 * Whether a field's name and declaring type are referenced in an XML file.
 * Usually, this implies that the field may be accessed reflectively.
 */
predicate referencedInXmlFile(Field f) {
  elementReferencingField(f).getParent*() = elementReferencingType(f.getDeclaringType())
}

/**
 * An XML element with an attribute whose value is the name of `f`,
 * suggesting that it might reference `f`.
 */
private XMLElement elementReferencingField(Field f) {
  result.getAnAttribute().getValue() = f.getName()
}

/**
 * An XML element with an attribute whose value is the fully qualified
 * name of `rt`, suggesting that it might reference `rt`.
 */
private XMLElement elementReferencingType(RefType rt) {
  result.getAnAttribute().getValue() = rt.getSourceDeclaration().getQualifiedName()
}

/**
 * A call to a Java standard library method which constructs or returns a `Class<T>` from a `String`.
 */
library class ReflectiveClassIdentifier extends MethodAccess {
  ReflectiveClassIdentifier() {
    // A call to `Class.forName(...)`, from which we can infer `T` in the returned type `Class<T>`.
    getCallee().getDeclaringType() instanceof TypeClass and getCallee().hasName("forName") or
    // A call to `ClassLoader.loadClass(...)`, from which we can infer `T` in the returned type `Class<T>`.
    getCallee().getDeclaringType().hasQualifiedName("java.lang", "ClassLoader") and getCallee().hasName("loadClass")
  }

  /**
   * If the argument to this call is a `StringLiteral`, then return that string.
   */
  string getTypeName() {
    result = getArgument(0).(StringLiteral).getRepresentedString()
  }

  RefType getReflectivelyIdentifiedClass() {
    // We only handle cases where the class is specified as a string literal to this call.
    result.getQualifiedName() = getTypeName()
  }
}

/**
 * A `ReflectiveClassIdentifier` that we believe may represent the value of `expr`.
 */
private ReflectiveClassIdentifier pointsToReflectiveClassIdentifier(Expr expr) {
    // If this is an expression creating a `Class<T>`, return the inferred `T` from the creation expression.
    result = expr or
    // Or if this is an access of a variable which was defined as an expression creating a `Class<T>`,
    // return the inferred `T` from the definition expression.
    exists(VarAccess va, LocalVariableDecl v, DefStmt def, UseStmt use, VariableAssign assign |
      va = expr.(VarAccess) and
      v = va.getVariable() and
      defUsePair(v, def, use) and
      va = use.getAUse(v) and
      assign = def.getADef(v) and
      // The source of the assignment must be a `ReflectiveClassIdentifier`.
      result = assign.getSource()
    )
}

/**
 * A type that is considered to be "overly" generic.
 */
private predicate overlyGenericType(Type type) {
  type instanceof TypeObject or
  type instanceof TypeSerializable
}

/**
 * Identify "catch-all" bounded types, where the upper bound is an overly generic type, such as
 * `? extends Object` and `? extends Serializable`.
 */
private predicate catchallType(BoundedType type) {
  exists(Type upperBound |
    upperBound = type.getUpperBoundType() |
    overlyGenericType(upperBound)
  )
}

/**
 * Given `Class<X>` or `Constructor<X>`, return all types `T`, such that
 * `Class<T>` or `Constructor<T>` is, or is a sub-type of, `type`.
 *
 * In the case that `X` is a bounded type with an upper bound, and that upper bound is `Object` or
 * `Serializable`, we return no sub-types.
 */
private Type parameterForSubTypes(ParameterizedType type) {
  (
    type instanceof TypeClass or type instanceof TypeConstructor
  ) and
  // Only report "real" types.
  not result instanceof TypeVariable and
  // Identify which types the type argument `arg` could represent.
  exists(Type arg |
    arg = type.getTypeArgument(0) and
    // Must not be a catch-all.
    not catchallType(arg) |
    (
      // Simple case - this type is not a bounded type, so must represent exactly the `arg` class.
      not arg instanceof BoundedType and result = arg
    ) or
    exists(RefType upperBound |
      // Upper bound case
      upperBound = arg.(BoundedType).getUpperBoundType() |
      /*
       * `T extends Foo` implies that `Foo`, or any sub-type of `Foo`, may be represented.
       */
      result.(RefType).getAnAncestor() = upperBound
    ) or
    exists(RefType lowerBound |
      // Lower bound case
      lowerBound = arg.(Wildcard).getLowerBoundType() |
      /*
       * `T super Foo` implies that `Foo`, or any super-type of `Foo`, may be represented.
       */
      lowerBound.(RefType).getAnAncestor() = result
    )
  )
}

/**
 * Given an expression whose type is `Class<T>`, infer a possible set of types for `T`.
 */
Type inferClassParameterType(Expr expr) {
  // Must be of type `Class` or `Class<T>`.
  expr.getType() instanceof TypeClass and
  (
    /*
     * If this `expr` is a `VarAccess` of a final or effectively final parameter, then look at the
     * arguments to calls to this method, to see if we can infer anything from that case.
     */
    exists(Parameter p |
      p = expr.(VarAccess).getVariable() and
      p.isEffectivelyFinal() |
      result = inferClassParameterType(p.getAnArgument())
    )
    or
    if exists(pointsToReflectiveClassIdentifier(expr).getReflectivelyIdentifiedClass()) then
      /*
       * We've been able to identify where this `Class` instance was created, and identified the
       * particular class that was loaded.
       */
      result = pointsToReflectiveClassIdentifier(expr).getReflectivelyIdentifiedClass()
    else
    (
      /*
       * If we haven't been able to find where the value for this expression was defined, then we
       * resort to the type `T` in `Class<T>`.
       *
       * If `T` refers to a bounded type with an upper bound, then we return all sub-types of the upper
       * bound as possibilities for the instantiation, so long as this is not a catch-all type.
       *
       * A "catch-all" type is something like `? extends Object` or `? extends Serialization`, which
       * would return too many sub-types.
       */
      result = parameterForSubTypes(expr.getType())
    )
  )
}

/**
 * Given an expression whose type is `Constructor<T>`, infer a possible set of types for `T`.
 */
private Type inferConstructorParameterType(Expr expr) {
  expr.getType() instanceof TypeConstructor and
  // Return all the possible sub-types that could be instantiated.
  // Not a catch-all `Constructor`, for example, `? extends Object` or `? extends Serializable`.
  result = parameterForSubTypes(expr.getType())
}

/**
 * Whether a `Constructor.newInstance(...)` call for this type would expect an enclosing instance
 * argument in the first position.
 */
private predicate expectsEnclosingInstance(RefType r) {
  r instanceof NestedType and
  not r.(NestedType).isStatic()
}

/**
 * A call to `Class.newInstance()` or `Constructor.newInstance()`.
 */
class NewInstance extends MethodAccess {
  NewInstance() {
    (getCallee().getDeclaringType() instanceof TypeClass or getCallee().getDeclaringType() instanceof TypeConstructor) and
    getCallee().hasName("newInstance")
  }

  /**
   * Return the `Constructor` that we believe will be invoked when this `newInstance()` method is
   * called.
   */
  Constructor getInferredConstructor() {
    result = getInferredConstructedType().getAConstructor() and
    if getCallee().getDeclaringType() instanceof TypeClass then
      result.getNumberOfParameters() = 0
    else if getNumArgument() = 1 and getArgument(0).getType() instanceof Array then
      /*
       * This is a var-args array argument. If array argument is initialized inline, then identify
       * the number of arguments specified in the array.
       */
      if exists(getArgument(0).(ArrayCreationExpr).getInit()) then
        // Count the number of elements in the initializer, and find the matching constructors.
        matchConstructorArguments(result, count(getArgument(0).(ArrayCreationExpr).getInit().getAnInit()))
      else
        // Could be any of the constructors on this class.
        any()
    else
      /*
       * No var-args in play, just use the number of arguments to the `newInstance(..)` to determine
       * which constructors may be called.
       */
      matchConstructorArguments(result, getNumArgument())
  }

  /**
   * Use the number of arguments to a `newInstance(..)` call to determine which constructor might be
   * called.
   *
   * If the `Constructor` is for a non-static nested type, an extra argument is expected to be
   * provided for the enclosing instance.
   */
  private predicate matchConstructorArguments(Constructor c, int numArguments) {
    if expectsEnclosingInstance(c.getDeclaringType()) then
      c.getNumberOfParameters() = numArguments - 1
    else
      c.getNumberOfParameters() = numArguments
  }

  /**
   * Return an inferred type for the constructed class.
   * 
   * To infer the constructed type we infer a type `T` for `Class<T>` or `Constructor<T>`, by inspecting
   * points to results.
   */
  RefType getInferredConstructedType() {
    // Inferred type cannot be abstract.
    not result.isAbstract() and
    // `TypeVariable`s cannot be constructed themselves.
    not result instanceof TypeVariable and
    (
      // If this is called on a `Class<T>` instance, return the inferred type `T`.
      result = inferClassParameterType(getQualifier()) or
      // If this is called on a `Constructor<T>` instance, return the inferred type `T`.
      result = inferConstructorParameterType(getQualifier()) or
      // If the result of this is cast to a particular type, then use that type.
      result = getCastInferredConstructedTypes()
    )
  }

  /**
   * If the result of this `newInstance` call is casted, infer the types that we could have
   * constructed based on the cast. If the cast is to `Object` or `Serializable`, then we ignore the
   * cast.
   */
  private Type getCastInferredConstructedTypes() {
    exists(CastExpr cast |
      cast.getExpr() = this or cast.getExpr().(ParExpr).getExpr() = this |
      result = cast.getType() or
      (
        /*
         * If we cast the result of this method, then this is either the type specified, or a
         * sub-type of that type. Make sure we exclude overly generic types such as `Object`.
         */
        not overlyGenericType(cast.getType()) and
        hasSubtypeStar(cast.getType(), result)
      )
    )
  }
}

/**
 * A `MethodAccess` on a `Class` element.
 */
class ClassMethodAccess extends MethodAccess {
  ClassMethodAccess() {
    this.getCallee().getDeclaringType() instanceof TypeClass
  }

  /**
   * Return an inferred type for the `Class` represented by this expression.
   */
  RefType getInferredClassType() {
    // `TypeVariable`s do not have methods themselves.
    not result instanceof TypeVariable and
    // If this is called on a `Class<T>` instance, return the inferred type `T`.
    result = inferClassParameterType(getQualifier())
  }
}

/**
 * A call to `Class.getMethod(..)` or `Class.getDeclaredMethod(..)`.
 */
class ReflectiveMethodAccess extends ClassMethodAccess {
  ReflectiveMethodAccess() {
    this.getCallee().hasName("getMethod") or
    this.getCallee().hasName("getDeclaredMethod")
  }

  /**
   * A `Method` that is inferred to be accessed by this reflective use of `getMethod(..)`.
   */
  Method inferAccessedMethod() {
    (
      if this.getCallee().hasName("getDeclaredMethod") then
        // The method must be declared on the type itself.
        result.getDeclaringType() = getInferredClassType()
      else
        // The method may be declared on an inferred type or a super-type.
        getInferredClassType().inherits(result)
    )
    and
    // Only consider instances where the method name is provided as a `StringLiteral`.
    result.hasName(getArgument(0).(StringLiteral).getRepresentedString())
  }
}

/**
 * A call to `Class.getAnnotation(..)`.
 */
class ReflectiveAnnotationAccess extends ClassMethodAccess {
  ReflectiveAnnotationAccess() {
    this.getCallee().hasName("getAnnotation")
  }

  /**
   * Return a possible annotation type for this reflective annotation access.
   */
  AnnotationType getAPossibleAnnotationType() {
    result = inferClassParameterType(getArgument(0))
  }
}

/**
 * A call to `Class.getField(..)` that accesses a field.
 */
class ReflectiveFieldAccess extends ClassMethodAccess {
  ReflectiveFieldAccess() {
    this.getCallee().hasName("getField") or
    this.getCallee().hasName("getDeclaredField")
  }

  Field inferAccessedField() {
    (
      if this.getCallee().hasName("getDeclaredField") then
        // Declared fields must be on the type itself.
        result.getDeclaringType() = getInferredClassType()
      else
        (
          // This field must be public, and be inherited by one of the inferred class types.
          result.isPublic() and
          getInferredClassType().inherits(result)
        )
    ) and
    result.hasName(getArgument(0).(StringLiteral).getRepresentedString())
  }
}
