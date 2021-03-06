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
 * Provides classes for working with JavaScript programs, as well as JSON, YAML and HTML.
 */

import semmle.javascript.Files
import semmle.javascript.Paths
import semmle.javascript.AST
import semmle.javascript.Expr
import semmle.javascript.Stmt
import semmle.javascript.Comments
import semmle.javascript.Functions
import semmle.javascript.Lines
import semmle.javascript.Variables
import semmle.javascript.Errors
import semmle.javascript.Regexp
import semmle.javascript.Tokens
import semmle.javascript.Externs
import semmle.javascript.JSLint
import semmle.javascript.Templates
import semmle.javascript.JSDoc
import semmle.javascript.JSON
import semmle.javascript.NodeJS
import semmle.javascript.NPM
import semmle.javascript.YAML
import semmle.javascript.AMD
import semmle.javascript.Classes
import semmle.javascript.Modules
import semmle.javascript.ES2015Modules
import semmle.javascript.JSX
import semmle.javascript.HTML
import semmle.javascript.StandardLibrary
import semmle.javascript.Util