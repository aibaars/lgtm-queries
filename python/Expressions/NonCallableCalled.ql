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
 * @name Non-callable called
 * @description A call to an object which is not a callable will raise a TypeError at runtime.
 * @kind problem
 * @tags reliability
 *       correctness
 *       types
 * @problem.severity error
 * @sub-severity high
 * @precision high
 */

import python

from Call c, ClassObject t, ControlFlowNode f, ControlFlowNode origin
where f = c.getFunc().getAFlowNode() and f.refersTo(_, t, origin) and 
      not t.isCallable() and not t.unknowableAttributes()
      and not t.isDescriptorType()
      and not t = theNoneType()

select c, "Call to a $@ of $@.", origin, "non-callable", t, t.toString()
