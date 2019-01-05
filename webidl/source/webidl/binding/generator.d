module webidl.binding.generator;

import std.stdio;
import webidl.grammar;
import pegged.grammar : ParseTree;

import std.array : appender, array, Appender;
import std.algorithm : each, sort, schwartzSort, filter, uniq, sum, max, maxElement, copy;
  import std.algorithm : each, joiner, map;
import std.range : chain, enumerate;
import std.conv : text, to;
  import std.range : zip, only;
import std.typecons : Flag, No, Yes;
import openmethods;

enum dKeywords = ["abstract","alias","align","asm","assert","auto","body","bool","break","byte","case","cast","catch","cdouble","cent","cfloat","char","class","const","continue","creal","dchar","debug","default","delegate","delete","deprecated","do","double","else","enum","export","extern","false","final","finally","float","for","foreach","foreach_reverse","function","goto","idouble","if","ifloat","immutable","import","in","inout","int","interface","invariant","ireal","is","lazy","long","macro","mixin","module","new","nothrow","null","out","override","package","pragma","private","protected","public","pure","real","ref","return","scope","shared","short","static","struct","super","switch","synchronized","template","this","throw","true","try","typedef","typeid","typeof","ubyte","ucent","uint","ulong","union","unittest","ushort","version","void","wchar","while","with","__FILE__","__FILE_FULL_PATH__","__MODULE__","__LINE__","__FUNCTION__","__PRETTY_FUNCTION__","__gshared","__traits","__vector","__parameters","__DATE__","__EOF__","__TIME__","__TIMESTAMP__","__VENDOR__","__VERSION__"];

mixin(registerMethods);

enum FunctionType { Function = 1, Attribute = 2, Static = 4, OpIndex = 8, OpIndexAssign = 16, OpDispatch = 32, Getter = 64, Setter = 128, Deleter = 256, Includes = 512, Partial = 1024 };

struct Argument {
  string name;
  ParseTree type;
  ParseTree default_;
  bool templated = false;
}

struct JsExportFunction {
  string parentTypeName;
  string name;
  Argument[] args;
  ParseTree result;
  FunctionType type;
  string manglePostfix;
}

struct DBindingFunction {
  string parentTypeName;
  string name;
  Argument[] args;
  ParseTree result;
  FunctionType type;
  string manglePostfix;
  string baseType;
  string customName;
}

struct DImportFunction {
  string parentTypeName;
  string name;
  Argument[] args;
  ParseTree result;
  FunctionType type;
  string manglePostfix;
}

interface Node {
}
class ModuleNode : Node {
  Module module_;
  Node[] children;
  this(Module module_, Node[] children) {
    this.module_ = module_;
    this.children = children;
  }
}
class ConstNode : Node {
  string type;
  string name;
  string value;
  this(string type, string name, string value) {
    this.type = type;
    this.name = name;
    this.value = value;
  }
}

class StructNode : Node {
  string name;
  ParseTree baseType;
  Node[] children;
  Flag!"isStatic" isStatic;
  this(string name, ParseTree baseType , Node[] children, Flag!"isStatic" isStatic = No.isStatic) {
    this.name = name;
    this.baseType = baseType;
    this.children = children;
    this.isStatic = isStatic;
  }
}

void toDBinding(virtual!Node node, Semantics semantics, IndentedStringAppender* a);
void toDBinding(virtual!Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a);
void toJsExport(virtual!Node node, Semantics semantics, IndentedStringAppender* a);
void toJsExport(virtual!Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a);
void toDImport(virtual!Node node, Semantics semantics, IndentedStringAppender* a);
void toDImport(virtual!Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a);

@method void _toDBinding(Node node, Semantics semantics, IndentedStringAppender* a) {}
@method void _toDBinding(ModuleNode node, Semantics semantics, IndentedStringAppender* a) {
  node.children.each!(c => toDBinding(c, semantics, a));
}
@method void _toJsExport(Node node, Semantics semantics, IndentedStringAppender* a) {}
@method void _toJsExport(ModuleNode node, Semantics semantics, IndentedStringAppender* a) {
  node.children.each!(c => toJsExport(c, semantics, a));
}
@method void _toJsExport(StructNode node, Semantics semantics, IndentedStringAppender* a) {
  node.children.each!(c => toJsExport(c, node, semantics, a));
}
@method void _toDImport(Node node, Semantics semantics, IndentedStringAppender* a) {}
@method void _toDImport(ModuleNode node, Semantics semantics, IndentedStringAppender* a) {
  node.children.each!(c => toDImport(c, semantics, a));
}
@method void _toDImport(StructNode node, Semantics semantics, IndentedStringAppender* a) {
  node.children.each!(c => toDImport(c, node, semantics, a));
}

@method void _toDBinding(StructNode node, Semantics semantics, IndentedStringAppender* a) {
  a.putLn(["struct ", node.name.friendlyName, " {"]);
  a.indent();
  if (node.isStatic == Yes.isStatic) {
    a.putLn("static:");
  } else if (node.baseType != ParseTree.init) {
    a.put(node.baseType.matches[0].friendlyName);
    a.putLn(" _parent;");
    a.putLn("alias _parent this;");
  } else {
    a.putLn("JsHandle handle;");
    a.putLn("alias handle this;");
  }
  node.children.each!(c => toDBinding(c, node, semantics, a));
  a.undent();
  a.putLn("}");
}

@method void _toDBinding(Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  // default od nothing
}
@method void _toJsExport(Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  // default od nothing
}
@method void _toDImport(Node node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  // default od nothing
}
@method void _toDBinding(ConstNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  a.putLn(["enum ", node.type, " ", node.name, " = ", node.value, ";"]);
}

class StructIncludesNode : Node {
  string name;
  string baseType;
  Node[] children;
  this(string baseType, string name, Node[] children) {
    this.name = name;
    this.baseType = baseType;
    this.children = children;
  }
}

@method void _toDBinding(StructIncludesNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  auto dummyParent = new StructNode(node.name, ParseTree.init, node.children);
  node.children.each!(c => toDBinding(c, dummyParent, semantics, a));
}
@method void _toJsExport(StructIncludesNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  auto dummyParent = new StructNode(node.name, ParseTree.init, node.children);
  node.children.each!(c => toJsExport(c, dummyParent, semantics, a));
}
@method void _toDImport(StructIncludesNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  auto dummyParent = new StructNode(node.name, ParseTree.init, node.children);
  node.children.each!(c => toDImport(c, dummyParent, semantics, a));
}

class FunctionNode : Node {
  string name;
  Argument[] args;
  ParseTree result;
  FunctionType type;
  string manglePostfix;
  string baseType;
  string customName;
  this(string name, Argument[] args, ParseTree result, FunctionType type, string manglePostfix, string baseType, string customName) {
    this.name = name;
    this.args = args;
    this.result = result;
    this.type = type;
    this.manglePostfix = manglePostfix;
    this.baseType = baseType;
    this.customName = customName;
  }
}

@method void _toDBinding(FunctionNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  auto tmp = DBindingFunction(parent.name, node.name, node.args, node.result, node.type, node.manglePostfix, node.baseType, node.customName);
  if (parent.isStatic == Yes.isStatic)
    tmp.type |= FunctionType.Static;
  semantics.dump(tmp, a);
}
@method void _toJsExport(FunctionNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  if (node.type & (FunctionType.OpDispatch))
    return;
  auto tmp = JsExportFunction(parent.name, node.customName != "" ? node.customName : node.name, node.args, node.result, node.type, node.manglePostfix);
  if (parent.isStatic == Yes.isStatic)
    tmp.type |= FunctionType.Static;
  auto context = Context(semantics);
  context.dump(tmp, a);
}
@method void _toDImport(FunctionNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  if (node.type & (FunctionType.OpDispatch))
    return;
  auto tmp = DImportFunction(parent.name, node.customName != "" ? node.customName : node.name, node.args, node.result, node.type, node.manglePostfix);
  if (parent.isStatic == Yes.isStatic)
    tmp.type |= FunctionType.Static;
  semantics.dump(tmp, a);
}

class TypedefNode : Node {
  string name;
  string def;
  ParseTree rhs;
  this(string n, string d, ParseTree rhs) {
    name = n;
    def = d;
    this.rhs = rhs;
  }
}
@method void _toDBinding(TypedefNode node, Semantics semantics, IndentedStringAppender* a) {
  a.putLn(["alias ", node.name, " = ", node.def, ";"]);
}

class EnumNode : Node {
  string name;
  string content;
  this(string n, string c) {
    name = n;
    content = c;
  }
}

@method void _toDBinding(EnumNode node, Semantics semantics, IndentedStringAppender* a) {
  a.putLn(["enum ", node.name, " {"]);
  a.indent();
  a.putLn(node.content);
  a.undent();
  a.putLn("}");
}

class MaplikeNode : Node {
  string keyType;
  string valueType;
  this(string keyType, string valueType) {
    this.keyType = keyType;
    this.valueType = valueType;
  }
}

@method void _toDBinding(MaplikeNode node, StructNode parent, Semantics semantics, IndentedStringAppender* a) {
  a.putLn("uint size() {");
  a.putLn("  return Maplike_size(handle);");
  a.putLn("}");
  a.putLn("void clear() {");
  a.putLn("  Maplike_clear(handle);");
  a.putLn("}");
  a.putLn(["void delete_(",node.keyType," key) {"]);
  a.putLn("  Maplike_delete(handle, key);");
  a.putLn("}");
  a.putLn(["Iterator!(ArrayPair!(",node.keyType,", ",node.valueType,")) entries() {"]);
  a.putLn(["  return Iterator!(ArrayPair!(",node.keyType,", ",node.valueType,"))(Maplike_entries(handle));"]);
  a.putLn("}");
  a.putLn(["void forEach(void delegate(",node.keyType,", JsHandle, JsHandle) callback) {"]);
  a.putLn("  Maplike_forEach(handle, callback);");
  a.putLn("}");
  a.putLn(["",node.valueType," get(",node.keyType," key) {"]);
  a.putLn(["  return ",node.valueType,"(Maplike_get(handle, key));"]);
  a.putLn("}");
  a.putLn(["bool has(",node.keyType," key) {"]);
  a.putLn("  return Maplike_has(handle, key);");
  a.putLn("}");
  a.putLn(["Iterator!(",node.keyType,") keys() {"]);
  a.putLn(["  return Iterator!(",node.keyType,")(Maplike_keys(handle));"]);
  a.putLn("}");
  a.putLn(["void set(",node.keyType," key, ",node.valueType," value) {"]);
  a.putLn("  Maplike_set(handle, key, value.handle);");
  a.putLn("}");
  a.putLn(["Iterator!(",node.valueType,") values() {"]);
  a.putLn(["  return Iterator!(",node.valueType,")(Maplike_values(handle));"]);
  a.putLn("}");
}

