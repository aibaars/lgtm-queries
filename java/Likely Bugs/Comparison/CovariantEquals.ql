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
 * @name Overloaded equals
 * @description Defining 'Object.equals', where the parameter of 'equals' is not of the 
 *              appropriate type, overloads 'equals' instead of overriding it.
 * @kind problem
 * @problem.severity error
 */
import default

from RefType t, Method equals
where t.fromSource() and
      equals = t.getAMethod() and
      equals.hasName("equals") and 
      equals.getNumberOfParameters() = 1 and 
      not t.getAMethod() instanceof EqualsMethod
select equals, "To override the equals method, the parameter "
               + "must be of type java.lang.Object."