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
 * @name Direct state mutation
 * @description Mutating the state of a React component directly may lead to
 *              lost updates.
 * @kind problem
 * @problem.severity warning
 * @tags reliability
 *       frameworks/react
 * @precision high
 */

import semmle.javascript.frameworks.React

from PropWriteNode pwn, ReactComponent c
where pwn.getBase() = c.getAStateAccess()
select pwn, "Use `setState` instead of directly modifying component state."