class CallbackNode : Node {
  string name;
  ParseTree result;
  ParseTree args;
  this(string name, ParseTree result, ParseTree args) {
    this.name = name;
    this.result = result;
    this.args = args;
  }
}

@method void _toDBinding(CallbackNode node, Semantics semantics, IndentedStringAppender* a) {
  a.put(["alias ", node.name, " = "]);
  if (node.result.matches[0] == "void") {
    a.put("void");
  } else
    node.result.generateDType(a, Context(semantics));
  auto types = node.args.extractTypes.map!(arg => arg.generateDType(Context(semantics))).joiner(", ").text;
  a.putLn([" delegate(", types, ");"]);
}



void dumpJsArgument(Appender)(ref Semantics semantics, Argument arg, ref Appender a) {
  if (semantics.isNullable(arg.type)) {
    a.put(arg.name);
    a.put("Defined ? ");
  }
  if (semantics.isUnion(arg.type) || semantics.isEnum(arg.type)) {
    a.put("spasm.decode_");
    arg.type.mangleTypeJsImpl(a, semantics, MangleTypeJsContext(true));
    a.put("(");
    a.put(arg.name);
    a.put(")");
  } else if (semantics.isStringType(arg.type)) {
    a.put(["spasm.decode_string(",arg.name,"Len, ",arg.name,"Ptr)"]);
  } else if (semantics.isCallback(arg.type.matches[0])){
    string callbackName = semantics.getType(arg.type).mangleTypeJs(semantics);

    auto argList = semantics.getArgumentList(arg.type);
    auto arguments = extractArguments(argList);
    auto types = extractTypes(argList);
    string base = arg.name;
    a.put([ "(", arguments.joiner(", ").text, ")=>{spasm.", callbackName, "(", base, "Ctx, ", base ~ "Ptr, "]);
    zip(arguments, types).each!((t) {
      auto arg = t[0];
      auto type = t[1];
      bool needsClose = false;
      if (semantics.isStringType(type) || semantics.isUnion(type)
        || semantics.isNullable(type) || semantics.isEnum(type))
      {
        a.put("spasm.encode_");
        if (type.name == "WebIDL.TypeWithExtendedAttributes")
          type.children[1].mangleTypeJs(a, semantics);
        else
          type.mangleTypeJs(a, semantics);
        needsClose = true;
        if (false)//rawResult) //TODO: don't know how to return rawResult
          a.put("(rawResult, ");
        else
          a.put("(");
      }
      else if (!semantics.isPrimitive(type))
      {
        a.put(["spasm.addObject("]);
        needsClose = true;
      }
      a.put(arg);
      if (needsClose)
        a.put(")");
    });
    a.put(")}");
  } else if (semantics.isPrimitive(arg.type)) {
    a.put(arg.name);
  } else {
    a.put(["spasm.objects[",arg.name,"]"]);
  }
  if (semantics.isNullable(arg.type)) {
    a.put(" : undefined");
  }
}

void dumpJsArguments(Appender)(ref Semantics semantics, Argument[] args, ref Appender a) {
  if (args.length == 0)
    return;
  foreach(arg; args[0..$-1]) {
    semantics.dumpJsArgument(arg, a);
    a.put(", ");
  }
  semantics.dumpJsArgument(args[$-1], a);
}

void dump(Appender)(ref Context context, JsExportFunction item, ref Appender a) {
  auto semantics = context.semantics;
  a.put(mangleName(item.parentTypeName,item.name,item.manglePostfix));
  a.put(": function(");
  bool rawResult = item.result != ParseTree.init && semantics.isRawResultType(item.result);
  if (rawResult)
    a.put("rawResult, ");
  if (!(item.type & FunctionType.Static)) {
    a.put("ctx");
    if (item.args.length > 0)
      a.put(", ");
  }
  item.args.enumerate.each!((e){
      auto arg = e.value;
      if (e.index > 0)
        a.put(", ");
      a.put(arg.name);
      if (semantics.isNullable(arg.type))
        a.put(["Defined, ", arg.name]);
      if (semantics.isCallback(arg.type.matches[0]))
        a.put(["Ctx, ", arg.name, "Ptr"]);
      else if (semantics.isStringType(arg.type))
        a.put(["Len, ", arg.name, "Ptr"]);
    });
  a.putLn(") {");
  a.indent();
  bool returns = item.result != ParseTree.init && item.result.matches[0] != "void";
  bool needsClose = false;
  if (returns) {
    if (!rawResult)
      a.put("return ");
    if (semantics.isStringType(item.result) || semantics.isUnion(item.result) || semantics.isNullable(item.result) || semantics.isEnum(item.result)) {
      a.put("spasm.encode_");
      if (item.result.name == "WebIDL.TypeWithExtendedAttributes")
        item.result.children[1].mangleTypeJs(a, semantics);
      else
        item.result.mangleTypeJs(a, semantics);
      needsClose = true;
      if (rawResult)
        a.put("(rawResult, ");
      else
        a.put("(");
    } else if (!semantics.isPrimitive(item.result)) {
      a.put(["spasm.addObject("]);
      needsClose = true;
    }
  }
  if (item.type & FunctionType.Deleter)
    a.put("delete ");
  if (item.type & FunctionType.Static)
    a.put(item.parentTypeName);
  else
    a.put("spasm.objects[ctx]");
  if (item.type & (FunctionType.Getter | FunctionType.Setter | FunctionType.Deleter)) {
    a.put("[");
    semantics.dumpJsArgument(item.args[0], a);
    a.put("]");
    if (item.type & FunctionType.Setter) {
      a.put(" = ");
      semantics.dumpJsArgument(item.args[1], a);
    }
  } else {
    a.put(".");
    a.put(item.name);
    if (item.type & FunctionType.Attribute) {
      if (!returns) {
        a.put(" = ");
        semantics.dumpJsArgument(item.args[0], a);
      }
    } else {
      a.put("(");
      semantics.dumpJsArguments(item.args, a);
      a.put(")");
    }
  }
  if (needsClose)
    a.put(")");
  a.putLn(";");
  a.undent();
  a.putLn("},");
}

void dump(Appender)(ref Semantics semantics, DImportFunction item, ref Appender a) {
  auto context = Context(semantics);
  a.put("extern (C) ");
  if (item.result == ParseTree.init || item.result.matches[0] == "void")
    a.put("void");
  else {
    if (!semantics.isPrimitive(item.result) && !semantics.isUnion(item.result) && !semantics.isNullable(item.result)) {
      a.put("JsHandle");
    } else {
      item.result.generateDType(*a, context);
    }
  }
  a.put(" ");
  a.put(mangleName(item.parentTypeName,item.name,item.manglePostfix));
  a.put("(");
  if (!(item.type & FunctionType.Static)) {
    a.put("JsHandle");
    if (item.args.length > 0)
      a.put(", ");
  }
  if (item.args.length > 0) {
    item.args.map!(arg => arg.type).array.putWithDelimiter!(generateDImports)(", ", *a, context);
  }
  a.putLn(");");
}

void dump(Appender)(ref Semantics semantics, DBindingFunction item, ref Appender a) {
  if (item.result != ParseTree.init) {
    item.result.generateDType(a, Context(semantics));
    a.put(" ");
  } else
    a.put("void ");
  switch (item.type & (FunctionType.OpIndex | FunctionType.OpDispatch | FunctionType.OpIndexAssign)) {
  case FunctionType.OpIndex:
    a.put("opIndex");
    break;
  case FunctionType.OpDispatch:
    a.put("opDispatch");
    break;
  case FunctionType.OpIndexAssign:
    a.put("opIndexAssign");
    break;
  default:
    a.put(item.name.friendlyName);
    break;
  }
  auto templArgs = item.args.filter!(a => a.templated).array();
  auto runArgs = item.args.filter!(a => !a.templated).array();
  if (templArgs.length > 0) {
    a.put("(");
    semantics.dumpDParameters(templArgs, a);
    a.put(")");
  }
  a.put("(");
  if (item.type & FunctionType.OpIndexAssign) {
    assert(runArgs.length > 1);
    semantics.dumpDParameter(runArgs[$-1], a);
    a.put(", ");
    semantics.dumpDParameters(runArgs[0..$-1], a);
  } else
    semantics.dumpDParameters(runArgs, a);
  a.putLn(") {");
  a.indent();
  bool returns = item.result != ParseTree.init && item.result.matches[0] != "void";
  if (returns) {
    a.put("return ");
    if (!semantics.isPrimitive(item.result) && !semantics.isUnion(item.result) && !semantics.isNullable(item.result)) {
      item.result.generateDType(a, Context(semantics));
      a.put("(");
    }
  }
  a.put(mangleName(item.parentTypeName, item.customName.length > 0 ? item.customName : item.name,item.manglePostfix));
  a.put("(");
  if (!(item.type & FunctionType.Static)) {
    a.put("handle");
    if (item.args.length > 0)
      a.put(", ");
  }
  semantics.dumpDJsArguments(item.args, a);
  if (returns) {
    if (!semantics.isPrimitive(item.result) && !semantics.isUnion(item.result) && !semantics.isNullable(item.result)) {
      a.put(")");
    }
  }
  a.putLn(");");
  a.undent();
  a.putLn("}");
}
void dumpDParameters(Appender)(ref Semantics semantics, Argument[] args, ref Appender a) {
  if (args.length == 0)
    return;
  foreach(arg; args[0..$-1]) {
    semantics.dumpDParameter(arg, a);
    a.put(", ");
  }
  semantics.dumpDParameter(args[$-1], a);
}
void dumpDParameter(Appender)(ref Semantics semantics, Argument arg, ref Appender a) {
  arg.type.generateDType(a, Context(semantics));
  a.put(" ");
  a.putCamelCase(arg.name.friendlyName);
  if (arg.default_.matches.length > 1) {
    a.put(" ");
    if (arg.default_.children[0].matches[0] == "null") {
      if (semantics.isNullable(arg.type)) {
        a.put("/* = no!(");
        arg.type.generateDType(a, Context(semantics).withSkipOptional);
        a.put(") */");
        return;
      }
    }
    arg.default_.generateDType(a, Context(semantics));
  }
}

