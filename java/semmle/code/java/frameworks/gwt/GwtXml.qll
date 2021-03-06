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

import semmle.code.xml.XML

/**
 * Whether any `*.gwt.xml` files are included in this snapshot.
 */
predicate isGwtXmlIncluded() {
  exists(GwtXmlFile webXML)
}

/** A GWT module XML file with a `.gwt.xml` suffix. */
class GwtXmlFile extends XMLFile {
  GwtXmlFile() {
    this.getName().matches("%.gwt.xml")
  }

  /** The top-level module element of a GWT module XML file. */
  GwtModuleElement getModuleElement() {
    result = this.getAChild()
  }

  /** The name of an inherited GWT module, for example `com.google.gwt.user.User`. */
  string getAnInheritedModuleName() {
    result = getModuleElement().getAnInheritsElement().getAnInheritedName()
  }

  /** A GWT module XML file (from source) inherited from this module. */
  GwtXmlFile getAnInheritedXmlFile() {
    exists(GwtXmlFile f, string name |
      name = getAnInheritedModuleName() and
      f.getName().matches("%/" + name.replaceAll(".","/") + ".gwt.xml") and
      result = f
    )
  }

  /** The relative path of the folder containing this GWT module XML file. */
  string getRelativeRootFolderPath() {
    result = getParentContainer().getRelativePath()
  }

  /** A GWT-translatable source sub-folder explicitly defined in a `<source>` element. */
  string getAnExplicitSourceSubPath() {
    result = getModuleElement().getASourceElement().getASourcePath()
  }

  /**
   * A GWT-translatable source sub-folder of this GWT module XML file.
   * Either the default `client` folder or as specified by `<source>` tags.
   */
  string getASourceSubPath() {
    (result = "client" and not exists(getAnExplicitSourceSubPath())) or
    result = getAnExplicitSourceSubPath()
  }

  /**
   * A translatable source folder of this GWT module XML file.
   * Either the default `client` folder or as specified by `<source>` tags.
   * (Includes the full relative root folder path of the GWT module.)
   */
  string getARelativeSourcePath() {
    result = getRelativeRootFolderPath() + "/" + getASourceSubPath()
  }
}

/** The top-level `<module>` element of a GWT module XML file. */
class GwtModuleElement extends XMLElement {
  GwtModuleElement() {
    this.getParent() instanceof GwtXmlFile and
    this.getName() = "module"
  }

  /** An element of the form `<inherits>`, which specifies a GWT module to inherit. */
  GwtInheritsElement getAnInheritsElement() {
    result = this.getAChild()
  }

  /** An element of the form `<entry-point>`, which specifies a GWT entry-point class name. */
  GwtEntryPointElement getAnEntryPointElement() {
    result = this.getAChild()
  }

  /** An element of the form `<source>`, which specifies a GWT-translatable source path. */
  GwtSourceElement getASourceElement() {
    result = this.getAChild()
  }
}

/** An `<inherits>` element within a GWT module XML file. */
class GwtInheritsElement extends XMLElement {
  GwtInheritsElement() {
    this.getParent() instanceof GwtModuleElement and
    this.getName() = "inherits"
  }

  /** The name of an inherited GWT module, for example `com.google.gwt.user.User`. */
  string getAnInheritedName() {
    result = getAttribute("name").getValue()
  }
}

/** An `<entry-point>` element within a GWT module XML file. */
class GwtEntryPointElement extends XMLElement {
  GwtEntryPointElement() {
    this.getParent() instanceof GwtModuleElement and
    this.getName() = "entry-point"
  }

  /** The name of a class that serves as a GWT entry-point. */
  string getClassName() {
    result = getAttribute("class").getValue().trim()
  }
}

/** A `<source>` element within a GWT module XML file. */
class GwtSourceElement extends XMLElement {
  GwtSourceElement() {
    this.getParent() instanceof GwtModuleElement and
    this.getName() = "source"
  }

  /** A path specified to be GWT translatable source code. */
  string getASourcePath() {
    result = getAttribute("path").getValue() and
    // Conservative approximation, ignoring Ant-style `FileSet` semantics.
    not exists(getAChild()) and
    not exists(getAttribute("includes")) and
    not exists(getAttribute("excludes"))
  }
}

/** A `<servlet>` element within a GWT module XML file. */
class GwtServletElement extends XMLElement {
  GwtServletElement() {
    this.getParent() instanceof GwtModuleElement and
    this.getName() = "servlet"
  }

  /** The name of a class that is used as a servlet. */
  string getClassName() {
    result = getAttribute("class").getValue().trim()
  }
}