void dumpDJsArguments(Appender)(ref Semantics semantics, Argument[] args, ref Appender a) {
  if (args.length == 0)
    return;
  foreach(arg; args[0..$-1]) {
    semantics.dumpDJsArgument(arg, a);
    a.put(", ");
  }
  semantics.dumpDJsArgument(args[$-1], a);
}

void dumpDJsArgument(Appender)(ref Semantics semantics, Argument arg, ref Appender a) {
  bool optional = semantics.isNullable(arg.type);
  if (optional)
    a.put("!");
  a.put(arg.name.friendlyName);
  if (optional)
    a.put([".empty, ", arg.name.friendlyName, ".value"]);
  if (!semantics.isPrimitive(arg.type) && !semantics.isUnion(arg.type))
    a.put(".handle");
}

bool isKeyword(string s) {
  import std.algorithm : canFind;
  return dKeywords.canFind(s);
}

string friendlyName(string s) {
  import std.ascii;
  import std.conv : text;
  import std.utf : byChar;
  if (s.length == 0)
    return s;
  if (s.isKeyword)
    return s~"_";
  string clean = s.byChar.map!(c => c.isAlphaNum ? c : '_').text;
  if (!clean[0].isAlpha && clean[0] != '_')
    return '_'~clean;
  return clean;
}

struct IndentedStringAppender {
  import std.array : Appender;
  import std.algorithm : each;
  bool beginLine = true;
  Appender!string appender;
  int i = 0;
  void put(char c) {
    putIndent();
    appender.put(c);
  }
  void put(string s) {
    putIndent();
    appender.put(s);
  }
  void put(string[] ss) {
    putIndent();
    ss.each!(s => appender.put(s));
  }
  void putLn(char c) {
    put(c);
    appender.put("\n");
    beginLine = true;
  }
  void putLn(string s) {
    put(s);
    appender.put("\n");
    beginLine = true;
  }
  void putLn(string[] ss) {
    put(ss);
    appender.put("\n");
    beginLine = true;
  }
  void putIndent() {
    if (!beginLine)
      return;
    beginLine = false;
    import std.range : repeat;
    import std.algorithm : copy;
    ' '.repeat(i*2).copy(appender);
  }
  void indent() {
    i++;
  }
  void undent() {
    import std.algorithm : max;
    i = max(0, i-1);
  }
  auto data() {
    return appender.data;
  }
}

struct Context {
  Semantics semantics;
  ParseTree extendedAttributeList;
  ParseTree partial;
  ParseTree includes;
  bool readonly = false;
  bool primitiveType = false;
  bool sumType = false;
  bool optional = false;
  bool returnType = false;
  bool isIncludes = false;
  bool skipOptional = false;
  string typeName;
  string customName;
}

auto withSkipOptional(Context c) {
  c.skipOptional = true;
  return c;
}

bool isEnum(ref Context context, ParseTree tree) {
  return context.semantics.isEnum(tree);
}
bool isEnum(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isEnum(tree.children[1]);
  return semantics.isEnum(tree.matches[0]);
}

bool isEnum(ref Semantics semantics, string typeName) {
  if (auto p = typeName in semantics.types) {
    return p.tree.name == "WebIDL.Enum";
  }
  return false;
}
bool isNullableTypedef(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isNullableTypedef(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isNullableTypedef(tree.children[1]);
  assert(tree.name == "WebIDL.Type" || tree.name == "WebIDL.UnionMemberType");
  if (tree.name == "WebIDL.UnionMemberType" && tree.children[0].name == "WebIDL.UnionType")
    return false;
  string typeName = tree.getTypeName();
  if (!semantics.isTypedef(typeName))
    return false;
  if (tree.matches[$-1] == "?")
    return true;
  return false;
}

bool isTypedef(ref Context context, ParseTree tree) {
  return context.semantics.isTypedef(tree);
}

bool isTypedef(ref Semantics semantics, ParseTree tree) {
  string typeName = tree.getTypeName();
  return semantics.isTypedef(typeName);
}

bool isTypedef(ref Context context, string typeName) {
  return context.semantics.isTypedef(typeName);
}
bool isTypedef(ref Semantics semantics, string typeName) {
  if (auto p = typeName in semantics.types) {
    return p.tree.name == "WebIDL.Typedef";
  }
  return false;
}
bool isCallback(ref Context context, string typeName) {
  return context.semantics.isCallback(typeName);
}
bool isCallback(ref Semantics semantics, string typeName) {
  if (auto p = typeName in semantics.types) {
    return p.tree.name == "WebIDL.CallbackRest";
  }
  return false;
}

bool isPartial(ref Context context) {
  return context.partial.matches.length > 0;
}

void putCamelCase(Appender)(ref Appender a, string s) {
  import std.algorithm : until;
  import std.uni : isUpper, isLower, asLowerCase;
  import std.conv : text;
  if (s.length == 0)
    return;
  if (s[0].isLower) {
    a.put(s);
    return;
  }
  import std.string : toLower;
  auto head = s.until!(isLower).asLowerCase.text;
  if (head.length == 1) {
    a.put(head);
    a.put(s[head.length .. $]);
    return;
  }
  auto tail = s[head.length-1 .. $];
  a.put(head[0..$-1]);
  a.put(tail);
}

string toCamelCase(string s) {
  auto app = appender!string;
  app.putCamelCase(s);
  return app.data;
}

string mangleName(string typeName, string name, string appendix = "") {
  import std.ascii : toLower, toUpper;
  import std.array : appender;
  auto app = appender!string;
  app.put(typeName);
  app.put("_");
  app.put(name);
  if (appendix.length > 0) {
    app.put("_");
    app.put(appendix);
  }
  return app.data;
}

bool isNullable(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isNullable(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isNullable(tree.children[1]);
  if (tree.name == "WebIDL.UnionMemberType")
    return tree.matches[$-1] == "?";
  assert(tree.name == "WebIDL.Type");
  if (tree.matches[$-1] == "?")
    return true;
  string typeName = tree.getTypeName();
  if (semantics.isTypedef(typeName)) {
    return semantics.isNullable(semantics.getAliasedType(typeName));
  }
  return false;
}

bool isRawResultType(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isRawResultType(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isRawResultType(tree.children[1]);
  assert(tree.name == "WebIDL.Type");
  return semantics.isNullable(tree) ||
    semantics.isStringType(tree) || semantics.isUnion(tree);
}

bool isStringType(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isStringType(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isStringType(tree.children[1]);
  assert(tree.name == "WebIDL.Type");
  string typeName = tree.getTypeName();
  if (semantics.isTypedef(typeName)) {
    return semantics.isStringType(semantics.getAliasedType(typeName));
  }
  if (tree.children[0].name != "WebIDL.SingleType")
    return false;
  if (tree.children[0].matches[0] == "any")
    return false;
  if (tree.children[0].children[0].children[0].name == "WebIDL.StringType")
    return true;
  return false;
}
bool isUnion(ref Context context, ParseTree tree) {
  return context.semantics.isUnion(tree);
}

bool isUnion(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isUnion(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isUnion(tree.children[1]);
  assert(tree.name == "WebIDL.Type" || tree.name == "WebIDL.UnionMemberType");
  if (tree.children[0].name == "WebIDL.UnionType")
    return true;
  string typeName = tree.getTypeName();
  if (semantics.isTypedef(typeName)) {
    return semantics.isUnion(semantics.getAliasedType(typeName));
  }
  return false;
}
auto getAliasedType(ref Context context, string typeName) {
  assert(typeName in context.semantics.types);
  assert(context.semantics.types[typeName].tree.name == "WebIDL.Typedef");
  return context.semantics.types[typeName].tree.children[0];
}

auto getAliasedType(ref Semantics semantics, string typeName) {
  assert(typeName in semantics.types);
  assert(semantics.types[typeName].tree.name == "WebIDL.Typedef");
  return semantics.types[typeName].tree.children[0];
}

bool isPrimitive(Context context, ParseTree tree) {
  return context.semantics.isPrimitive(tree);
}

bool isPrimitive(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    if (tree.matches[0] == "void")
      return false;
    return semantics.isPrimitive(tree.children[0]);
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.isPrimitive(tree.children[1]);
  assert(tree.name == "WebIDL.Type");
  string typeName = tree.getTypeName();
  if (semantics.isEnum(typeName) || semantics.isCallback(typeName))
    return true;
  if (semantics.isTypedef(typeName)) {
    return semantics.isPrimitive(semantics.getAliasedType(typeName));
  }
  if (tree.children[0].name != "WebIDL.SingleType")
    return false;
  if (tree.children[0].matches[0] == "any")
    return false;
  if (tree.children[0].matches[0] == "DOMString")
    return true;
  if (tree.children[0].children[0].name != "WebIDL.NonAnyType")
    return false;
  return tree.children[0].children[0].children[0].name == "WebIDL.PrimitiveType";
}

string getTypeName(ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType") {
    assert(tree.matches[0] != "void");
    return tree.children[0].getTypeName();
  }
  assert(tree.name == "WebIDL.TypeWithExtendedAttributes" || tree.name == "WebIDL.Type" || tree.name == "WebIDL.UnionMemberType");
  if (tree.name == "WebIDL.UnionMemberType") {
    assert(tree.children[1].name == "WebIDL.NonAnyType");
    return tree.children[1].matches[0];
  }
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return tree.children[1].matches[0];
  return tree.matches[0];
}

auto isEmpty(string s) {
  return s == "";
}
auto isEmpty(string[] matches) {
  import std.algorithm : all;
  return matches.length == 0 || matches.all!(m => m.isEmpty);
}

template putWithDelimiter(alias Generator)
{
  void putWithDelimiter(Appender, Ts...)(ParseTree[] children, string delimiter,ref Appender a, Ts args) {
    import std.algorithm : each, filter;
    import std.array : array;
    auto nonEmpty = children.filter!(c => !c.matches.isEmpty).array;
    // need to filter first
    if (nonEmpty.length > 0) {
      nonEmpty[0..$-1].each!((c){if (c.matches.isEmpty) return; Generator(c, a, args);a.put(delimiter);});
      Generator(nonEmpty[$-1], a, args);
    }
  }
}

auto extractArgument(ParseTree tree) {
  assert(tree.name == "WebIDL.Argument");
  auto argRest = tree.children[$-1];
  if (argRest.matches[0] == "optional") {
    return argRest.children[1].matches[0];
  } else {
    return argRest.children[2].matches[0];
  }
}
auto extractDefault(ParseTree tree) {
  assert(tree.name == "WebIDL.Argument");
  auto argRest = tree.children[$-1];
  string typeName;
  if (argRest.matches[0] == "optional") {
    return argRest.children[2];
  } else {
    return ParseTree.init;
  }
}
auto extractType(ParseTree tree) {
  assert(tree.name == "WebIDL.Argument");
  auto argRest = tree.children[$-1];
  string typeName;
  if (argRest.matches[0] == "optional") {
    return argRest.children[0].children[1];
  } else {
    return argRest.children[0];
  }
}

string extractTypeName(ParseTree tree) {
  if (tree.name == "WebIDL.Argument") {
    auto argRest = tree.children[$-1];
    if (argRest.matches[0] == "optional") {
      return extractTypeName(argRest.children[0].children[1]);
    }
    return extractTypeName(argRest.children[0]);
  }
  assert(tree.name == "WebIDL.Type");
  string typeName = tree.matches[0];
  if (typeName == "any")
    return "Any";
  if (typeName == "DOMString")
    return "string";
  if (typeName == "boolean")
    return "bool";
  return typeName;
}
auto extractArguments(ParseTree tree) {
  import std.algorithm : map;
  assert(tree.name == "WebIDL.ArgumentList");
  return tree.children.map!(c => c.extractArgument);
}
auto extractDefaults(ParseTree tree) {
  import std.algorithm : map;
  assert(tree.name == "WebIDL.ArgumentList");
  return tree.children.map!(c => c.extractDefault);
}
auto extractTypes(ParseTree tree) {
  import std.algorithm : map;
  assert(tree.name == "WebIDL.ArgumentList");
  return tree.children.map!(c => c.extractType);
}
auto extractTypeNames(ParseTree tree) {
  import std.algorithm : map;
  assert(tree.name == "WebIDL.ArgumentList");
  return tree.children.map!(c => c.extractTypeName);
}
ParseTree getArgumentList(ref Semantics semantics, ParseTree tree) {
  auto p = tree.matches[0] in semantics.types;
  assert(p != null);
  assert(p.tree.name == "WebIDL.CallbackRest");
  return p.tree.children[2];
}
auto getType(ref Semantics semantics, ParseTree tree) {
  return semantics.getType(tree.matches[0]);
}
auto getType(ref Semantics semantics, string name) {
  auto p = name in semantics.types;
  if (p is null) {
    writeln("Failed to find "~name);
    return ParseTree.init;
  }
  return p.tree;
}
auto getType(ref Context context, string name) {
  return context.semantics.getType(name);
}
auto getMatchingPartials(ref Semantics semantics, string name) {
  auto isInterface = (Type p) => p.tree.children[0].children[0].name == "WebIDL.PartialInterfaceOrPartialMixin";
  auto matches = (Type p) => p.tree.children[0].children[0].children[0].children[0].matches[0] == name;
  return semantics.partials.filter!(p => isInterface(p) && matches(p)).map!(t => t.tree).array();
}

auto getMatchingPartials(ref Context context, string name) {
  return context.semantics.getMatchingPartials(name);
}

uint getSizeOf(ref Semantics semantics, ParseTree tree) {
  switch(tree.name) {
    case "WebIDL.IntegerType":
      if (tree.matches[0] == "long") {
        if (tree.matches.length > 1)
          return 8;
        return 4;
      }
      return 2;
  case "WebIDL.StringType":
    return 8;
  case "WebIDL.FloatType":
    if (tree.matches[0] == "float")
      return 4;
    return 8;
  case "WebIDL.PrimitiveType":
    if (tree.children.length == 0) {
      if (tree.matches[0] == "boolean")
        return 4;
      return 1;
    } else
      goto default;
  case "WebIDL.SingleType":
    if (tree.matches[0] == "any")
      return 4;
    goto default;
  case "WebIDL.Identifier":
  case "WebIDL.SequenceType":
  case "WebIDL.Enum":
  case "WebIDL.RecordType":
  case "WebIDL.PromiseType":
  case "WebIDL.BufferRelatedType":
    return 4;
  case "WebIDL.UnionType":
    return 4 + tree.children.map!(c => semantics.getSizeOf(c)).maxElement;
  case "WebIDL.NonAnyType":
    if (tree.matches[0] == "object" || tree.matches[0] == "symbol" || tree.matches[0] == "Error" || tree.matches[0] == "FrozenArray") {
      return 4 + semantics.getSizeOf(tree.children[$-1]);
    }
  goto default;
  case "WebIDL.Null":
    return tree.matches[0] == "?" ? 4 : 0;
  default:
    return tree.children.map!(c => semantics.getSizeOf(c)).sum;
  }
}
string mangleTypeJs(ParseTree tree, ref Semantics semantics) {
  auto app = appender!string;
  tree.mangleTypeJs(app, semantics);
  return app.data;
}
string mangleTypeJs(ParseTree tree, ref Semantics semantics, MangleTypeJsContext context) {
  auto app = appender!string;
  tree.mangleTypeJsImpl(app, semantics, context);
  return app.data;
}

struct MangleTypeJsContext {
  bool skipOptional;
  bool inUnion = false;
}
void mangleTypeJs(Appender)(ParseTree tree, ref Appender a, ref Semantics semantics) {
  MangleTypeJsContext context;
  tree.mangleTypeJsImpl(a, semantics, context);
}
void mangleTypeJsImpl(Appender)(ParseTree tree, ref Appender a, ref Semantics semantics, MangleTypeJsContext context) {
  switch (tree.name) {
  case "WebIDL.CallbackRest":
    a.put("callback_");
    tree.children[1].mangleTypeJsImpl(a, semantics, context);
    a.put("_");
    tree.children[2].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.ArgumentList":
    tree.children.putWithDelimiter!(mangleTypeJsImpl)("_", a, semantics, context);
    break;
  case "WebIDL.Argument":
    auto type = tree.extractType;
    if (!semantics.isPrimitive(type) && !semantics.isUnion(type)) {
      a.put("JsHandle");
      break;
    }
    tree.children[1].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.UnsignedIntegerType":
    if (tree.matches[0] == "unsigned")
      a.put("u");
    tree.children[0].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.IntegerType":
    if (tree.matches[0] == "long") {
      if (tree.matches.length > 1)
        a.put("long");
      else
        a.put("int");
    } else
      a.put(tree.matches[0]);
    break;
  case "WebIDL.SequenceType":
    if (!context.skipOptional && tree.matches[$-1] == "?")
      a.put("optional_");
    a.put("sequence_");
    tree.children[0].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.SingleType":
    if (tree.matches[0] == "any") {
      a.put("any");
    } else if (tree.matches[0] == "void") {
      a.put("void");
    } else {
      tree.children[0].mangleTypeJsImpl(a, semantics, context);
    }
    break;
  case "WebIDL.Type":
    string typeName = getTypeName(tree);
    if (semantics.isTypedef(typeName)) {
      if (tree.matches[$-1] == "?") {
        if (context.skipOptional)
          context.skipOptional = false;
        else
          a.put("optional_");
      }
      auto aliasMangled = semantics.getAliasedType(typeName).mangleTypeJs(semantics, context);
      if (aliasMangled.length < typeName.length)
        a.put(aliasMangled);
      else
        a.put(typeName);
      return;
    }
    if (tree.children.length == 2 && tree.children[$-1].matches[0] == "?") {
      if (context.skipOptional)
        context.skipOptional = false;
      else
        a.put("optional_");
    }
    tree.children[0].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.UnionType":
    a.put("union");
    a.put(tree.children.length.to!string);
    a.put("_");
    context.inUnion = true;
    tree.children.putWithDelimiter!(mangleTypeJsImpl)("_", a, semantics, context);
    break;
  case "WebIDL.UnionMemberType":
    if (tree.children[1].name == "WebIDL.NonAnyType")
      tree.children[1].mangleTypeJsImpl(a, semantics, context);
    else {
      tree.children[0].mangleTypeJsImpl(a, semantics, context);
      if (tree.children[$-1].matches[0] == "?")
        a.put("_Null");
    }
    break;
  case "WebIDL.NonAnyType":
    if (tree.children.length > 1 && tree.children[$-1].matches[0] == "?") {
      if (context.skipOptional)
        context.skipOptional = false;
      else
        a.put("optional_");
    }
    if (tree.children[0].name == "WebIDL.Null")
      a.put(tree.matches[0]); // Maybe return here?
    if (tree.matches[0] == "FrozenArray")
      assert(false);
    tree.children[0].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.FloatType":
    a.put(tree.matches[0]);
    break;
  case "WebIDL.TypeWithExtendedAttributes":
    tree.children[1].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.Identifier":
    auto typeName = tree.matches[0];
    if (!context.inUnion && !semantics.isEnum(tree)) {
      a.put("JsHandle");
      return;
    }
    // TODO: could be nullable typedef
    if (semantics.isTypedef(typeName)) {
      auto aliasMangled = semantics.getAliasedType(typeName).mangleTypeJs(semantics, context);
      if (aliasMangled.length < tree.matches[0].length) {
        a.put(aliasMangled);
        return;
      }
    }
    a.put(tree.matches[0]);
    break;
  case "WebIDL.StringType":
    a.put("string");
    break;
  case "WebIDL.ArgumentRest":
    tree.children[0].mangleTypeJsImpl(a, semantics, context);
    break;
  case "WebIDL.PrimitiveType":
    if (tree.children.length == 1) {
      tree.children[0].mangleTypeJsImpl(a, semantics, context);
    } else {
      switch (tree.matches[0]) {
      case "byte": a.put("byte"); break;
      case "octet": a.put("ubyte"); break;
      case "boolean": a.put("bool"); break;
      default: a.put(tree.matches[0]); break;
      }
    }
    break;
  default:
    tree.children.each!(c => c.mangleTypeJsImpl(a, semantics, context));
  }
}

void generateDImports(Appender)(ParseTree tree, ref Appender a, Context context) {
  import std.algorithm : each, joiner, map;
  import std.range : chain;
  import std.conv : text;
  switch (tree.name) {
  case "WebIDL.InterfaceRest":
  case "WebIDL.InterfaceMembers":
  case "WebIDL.InterfaceMember":
  case "WebIDL.ReadOnlyMember":
  case "WebIDL.AttributeRest":
    break;
  case "WebIDL.TypeWithExtendedAttributes":
    tree.children[1].generateDImports(a, context);
    break;
  case "WebIDL.NonAnyType":
    bool optional = !context.skipOptional && (context.optional || tree.children[$-1].name == "WebIDL.Null" && tree.children[$-1].matches[0] == "?");
    if (optional) {
      if (context.returnType)
        a.put("Optional!(");
      else
        a.put("bool, ");
    }
    if (!(optional && context.returnType) && !context.primitiveType && !context.sumType && !(context.returnType && tree.children[0].name == "WebIDL.SequenceType"))
      a.put("JsHandle");
    else
      tree.children.each!(c => c.generateDType(a, context));
    if (optional && context.returnType)
      a.put(")");
    break;
  case "WebIDL.SingleType":
    if (tree.matches[0] == "any")
      a.put("Any");
    else
      tree.children[0].generateDImports(a, context);
    break;
  case "WebIDL.PrimitiveType":
    if (tree.children.length == 0) {
      switch (tree.matches[0]) {
      case "byte": a.put("byte"); break;
      case "octet": a.put("ubyte"); break;
      case "boolean": a.put("bool"); break;
      default: a.put(tree.matches[0]); break;
      }
    } else
      tree.children[0].generateDImports(a, context);
    break;
  case "WebIDL.StringType":
    switch (tree.matches[0]) {
    case "ByteString":
      a.put(tree.matches[0]);
    break;
    default:
      a.put("string");
    break;
    }
    break;
  case "WebIDL.ArgumentName":
  case "WebIDL.AttributeName":
    break;
  case "WebIDL.UnrestrictedFloatType":
    // TODO: handle unrestricted
    tree.children[0].generateDImports(a, context);
    break;
  case "WebIDL.UnsignedIntegerType":
    if (tree.matches[0] == "unsigned")
      a.put("u");
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.IntegerType":
    if (tree.matches[0] == "long") {
      if (tree.matches.length > 1)
        a.put("long");
      else
        a.put("int");
    } else
      a.put(tree.matches[0]);
    break;
  case "WebIDL.ExtendedAttributeList":
    break;
  case "WebIDL.FloatType":
  case "WebIDL.Identifier":
    a.put(tree.matches[0]);
    break;
  case "WebIDL.SpecialOperation":
  case "WebIDL.RegularOperation":
    break;
  case "WebIDL.Type":
    context.optional = false;
    if (context.isUnion(tree)) {
      bool optional = tree.matches[$-1] == "?";
      context.optional = optional;
      if (optional) {
        if (context.returnType)
          a.put("Optional!(");
        else
          a.put("bool, ");
      }
      if (!context.isTypedef(tree))
        a.put("SumType!(");
      context.sumType = true;
      tree.children[0].children.putWithDelimiter!(generateDImports)(", ", a, context.withSkipOptional);
      if (optional && context.returnType)
        a.put(")");
      if (!context.isTypedef(tree))
        a.put(")");
      break;
    } else {
      context.primitiveType = context.isPrimitive(tree);
      tree.children[0].generateDImports(a, context);
    }
    break;
  case "WebIDL.UnionMemberType":
    context.optional = false;
    if (context.isUnion(tree)) {
      bool optional = tree.matches[$-1] == "?";
      context.optional = optional;
      if (optional) {
        if (context.returnType)
          a.put("Optional!(");
        else
          a.put("bool, ");
      }
      a.put("SumType!(");
      tree.children[0].children.putWithDelimiter!(generateDImports)(", ", a, context);
      if (optional && context.returnType)
        a.put(")");
      a.put(")");
      break;
    } else
      tree.children.each!(c => c.generateDImports(a, context));
    break;
  case "WebIDL.IncludesStatement":
    break;
  case "WebIDL.ReturnType":
    context.returnType = true;
    if (tree.children.length > 0) {
      if (context.isPrimitive(tree.children[0]) || context.isUnion(tree.children[0]) || tree.matches[$-1] == "?")
        tree.children[0].generateDImports(a, context);
      else if (tree.matches[0] != "void")
        a.put("JsHandle");
      else
        a.put("void");
    }
    else
      a.put(tree.matches[0]);
    break;
  case "WebIDL.OperationRest":
  case "WebIDL.Enum":
  case "WebIDL.Dictionary":
  case "WebIDL.DictionaryMember":
  case "WebIDL.Iterable":
  case "WebIDL.Typedef":
  case "WebIDL.SetlikeRest":
  case "WebIDL.MaplikeRest":
  case "WebIDL.CallbackRest":
  case "WebIDL.MixinRest":
    break;
  case "WebIDL.SequenceType":
    a.put("JsHandle");
    break;
  case "WebIDL.MixinMember":
  case "WebIDL.Const":
  case "WebIDL.Partial":
    break;
  case "WebIDL.PromiseType":
    a.put("Promise!(");
    tree.children[0].generateDImports(a, context);
    a.put(")");
    break;
  case "WebIDL.PartialInterfaceRest":
    tree.children[1].generateDImports(a, context);
    break;
  default:
    tree.children.each!(c => generateDImports(c, a, context));
  }
}

string orNone(string s) {
  if (s.length == 0)
    return "none";
  return s;
}
IR toIr(ref Module module_) {
  auto app = appender!(Node[]);
  module_.iterate!(toIr)(app, Context(module_.semantics));
  return new IR([new ModuleNode(module_, app.data)], module_.semantics);
}
IR toIr(ref Semantics semantics) {
  auto app = appender!(ModuleNode[]);
  foreach(module_; semantics.modules) {
    auto mApp = appender!(Node[]);
    module_.iterate!(toIr)(mApp, Context(semantics));
    app.put(new ModuleNode(module_, mApp.data));
  }
  return new IR(app.data, semantics);
}

void toIr(Appender)(ParseTree tree, ref Appender a, Context context) {
  switch (tree.name) {
  case "WebIDL.Namespace":
    // TODO: get matching partials
    auto app = appender!(Node[]);
    tree.children[1..$].each!(c => toIr(c, app, context));
    a.put(new StructNode(tree.children[0].matches[0], ParseTree.init, app.data, Yes.isStatic));
    break;
  case "WebIDL.InterfaceRest":
    ParseTree baseType;
    if (tree.children[1].children.length > 0 && tree.children[1].children[0].matches.length != 0)
      baseType = tree.children[1].children[0];
    auto app = appender!(Node[]);
    tree.children[2..$].each!(c => toIr(c, app, context));
    a.put(new StructNode(tree.children[0].matches[0], baseType, app.data));
    break;
  case "WebIDL.IncludesStatement":
    context.isIncludes = true;
    context.includes = tree;
    context.typeName = tree.children[1].matches[0];
    ParseTree mixinRest = context.getType(context.typeName);
    auto partials = context.getMatchingPartials(context.typeName);
    auto app = appender!(Node[]);
    mixinRest.children[1].toIr(app, context);
    partials.each!(c => toIr(c.children[0], app, context));
    a.put(new StructIncludesNode(tree.children[0].matches[0], tree.children[1].matches[0], app.data));
    break;
  case "WebIDL.Iterable":
    // a.putLn("// TODO: add iterable");
    break;
  case "WebIDL.MixinRest":
    break;
  case "WebIDL.Const":
    a.put(new ConstNode(tree.children[0].generateDType(context),
                        tree.children[1].generateDType(context),
                        tree.children[2].generateDType(context)));
    break;
  case "WebIDL.InterfaceMember":
    context.extendedAttributeList = tree.children[0];
    tree.children[1].toIr(a, context);
    break;
  case "WebIDL.ReadOnlyMember":
    context.readonly = true;
    tree.children[0].toIr(a, context);
    break;
  case "WebIDL.MixinMember":
    if (tree.children[0].matches[0] == "readonly") {
      context.readonly = true;
      tree.children[1].toIr(a, context);
    } else
      tree.children[0].toIr(a, context);
    break;
  case "WebIDL.AttributeRest":
    if (context.isIncludes) {
      auto name = tree.children[1].matches[0];
      auto baseName = context.includes.children[0].matches[0];
      auto attrType = tree.children[0];
      auto attrArg = Argument(name, attrType);

      if (!context.readonly)
        a.put(new FunctionNode( name, [attrArg], ParseTree.init, FunctionType.Attribute | FunctionType.Includes, "Set", baseName, ""));
      a.put(new FunctionNode( name, [], attrType, FunctionType.Attribute | FunctionType.Includes, "Get", baseName, ""));
      break;
    }
    if (context.isPartial) {
      auto name = tree.children[1].matches[0];
      auto baseName = context.partial.children[0].children[0].matches[0];
      auto attrType = tree.children[0];
      auto attrArg = Argument(name, attrType);

      if (!context.readonly)
        a.put(new FunctionNode( name, [attrArg], ParseTree.init, FunctionType.Attribute | FunctionType.Partial, "Set", baseName, ""));
      a.put(new FunctionNode( name, [], attrType, FunctionType.Attribute | FunctionType.Partial, "Get", baseName, ""));
      break;
    }
    auto name = tree.children[1].matches[0];
    auto attrType = tree.children[0];
    if (!context.readonly)
      a.put(new FunctionNode( name, [Argument(name, attrType)], ParseTree.init, FunctionType.Attribute, "Set", "", ""));
    a.put(new FunctionNode( name, [], attrType, FunctionType.Attribute, "Get", "", ""));
    break;
  case "WebIDL.ExtendedAttributeList":
    break;
  case "WebIDL.SpecialOperation":
    if (tree.children[1].children[1].children[0].matches[0] != "") {
      // context.customName = tree.children[0].matches[0];
      tree.children[1].toIr(a, context);
      switch(tree.matches[0]) {
      case "getter":
        // (cast(FunctionNode)a.data[$-1]).type |= FunctionType.Getter;
        (cast(FunctionNode)a.data[$-1]).manglePostfix = tree.children[0].matches[0];
        break;
      case "setter":
        // (cast(FunctionNode)a.data[$-1]).type |= FunctionType.Getter;
        (cast(FunctionNode)a.data[$-1]).manglePostfix = tree.children[0].matches[0];
        break;
      default: break;
      }
      break;
    }
    auto rest = tree.children[1].children[1];
    auto args = zip(rest.children[1].extractArguments,rest.children[1].extractTypes).map!(a=>Argument(a[0],a[1])).array();
    auto result = tree.children[1].children[0];
    switch(tree.matches[0]) {
    case "getter":
      assert(args.length == 1);
      a.put(new FunctionNode( "getter", args, result, FunctionType.OpIndex | FunctionType.Getter, "", "", ""));
      args = args.dup();
      args[0].templated = true;
      a.put(new FunctionNode( "getter", args, result, FunctionType.OpDispatch | FunctionType.Getter, "", "" ,""));
      break;
    case "setter":
      assert(args.length == 2);
      a.put(new FunctionNode( "setter", args, ParseTree.init, FunctionType.OpIndexAssign | FunctionType.Setter, "", "", ""));
      args = args.dup();
      args[0].templated = true;
      a.put(new FunctionNode( "setter", args, ParseTree.init, FunctionType.OpDispatch | FunctionType.Setter, "", "", ""));
      break;
    case "deleter":
      a.put(new FunctionNode( "remove", args, ParseTree.init, FunctionType.Function | FunctionType.Deleter, "", "", "deleter"));
      break;
    default: assert(0);
    }
    break;
  case "WebIDL.RegularOperation":
    auto rest = tree.children[1];
    auto args = zip(rest.children[1].extractArguments,rest.children[1].extractTypes,rest.children[1].extractDefaults).map!(a=>Argument(a[0],a[1],a[2])).array();
    auto result = tree.children[0];
    if (context.isIncludes) {
      auto name = tree.children[1].matches[0];
      auto baseName = context.includes.children[0].matches[0];
      a.put(new FunctionNode( name, args, result, FunctionType.Function | FunctionType.Includes, "", baseName, context.customName));
      break;
    }
    if (context.isPartial) {
      auto name = rest.children[0].matches[0];
      auto baseName = context.partial.children[0].children[0].matches[0];
      a.put(new FunctionNode( name, args, result, FunctionType.Function | FunctionType.Partial, "", baseName, context.customName));
      break;
    }
    auto name = rest.children[0].matches[0];
    a.put(new FunctionNode( name, args, result, FunctionType.Function, "", "", context.customName));
    break;
  case "WebIDL.Enum":
    a.put(new EnumNode(tree.children[0].matches[0], tree.children[1].children.map!(c => c.matches[0][1..$-1].orNone.friendlyName).joiner(",\n  ").text));
    break;
  case "WebIDL.Dictionary":
    ParseTree baseType;
    if (tree.children[1].children.length > 0 && tree.children[1].children[0].matches.length != 0)
      baseType = tree.children[1].children[0];
    auto app = appender!(Node[]);
    tree.children[2].toIr(app, context);
    a.put(new StructNode(tree.children[0].matches[0], baseType, app.data));
    break;
  case "WebIDL.DictionaryMember":
    context.extendedAttributeList = tree.children[0];
    tree.children[1].toIr(a, context);
    break;
  case "WebIDL.MaplikeRest":
    auto keyType = tree.children[0].generateDType(context);
    auto valueType = tree.children[1].generateDType(context);
    a.put(new MaplikeNode(keyType, valueType));
    break;
  case "WebIDL.DictionaryMemberRest":
    auto name = tree.children[1].matches[0];
    auto paramType = tree.children[0];
    a.put(new FunctionNode(name, [Argument(name, paramType)], ParseTree.init, FunctionType.Attribute, "Set", "", ""));
    a.put(new FunctionNode(name, [], paramType, FunctionType.Attribute, "Get", "", ""));
    break;
  case "WebIDL.Typedef":
    a.put(new TypedefNode(tree.children[1].matches[0], tree.children[0].generateDType(context), tree.children[0]));
    break;
  case "WebIDL.Partial":
    context.partial = tree;
    if (tree.children[0].children[0].name == "WebIDL.PartialInterfaceOrPartialMixin") {
      context.typeName = tree.children[0].children[0].children[0].children[0].matches[0];
      auto baseType = context.getType(context.typeName);
      if (baseType.name == "WebIDL.MixinRest")
        return;
    } else if (tree.children[0].children[0].name == "WebIDL.PartialDictionary")
      context.typeName = tree.children[0].children[0].children[0].matches[0];
    tree.children[0].toIr(a, context);
    break;
  case "WebIDL.PartialInterfaceRest":
    tree.children[1].toIr(a, context);
    break;
  case "WebIDL.CallbackRest":
    a.put(new CallbackNode(tree.children[0].matches[0], tree.children[1], tree.children[2]));
    break;
  default:
    tree.children.each!(c => toIr(c, a, context));
    return;
  }
}

auto extractNodes(T)(IR ir) {
  auto app = appender!(T[]);
  void recurse(Node node) {
    if (cast(T)node)
      app.put(cast(T)node);
    else if (cast(StructNode)node)
      (cast(StructNode)node).children.each!(node => recurse(node));
    else if (cast(StructIncludesNode)node)
      (cast(StructIncludesNode)node).children.each!(node => recurse(node));
    else if (cast(ModuleNode)node)
      (cast (ModuleNode)node).children.each!(node => recurse(node));
  }
  ir.nodes.each!(node => recurse(node));
  return app.data;
}

void generateEncodedTypes(IR ir, Semantics semantics, ref Appender!(ParseTree[]) a) {
  auto funcs = ir.extractNodes!(FunctionNode);

  foreach(fun; funcs) {
    if (fun.result != ParseTree.init && fun.result.matches[0] != "void") {
      if (semantics.isStringType(fun.result) || semantics.isUnion(fun.result) || semantics.isNullable(fun.result) || semantics.isEnum(fun.result)) {
        a.put(fun.result);
      }
    }
    foreach(arg; fun.args) {
      if (semantics.isCallback(arg.type.matches[0])){
        auto argList = semantics.getArgumentList(arg.type);
        auto types = extractTypes(argList);
        foreach(type; types) {
          if (semantics.isStringType(type) || semantics.isUnion(type)
              || semantics.isNullable(type) || semantics.isEnum(type))
            a.put(type);
        }
      }
    }
  }
}

auto stripNullable(ParseTree tree) {
  if (tree.children.length == 0)
    return tree;
  switch (tree.name) {
  case "WebIDL.ExtendedAttributeList": return tree;
  case "WebIDL.CallbackRest": return tree;
  case "WebIDL.Dictionary": return tree;
  case "WebIDL.CallbackOrInterfaceOrMixin": return tree;
  case "WebIDL.PartialDefinition": return tree;
  default:
  }
  if (tree.children[$-1].name == "WebIDL.Null") {
    tree.children = tree.children.dup;
    tree.children[$-1].matches = [""];
    tree.matches[$-1] = "";
    return tree;
  } else if (tree.matches[$-1] == "?") {
    tree.matches = tree.matches.dup[0..$-1];
  }
  tree.children = tree.children.map!(c => c.stripNullable).array;
  return tree;
}

void generateJsEncoder(Encoder)(Encoder encoder, ref IndentedStringAppender a, ref Semantics semantics, bool isVar) {
  a.put("encode_");
  a.put(encoder.mangled);
  if (isVar) {
    a.put(" = ");
  } else {
    a.put(": ");
  }
  a.putLn("(ptr, val)=>{");
  a.indent();
  // enum
  // optional!T
  // sumType!Ts
  // typedef to T
  if (semantics.isNullableTypedef(encoder.tree)) {
    string typeName = encoder.tree.getTypeName();
    auto aliasedType = semantics.getAliasedType(typeName);
    uint structSize = semantics.getSizeOf(aliasedType);
    a.putLn(["if (!setBool(ptr+", structSize.to!string, ", isEmpty(val))) {"]);
    a.indent();
    auto typedefMangled = aliasedType.mangleTypeJs(semantics);
    a.putLn(["encode_",typedefMangled,"(ptr, val);"]);
    a.undent();
    a.putLn("}");
  } else if (semantics.isTypedef(encoder.tree)) {
    string typeName = encoder.tree.getTypeName();
    auto aliasedType = semantics.getAliasedType(typeName);
    auto typedefMangled = aliasedType.mangleTypeJs(semantics);
    a.putLn(["encode_",typedefMangled,"(ptr, val);"]);
  } else if (semantics.isNullable(encoder.tree)) {
    auto baseType = encoder.tree.stripNullable;
    uint structSize = semantics.getSizeOf(baseType);
    a.putLn(["if (!setBool(ptr+", structSize.to!string, ", isEmpty(val))) {"]);
    a.indent();
    auto typedefMangled = baseType.mangleTypeJs(semantics);
    a.putLn(["encode_",typedefMangled,"(ptr, val);"]);
    a.undent();
    a.putLn("}");
  } else if (semantics.isEnum(encoder.tree)) {
    string typeName = encoder.tree.getTypeName();
    auto aliasedType = (typeName in semantics.types).tree;
    a.putLn(["const vals = [",aliasedType.children[1].children.map!(c => c.matches[0]).joiner(", ").text,"];"]);
    a.putLn("setInt(ptr, vals.indexOf(val))");
  } else if (semantics.isUnion(encoder.tree)) {
    void outputChild(Child)(Child c, ref Semantics semantics) {
        a.putLn(["if (val instanceof ",c.value.getTypeName,") {"]);
        a.indent();
        a.putLn(["setInt(ptr, ",c.index.to!string ,");"]);
        a.putLn(["encode_", c.value.mangleTypeJs(semantics),"(ptr+4, val);"]);
        a.undent();
        a.put("}");
    }
    auto children = semantics.getUnionChildren(encoder.tree).enumerate;
    if (children.length > 0) {
      children[0..$-1].each!((c){
        outputChild(c, semantics);
        a.put(" else ");
      });
      outputChild(semantics.getUnionChildren(encoder.tree).enumerate[$-1], semantics);
    }
    a.putLn("");
  } else {
    a.putLn("// other");
  }
  // where T can be any of the above
  // and Ts two or more of the set including the above and the following:
  // - any primitive (double, bool, int; unsigned/signed; etc.)
  // - a JsHandle
  a.undent();
  a.putLn("},");
}


void iterate(alias fun, Appender, Args...)(ref Module module_, ref Appender app, Args args) {
  foreach (key; module_.types.keys.array.sort) {
    auto type = module_.types[key];
    static if (Args.length > 0)
      args[0].extendedAttributeList = type.attributes;
    fun(type.tree, app, args);
  }
  foreach (namespace; module_.namespaces.dup.schwartzSort!(i => i.tree.name)) { 
    fun(namespace.tree, app, args);
  }
  foreach (partialType; module_.partials.dup.schwartzSort!(i => i.tree.name)) {
    static if (Args.length > 0)
      args[0].extendedAttributeList = partialType.attributes;
    fun(partialType.tree, app, args);
  }
  foreach (mixinType; module_.mixins.dup.schwartzSort!(i => i.tree.name)) {
    fun(mixinType.tree, app, args);
  }
}

ParseTree[] getUnionChildren(ref Semantics semantics, ParseTree tree) {
  if (tree.name == "WebIDL.ReturnType")
    return semantics.getUnionChildren(tree.children[0].children[0]);
  if (tree.name == "WebIDL.TypeWithExtendedAttributes")
    return semantics.getUnionChildren(tree.children[1].children[0]);
  if (tree.name == "WebIDL.Type") {
    assert(tree.children[0].name == "WebIDL.UnionType");
    return semantics.getUnionChildren(tree.children[0]);
  }
  assert(tree.name == "WebIDL.UnionType");
  return tree.children;
}
struct TypeEncoder {
  string mangled;
  ParseTree tree;
  bool external;
}
TypeEncoder[] generateEncodedTypes(IR ir, Semantics semantics) {
  auto app = appender!(ParseTree[]);
  ir.generateEncodedTypes(semantics, app);
  auto encodedTypes = app.data.map!(t => TypeEncoder(t.mangleTypeJs(semantics),t,true)).array.sort!((a,b){return a.mangled < b.mangled;}).uniq!((a, b){return a.mangled == b.mangled;});

  auto encoders = appender!(TypeEncoder[]);
  encodedTypes.copy(encoders);

  ulong start = 0, end = encoders.data.length;
  while (start != end) {
    foreach(encoder; encoders.data[start..end].dup) {
      if (semantics.isNullableTypedef(encoder.tree)) {
        string typeName = encoder.tree.getTypeName();
        auto aliasedType = semantics.getAliasedType(typeName);
        auto typedefMangled = aliasedType.mangleTypeJs(semantics);
        encoders.put(TypeEncoder(typedefMangled, aliasedType, false));
      } else if (semantics.isTypedef(encoder.tree)) {
        string typeName = encoder.tree.getTypeName();
        auto aliasedType = semantics.getAliasedType(typeName);
        auto typedefMangled = aliasedType.mangleTypeJs(semantics);
        encoders.put(TypeEncoder(typedefMangled, aliasedType, false));
      } else if (semantics.isNullable(encoder.tree)) {
        auto baseType = encoder.tree.stripNullable;
        auto typedefMangled = baseType.mangleTypeJs(semantics);
        encoders.put(TypeEncoder(typedefMangled, baseType, false));
      } else if (semantics.isUnion(encoder.tree)) {
        foreach (child; semantics.getUnionChildren(encoder.tree)) {
          auto typedefMangled = child.mangleTypeJs(semantics);
          encoders.put(TypeEncoder(typedefMangled, child, false));
        }
      }
    }
    start = end;
    end = encoders.data.length;
  }
  return encoders.data;
}

class IR {
  ModuleNode[] nodes;
  StructNode[string] structs;
  Semantics semantics;
  this(ModuleNode[] nodes, Semantics semantics) {
    this.nodes = nodes;
    this.semantics = semantics;
    nodes.each!(mod => mod.children.map!(n => cast(StructNode)n).filter!(n => n !is null).each!((n){
          structs[n.name] = n;
        }));
    this.resolvePartialsAndIncludes();
    this.postfixOverloads(semantics);
  }
}

auto getImports(IR ir, Module module_) {
  import std.format : format;
  import std.typecons : tuple, Tuple;
  alias Item = Tuple!(Type,"type",string,"name");
  auto app = appender!(Item[]);
  auto semantics = ir.semantics;
  void extractTypes(Semantics semantics, ParseTree tree, Appender!(Item[]) app) {
    if (tree.name == "WebIDL.NonAnyType" && tree.children[0].name == "WebIDL.Identifier") {
      if (auto p = tree.matches[0] in semantics.types)
        app.put(tuple!("type","name")(*p, tree.matches[0]));
    } else {
      tree.children.each!(c => extractTypes(semantics, c, app));
    }
  }
  void recurse(Node node) {
    if (cast(FunctionNode)node) {
      extractTypes(semantics, (cast(FunctionNode)node).result, app);
      (cast(FunctionNode)node).args.each!(arg => extractTypes(semantics, arg.type, app));
    } else if (cast(TypedefNode)node) {
      extractTypes(semantics, (cast(TypedefNode)node).rhs, app);
    } else if (cast(CallbackNode)node) {
      extractTypes(semantics, (cast(CallbackNode)node).result, app);
      extractTypes(semantics, (cast(CallbackNode)node).args, app);
    } else if (cast(StructNode)node)
      (cast(StructNode)node).children.each!(node => recurse(node));
    else if (cast(StructIncludesNode)node)
      (cast(StructIncludesNode)node).children.each!(node => recurse(node));
    else if (cast(ModuleNode)node)
      (cast (ModuleNode)node).children.each!(node => recurse(node));
  }
  ir.nodes.filter!(n => n.module_ is module_).each!((node){
      node.children.each!(c => recurse(c));
    });
  return app.data.schwartzSort!(a => a.name).uniq!((a,b){return a.name == b.name;}).filter!(t => t.type.module_ !is module_).map!(t => format("import spasm.bindings.%s : %s;", t.type.module_.name,t.name)).array;
}
auto resolvePartialsAndIncludes(IR ir) {
  ir.nodes.each!(mod => mod.children.map!(n => cast(FunctionNode)n).filter!(n => n !is null && n.baseType.length > 0).each!((n){
        if (auto p = n.baseType in ir.structs)
          p.children ~= n;
        else
          writeln("Error: Type ", n.baseType, " is unknown: ");
      }));
  ir.nodes.each!(mod => mod.children.map!(n => cast(StructIncludesNode)n).filter!(n => n !is null).each!((n){
        if (auto p = n.baseType in ir.structs) {
          p.children ~= n;
        }
        else
          writeln("Error: Type ", n.baseType, " is unknown");
      }));
}
auto postfixOverloads(IR ir, Semantics semantics) {
  import std.algorithm : schwartzSort;
  foreach(item; ir.structs.byValue) {
    auto funcs = item.children.map!(n => cast(FunctionNode)n).filter!(n => n !is null).array;
    auto overloadGroups = funcs.schwartzSort!((a){
        if (a.customName.length > 0)
          return a.customName ~ a.manglePostfix;
        return a.name ~ a.manglePostfix;
      }).groupBy.map!(g => g.array).filter!(g => g.length > 1);
    foreach(group; overloadGroups) {
      foreach(fun; group) {
        fun.manglePostfix ~= "_" ~ fun.args.map!(arg => arg.type.mangleTypeJs(semantics)).joiner("_").text;
      }
    }
  }
}
string generateDBindings(IR ir, Module module_) {
  auto app = IndentedStringAppender();
  auto context = Context(module_.semantics);
  app.put(""); // TODO: for some reason this is necessary.
  ir.nodes.filter!(mod => mod.module_ is module_).each!(n => n.toDBinding(module_.semantics, &app));
  return app.data;
}

string generateDImports(IR ir, Module module_) {
  auto app = IndentedStringAppender();
  ir.nodes.filter!(mod => mod.module_ is module_).each!(n => n.toDImport(module_.semantics, &app));
  if (app.data.length > 0)
    return app.data[0 .. $ - 1]; // remove last newline
  return app.data;
}

string generateJsExports(IR ir, Module module_) {
  auto app = IndentedStringAppender();
  app.putLn("import spasm from './spasm.js';");
  app.putLn("export default {");
  app.indent();
  app.putLn("jsExports: {");
  app.indent();

  ir.nodes.filter!(mod => mod.module_ is module_).each!(n => n.toJsExport(module_.semantics, &app));

  app.undent();
  app.putLn("}");
  app.undent();
  app.put("}");
  return app.data;
}

string generateJsEncoders(IR ir, Semantics semantics) {
  import std.algorithm : map, filter, joiner, each, sort, uniq, cmp;
  import std.array : array;
  import std.conv : text;
  import std.typecons : tuple;
  auto encodedTypes = ir.generateEncodedTypes(semantics).sort!((a,b){return a.mangled < b.mangled;}).uniq!((a, b){return a.mangled == b.mangled;});
  auto app = IndentedStringAppender();
  app.putLn("import spasm from './spasm.js';");
  app.putLn("const setBool = (ptr, val) => (spasm.heapi32u[ptr/4] = +val),");
  app.putLn("      setInt = (ptr, val) => (spasm.heapi32s[ptr/4] = val),");
  app.putLn("      setUInt = (ptr, val) => (spasm.heapi32u[ptr/4] = val),");
  app.putLn("      setShort = (ptr, val) => (spasm.heapi16s[ptr/2] = val),");
  app.putLn("      setUShort = (ptr, val) => (spasm.heapi16u[ptr/2] = val),");
  app.putLn("      setByte = (ptr, val) => (spasm.heapi8s[ptr] = val),");
  app.putLn("      setUByte = (ptr, val) => (spasm.heapi8u[ptr] = val),");
  app.putLn("      setFloat = (ptr, val) => (spasm.heapf32[ptr/4] = val),");
  app.putLn("      setDouble = (ptr, val) => (spasm.heapf64[ptr/8] = val),");
  app.putLn("      isEmpty = (val) => (val == undefined || val == null);");
  app.put("const ");
  app.indent();
  foreach(encoder; encodedTypes.filter!(e => e.external == false)) {
    encoder.generateJsEncoder(app, semantics, true);
  }
  app.putLn(";");
  app.undent();
  app.putLn("export default {");
  app.indent();
  foreach(encoder; encodedTypes.filter!(e => e.external)) {
    encoder.generateJsEncoder(app, semantics, false);
  }
  app.undent();
  app.put("}");
  return app.data;
}
class Type {
  ParseTree tree;
  ParseTree attributes;
  Module module_;
  this(ParseTree t, ParseTree a, Module m) {
    tree = t;
    attributes = a;
    module_ = m;
  }
}

class Module {
  string name;
  Type[string] types;
  Type[] partials;
  Type[] mixins;
  Type[] namespaces;
  Semantics semantics;
  this(string n, Semantics semantics) {
    this.name = n;
    this.semantics = semantics;
  }
}

class Semantics {
  Type[string] types;
  Type[] partials;
  Type[] mixins;
  Type[] namespaces;
  Module[string] modules;
  void analyse(string module_, ParseTree tree) {
    import std.range : chunks;
    assert(tree.name == "WebIDL");
    auto m = new Module(module_, this);
    foreach(chunk; tree.children[0].children.chunks(2)) {
      assert(chunk.length == 2);
      analyse(m, chunk[1], chunk[0]);
    }
    modules[module_] = m;
    foreach (n; m.namespaces)
      namespaces ~= n;
    foreach(p; m.partials)
      partials ~= p;
    foreach(mix; m.mixins)
      mixins ~= mix;
    foreach(k,v; m.types)
      types[k] = v;
  }
  void dumpTypes() {
    import std.format;
    writefln("%(%s\n%)",types.keys.map!((key){return format("%s.%s", types[key].module_.name, key);}).array.sort);
  }
  private void analyse(Module module_, ParseTree tree, ParseTree attributes) {
    switch (tree.name) {
    case "WebIDL.IncludesStatement":
      module_.mixins ~= new Type(tree, ParseTree.init, module_);
      break;
    case "WebIDL.Dictionary":
    case "WebIDL.InterfaceRest":
    case "WebIDL.Enum":
    case "WebIDL.CallbackRest":
    case "WebIDL.MixinRest":
      string name = tree.children[0].matches[0];
    if (auto p = name in types) {
      writefln("Warning: duplicated entry for %s", name);
      writefln("A in %s: %s",(*p).module_.name,(*p).tree.input[(*p).tree.begin .. (*p).tree.end]);
      writefln("B in %s: %s",module_.name,tree.input[tree.begin .. tree.end]);
    }
    module_.types[name] = new Type(tree, attributes, module_);
    break;
    case "WebIDL.Partial":
      module_.partials ~= new Type(tree, attributes, module_);
      break;
    case "WebIDL.Typedef":
      string name = tree.children[1].matches[0];
      module_.types[name] = new Type(tree, attributes, module_);
      break;
    case "WebIDL.Namespace":
      module_.namespaces ~= new Type(tree, attributes, module_);
      break;
    default:
      tree.children.each!(c => analyse(module_, c, attributes));
    }
  }
}
string generateDType(ParseTree tree, Context context) {
  auto app = IndentedStringAppender();
  tree.generateDType(app, context);
  return app.data;
}
void generateDType(Appender)(ParseTree tree, ref Appender a, Context context) {
  switch (tree.name) {
  case "WebIDL.InterfaceRest":
  case "WebIDL.IncludesStatement":
  case "WebIDL.Iterable":
  case "WebIDL.MixinRest":
  case "WebIDL.Const":
  case "WebIDL.InterfaceMember":
  case "WebIDL.ReadOnlyMember":
  case "WebIDL.MixinMember":
  case "WebIDL.AttributeRest":
  case "WebIDL.ExtendedAttributeList":
  case "WebIDL.SpecialOperation":
  case "WebIDL.RegularOperation":
  case "WebIDL.ArgumentList":
  case "WebIDL.ArgumentName":
  case "WebIDL.ArgumentRest":
  case "WebIDL.Enum":
  case "WebIDL.Dictionary":
  case "WebIDL.DictionaryMember":
  case "WebIDL.SetlikeRest":
  case "WebIDL.MaplikeRest":
  case "WebIDL.DictionaryMemberRest":
  case "WebIDL.Typedef":
  case "WebIDL.Partial":
  case "WebIDL.PartialInterfaceRest":
  case "WebIDL.CallbackRest":
    break;
  case "WebIDL.SequenceType":
    if (tree.children[$-1].matches[0] == "?")
      a.put("Optional!(");
    a.put("Sequence!(");
    tree.children[0].generateDType(a, context);
    a.put(")");
    if (tree.children[$-1].matches[0] == "?")
      a.put(")");
    break;
  case "WebIDL.TypeWithExtendedAttributes":
    context.extendedAttributeList = tree.children[0];
    tree.children[1].generateDType(a, context);
    break;
  case "WebIDL.StringType":
    switch (tree.matches[0]) {
    case "ByteString":
      a.put(tree.matches[0]);
    break;
    default:
      a.put("string");
    break;
    }
    break;
  case "WebIDL.SingleType":
    if (tree.matches[0] == "any")
      a.put("Any");
    else
      tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.NonAnyType":
    bool optional = !context.skipOptional && (context.optional || tree.children[$-1].name == "WebIDL.Null" && tree.children[$-1].matches[0] == "?");
    if (optional) {
      a.put("Optional!(");
    }
    switch (tree.matches[0]) {
    case "object":
      a.put("Object");
      break;
    case "symbol":
      a.put("Symbol");
      break;
    case "Error":
      a.put("Error");
      break;
    case "FrozenArray":
      a.put("FrozenArray!(");
      tree.children[$-2].generateDType(a, context);
      a.put(")");
      break;
    default:
      tree.children.each!(c => c.generateDType(a, context));
    }
    if (optional) {
      a.put(")");
    }
    break;
  case "WebIDL.PrimitiveType":
    if (tree.children.length == 0) {
      switch (tree.matches[0]) {
      case "byte": a.put("byte"); break;
      case "octet": a.put("ubyte"); break;
      case "boolean": a.put("bool"); break;
      default: a.put(tree.matches[0]); break;
      }
    } else
      tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.UnrestrictedFloatType":
    // TODO: handle unrestricted
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.UnsignedIntegerType":
    if (tree.matches[0] == "unsigned")
      a.put("u");
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.IntegerType":
    if (tree.matches[0] == "long") {
      if (tree.matches.length > 1)
        a.put("long");
      else
        a.put("int");
    } else
      a.put(tree.matches[0]);
    break;
  case "WebIDL.FloatType":
  case "WebIDL.Identifier":
    string typeName = tree.matches[0];
    if (context.isTypedef(typeName)) {
      auto aliasedType = context.getAliasedType(typeName);
      IndentedStringAppender app;
      aliasedType.generateDType(app, context);
      if (app.data.length < tree.matches[0].length)
        return a.put(app.data);
    }

    a.put(tree.matches[0]);
    break;
  case "WebIDL.ReturnType":
    if (tree.children.length > 0)
      tree.children[0].generateDType(a, context);
    else
      a.put(tree.matches[0]);
    break;
  case "WebIDL.Default":
    if (tree.children.length == 0)
      return;
    a.put("/* = ");
    tree.children[0].generateDType(a, context);
    a.put(" */");
    break;
  case "WebIDL.DefaultValue":
    if (tree.children.length == 0) {
      a.put("[]");
      return;
    }
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.ConstValue":
    if (tree.children.length == 0) {
      a.put(tree.matches);
      break;
    }
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.BooleanLiteral":
  case "WebIDL.Integer":
    a.put(tree.matches);
    break;
  case "WebIDL.Float":
    a.put(tree.matches[0]);
    break;
  case "WebIDL.FloatLiteral":
    if (tree.children.length == 0) {
      switch (tree.matches[0]) {
      case "-Infinity": a.put("-float.infinity"); break;
      case "Infinity": a.put("float.infinity"); break;
      case "NaN": a.put("float.nan"); break;
      default: assert(false);
      }
      break;
    }
    tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.String":
    a.put(tree.matches);
    break;
  case "WebIDL.RecordType":
    a.put("Record!(");
    tree.children.putWithDelimiter!(generateDType)(", ", a, context);
    a.put(")");
    break;
  case "WebIDL.PromiseType":
    a.put("Promise!(");
    tree.children[0].generateDType(a, context);
    a.put(")");
    break;
  case "WebIDL.Type":
    context.optional = false;
    if (tree.children[0].name == "WebIDL.UnionType") {
      bool optional = !context.skipOptional && tree.children[1].matches[0] == "?";
      context.optional = optional;
      if (optional) {
        a.put("Optional!(");
      }
      a.put("SumType!(");
      tree.children[0].children.putWithDelimiter!(generateDType)(", ", a, context);
      if (optional)
        a.put(")");
      a.put(")");
      break;
    } else
      tree.children[0].generateDType(a, context);
    break;
  case "WebIDL.UnionMemberType":
    context.optional = false;
    if (tree.children[0].name == "WebIDL.UnionType") {
      bool optional = !context.skipOptional && tree.matches[$-1] == "?";
      context.optional = optional;
      if (optional) {
        a.put("Optional!(");
      }
      a.put("SumType!(");
      tree.children[0].children.putWithDelimiter!(generateDType)(", ", a, context);
      if (optional)
        a.put(")");
      a.put(")");
      break;
    } else
      tree.children.each!(c => c.generateDType(a, context));
    break;
  default:
    tree.children.each!(c => generateDType(c, a, context));
  }
}
