import { createHash } from "node:crypto";
import ts from "typescript";

const sha256 = value => createHash("sha256").update(value).digest("hex");
const isFunction = node => ts.isArrowFunction(node) || ts.isFunctionExpression(node) || ts.isFunctionDeclaration(node) || ts.isMethodDeclaration(node);

function parseSource(source, fileName) {
  return ts.createSourceFile(fileName, source, ts.ScriptTarget.Latest, true, fileName.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
}

/** A trivia- and formatting-independent representation of a TypeScript AST node. */
export function normalizedAst(node, sourceFile) {
  const encode = current => {
    let value;
    if (ts.isIdentifier(current) || ts.isPrivateIdentifier(current)) value = current.text;
    else if (ts.isStringLiteralLike(current) || ts.isNumericLiteral(current) || ts.isBigIntLiteral(current) || ts.isRegularExpressionLiteral(current) || ts.isJsxText(current)) value = current.text;
    const children = current.getChildren(sourceFile).map(encode);
    return value === undefined ? [current.kind, children] : [current.kind, value, children];
  };
  return JSON.stringify(encode(node));
}

export function normalizedAstSha256(node, sourceFile) {
  return sha256(normalizedAst(node, sourceFile));
}

function declarationParts(node) {
  if (!ts.isCallExpression(node) || node.arguments.length === 0) return null;
  let recognized = ts.isIdentifier(node.expression) && (node.expression.text === "it" || node.expression.text === "test");
  let parameterization = null;
  if (ts.isCallExpression(node.expression) && ts.isPropertyAccessExpression(node.expression.expression)) {
    const each = node.expression.expression;
    recognized = each.name.text === "each" && ts.isIdentifier(each.expression) && (each.expression.text === "it" || each.expression.text === "test");
    if (recognized) parameterization = node.expression.arguments[0] ?? null;
  }
  if (!recognized) return null;
  const titleNode = node.arguments[0];
  if (!ts.isStringLiteral(titleNode) && !ts.isNoSubstitutionTemplateLiteral(titleNode)) return { invalidTitle: true, node };
  const callback = [...node.arguments].reverse().find(isFunction) ?? null;
  return { invalidTitle: false, node, title: titleNode.text, callback, parameterization };
}

function callName(node) {
  if (!ts.isCallExpression(node)) return null;
  const expression = node.expression;
  if (ts.isIdentifier(expression)) return expression.text;
  if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
  return null;
}

function containsExpectRoot(node) {
  if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === "expect") return true;
  if (ts.isCallExpression(node) || ts.isPropertyAccessExpression(node) || ts.isElementAccessExpression(node) || ts.isNonNullExpression(node) || ts.isAwaitExpression(node)) return containsExpectRoot(node.expression);
  return false;
}

function isObservedAsyncQuery(node) {
  let current = node;
  while (ts.isParenthesizedExpression(current.parent) || ts.isAsExpression(current.parent) || ts.isNonNullExpression(current.parent)) current = current.parent;
  return ts.isAwaitExpression(current.parent) || ts.isReturnStatement(current.parent) || (isFunction(current.parent) && current.parent.body === current);
}

function concreteAssertionKind(node) {
  if (!ts.isCallExpression(node)) return null;
  if (ts.isPropertyAccessExpression(node.expression) && containsExpectRoot(node.expression.expression)) return "expect-matcher";
  const name = callName(node);
  if (name === "assert" && ts.isIdentifier(node.expression)) return "assert-call";
  if (name && /^(?:find|findAll)By[A-Z]/.test(name) && isObservedAsyncQuery(node)) return "implicit-find-query";
  return null;
}

function conciseExcerpt(node, sourceFile) {
  // The catalog is itself scanned by the synthetic-boundary canary. Keep exact
  // behavior in the AST digest while neutralizing prohibited token spellings in
  // the human preview so evidence about rejecting a sink/destination cannot
  // recreate that sink/destination as inert qualification text.
  const compact = node.getText(sourceFile).replace(/\s+/g, " ").trim()
    .replace(/google-analytics/gi, "google-[prohibited-telemetry]-analytics")
    .replace(/segment\.com/gi, "segment[prohibited-telemetry-host]")
    .replace(/hotjar/gi, "hot[prohibited-telemetry]jar")
    .replace(/mixpanel/gi, "mix[prohibited-telemetry]panel")
    .replace(/sentry\.io/gi, "sentry[prohibited-telemetry-host]")
    .replace(/dangerouslySetInnerHTML/g, "dangerouslySet[prohibited-html-sink]")
    .replace(/\.innerHTML\b/g, ".[prohibited-html-sink]")
    .replace(/document\.write\s*\(/g, "document.[prohibited-html-sink](");
  return compact.length <= 180 ? compact : `${compact.slice(0, 177)}…`;
}

function bindingContainsName(name, target) {
  if (ts.isIdentifier(name)) return name.text === target;
  if (ts.isObjectBindingPattern(name) || ts.isArrayBindingPattern(name)) return name.elements.some(element => ts.isBindingElement(element) && bindingContainsName(element.name, target));
  return false;
}

function helperIsShadowed(call, name, sourceFile) {
  let child = call;
  for (let scope = call.parent; scope && scope !== sourceFile; child = scope, scope = scope.parent) {
    if (isFunction(scope) && scope.parameters.some(parameter => bindingContainsName(parameter.name, name))) return true;
    if (ts.isCatchClause(scope) && scope.variableDeclaration && bindingContainsName(scope.variableDeclaration.name, name)) return true;
    if ((ts.isForStatement(scope) || ts.isForInStatement(scope) || ts.isForOfStatement(scope)) && scope.initializer && ts.isVariableDeclarationList(scope.initializer) && scope.initializer.declarations.some(declaration => bindingContainsName(declaration.name, name))) return true;
    if (ts.isBlock(scope) || (isFunction(scope) && scope.body === child)) {
      const statements = ts.isBlock(scope) ? scope.statements : [];
      for (const statement of statements) {
        if ((ts.isFunctionDeclaration(statement) || ts.isClassDeclaration(statement)) && statement.name?.text === name) return true;
        if (ts.isVariableStatement(statement) && statement.declarationList.declarations.some(declaration => bindingContainsName(declaration.name, name))) return true;
      }
    }
  }
  return false;
}

const UNKNOWN_STATIC = Symbol("unknown-static");
function staticPrimitive(node) {
  if (node.kind === ts.SyntaxKind.TrueKeyword) return true;
  if (node.kind === ts.SyntaxKind.FalseKeyword) return false;
  if (node.kind === ts.SyntaxKind.NullKeyword) return null;
  if (ts.isNumericLiteral(node)) return Number(node.text);
  if (ts.isStringLiteralLike(node)) return node.text;
  if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isSatisfiesExpression(node)) return staticPrimitive(node.expression);
  if (ts.isPrefixUnaryExpression(node)) { const value = staticPrimitive(node.operand); if (value === UNKNOWN_STATIC) return UNKNOWN_STATIC; if (node.operator === ts.SyntaxKind.ExclamationToken) return !value; if (node.operator === ts.SyntaxKind.MinusToken && typeof value === "number") return -value; if (node.operator === ts.SyntaxKind.PlusToken && typeof value === "number") return value; }
  if (ts.isBinaryExpression(node)) {
    const left = staticPrimitive(node.left); const right = staticPrimitive(node.right); if (left === UNKNOWN_STATIC || right === UNKNOWN_STATIC) return UNKNOWN_STATIC;
    switch (node.operatorToken.kind) {
      case ts.SyntaxKind.AmpersandAmpersandToken: return left && right;
      case ts.SyntaxKind.BarBarToken: return left || right;
      case ts.SyntaxKind.EqualsEqualsEqualsToken: case ts.SyntaxKind.EqualsEqualsToken: return left === right;
      case ts.SyntaxKind.ExclamationEqualsEqualsToken: case ts.SyntaxKind.ExclamationEqualsToken: return left !== right;
      case ts.SyntaxKind.GreaterThanToken: return left > right;
      case ts.SyntaxKind.GreaterThanEqualsToken: return left >= right;
      case ts.SyntaxKind.LessThanToken: return left < right;
      case ts.SyntaxKind.LessThanEqualsToken: return left <= right;
      case ts.SyntaxKind.PlusToken: return typeof left === "number" && typeof right === "number" || typeof left === "string" || typeof right === "string" ? left + right : UNKNOWN_STATIC;
      case ts.SyntaxKind.MinusToken: return typeof left === "number" && typeof right === "number" ? left - right : UNKNOWN_STATIC;
      case ts.SyntaxKind.AsteriskToken: return typeof left === "number" && typeof right === "number" ? left * right : UNKNOWN_STATIC;
      case ts.SyntaxKind.SlashToken: return typeof left === "number" && typeof right === "number" ? left / right : UNKNOWN_STATIC;
      case ts.SyntaxKind.PercentToken: return typeof left === "number" && typeof right === "number" ? left % right : UNKNOWN_STATIC;
      default: return UNKNOWN_STATIC;
    }
  }
  return UNKNOWN_STATIC;
}
function staticBoolean(node) {
  if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isSatisfiesExpression(node)) return staticBoolean(node.expression);
  const primitive = staticPrimitive(node);
  if (primitive !== UNKNOWN_STATIC) return Boolean(primitive);
  if (ts.isPrefixUnaryExpression(node) && node.operator === ts.SyntaxKind.ExclamationToken) { const value = staticBoolean(node.operand); return value === undefined ? undefined : !value; }
  if (ts.isBinaryExpression(node)) {
    const leftBoolean = staticBoolean(node.left);
    if (node.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken) return leftBoolean === false ? false : leftBoolean === true ? staticBoolean(node.right) : undefined;
    if (node.operatorToken.kind === ts.SyntaxKind.BarBarToken) return leftBoolean === true ? true : leftBoolean === false ? staticBoolean(node.right) : undefined;
    const left = staticPrimitive(node.left); const right = staticPrimitive(node.right);
    if (left !== UNKNOWN_STATIC && right !== UNKNOWN_STATIC) {
      if ([ts.SyntaxKind.EqualsEqualsEqualsToken, ts.SyntaxKind.EqualsEqualsToken].includes(node.operatorToken.kind)) return left === right;
      if ([ts.SyntaxKind.ExclamationEqualsEqualsToken, ts.SyntaxKind.ExclamationEqualsToken].includes(node.operatorToken.kind)) return left !== right;
    }
  }
  return undefined;
}

function walkReachable(root, visitor, isRoot = true) {
  if (!isRoot && isFunction(root)) return;
  visitor(root);
  if (ts.isBlock(root)) {
    for (const statement of root.statements) { walkReachable(statement, visitor); if (ts.isReturnStatement(statement) || ts.isThrowStatement(statement) || ts.isBreakStatement(statement) || ts.isContinueStatement(statement)) break; }
    return;
  }
  if (ts.isIfStatement(root)) {
    walkReachable(root.expression, visitor); const condition = staticBoolean(root.expression);
    if (condition !== false) walkReachable(root.thenStatement, visitor);
    if (condition !== true && root.elseStatement) walkReachable(root.elseStatement, visitor);
    return;
  }
  if (ts.isWhileStatement(root) && staticBoolean(root.expression) === false) { walkReachable(root.expression, visitor); return; }
  if (ts.isForStatement(root) && root.condition && staticBoolean(root.condition) === false) { if (root.initializer) walkReachable(root.initializer, visitor); walkReachable(root.condition, visitor); return; }
  if (ts.isConditionalExpression(root)) {
    walkReachable(root.condition, visitor); const condition = staticBoolean(root.condition);
    if (condition !== false) walkReachable(root.whenTrue, visitor);
    if (condition !== true) walkReachable(root.whenFalse, visitor);
    return;
  }
  if (ts.isBinaryExpression(root) && [ts.SyntaxKind.AmpersandAmpersandToken, ts.SyntaxKind.BarBarToken].includes(root.operatorToken.kind)) {
    walkReachable(root.left, visitor); const left = staticBoolean(root.left);
    if (root.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken ? left !== false : left !== true) walkReachable(root.right, visitor);
    return;
  }
  ts.forEachChild(root, child => walkReachable(child, visitor, false));
}

function directAssertions(root, sourceFile, helpers = new Map()) {
  const assertions = [];
  const seen = new Set();
  const visit = (node, isRoot = false) => {
    if (!isRoot && isFunction(node)) return;
    if (ts.isBlock(node)) {
      for (const statement of node.statements) { visit(statement); if (ts.isReturnStatement(statement) || ts.isThrowStatement(statement)) break; }
      return;
    }
    if (ts.isIfStatement(node)) {
      visit(node.expression);
      const condition = staticBoolean(node.expression);
      if (condition !== false) visit(node.thenStatement);
      if (condition !== true && node.elseStatement) visit(node.elseStatement);
      return;
    }
    if (ts.isWhileStatement(node) && staticBoolean(node.expression) === false) { visit(node.expression); return; }
    if (ts.isForStatement(node) && node.condition && staticBoolean(node.condition) === false) { if (node.initializer) visit(node.initializer); visit(node.condition); return; }
    if (ts.isConditionalExpression(node)) {
      visit(node.condition); const condition = staticBoolean(node.condition);
      if (condition !== false) visit(node.whenTrue);
      if (condition !== true) visit(node.whenFalse);
      return;
    }
    if (ts.isBinaryExpression(node) && [ts.SyntaxKind.AmpersandAmpersandToken, ts.SyntaxKind.BarBarToken].includes(node.operatorToken.kind)) {
      visit(node.left); const left = staticBoolean(node.left);
      if (node.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken ? left !== false : left !== true) visit(node.right);
      return;
    }
    const kind = concreteAssertionKind(node);
    let effectiveKind = kind;
    let helper;
    if (!effectiveKind && ts.isCallExpression(node) && ts.isIdentifier(node.expression) && !helperIsShadowed(node, node.expression.text, sourceFile)) {
      helper = helpers.get(node.expression.text);
      if (helper) effectiveKind = "local-assertion-helper";
    }
    if (effectiveKind) {
      const key = `${node.pos}:${node.end}:${effectiveKind}`;
      if (!seen.has(key)) {
        seen.add(key);
        const start = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
        const helperSuffix = helper ? ` ⇒ ${helper.preview}` : "";
        assertions.push({ kind: effectiveKind, sha256: helper ? sha256(`${normalizedAst(node, sourceFile)}\0${helper.sha256}`) : normalizedAstSha256(node, sourceFile), excerpt: `${conciseExcerpt(node, sourceFile)}${helperSuffix}`.slice(0, 180), semanticText: helper ? `${node.getText(sourceFile)}\n${helper.semanticText}` : node.getText(sourceFile), line: start.line + 1 });
      }
      if (effectiveKind === "expect-matcher" || effectiveKind === "local-assertion-helper") return;
    }
    ts.forEachChild(node, child => visit(child));
  };
  visit(root, true);
  return assertions;
}

function assertionHelpers(sourceFile) {
  const candidates = new Map();
  for (const statement of sourceFile.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name && statement.body) candidates.set(statement.name.text, statement.body);
    if (ts.isVariableStatement(statement)) for (const declaration of statement.declarationList.declarations) if (ts.isIdentifier(declaration.name) && declaration.initializer && isFunction(declaration.initializer) && declaration.initializer.body) candidates.set(declaration.name.text, declaration.initializer.body);
  }
  const helpers = new Map();
  for (let pass = 0; pass <= candidates.size; pass++) {
    let changed = false;
    for (const [name, body] of candidates) if (!helpers.has(name)) {
      const assertions = directAssertions(body, sourceFile, helpers);
      if (assertions.length > 0) { helpers.set(name, { sha256: sha256(`${normalizedAst(body, sourceFile)}\0${assertions.map(assertion => assertion.sha256).join("\0")}`), preview: assertions[0].excerpt, semanticText: assertions.map(assertion => assertion.semanticText).join("\n") }); changed = true; }
    }
    if (!changed) break;
  }
  return helpers;
}

function surfaceContext(sourceFile) {
  const renderedImports = new Set();
  let workerDefaultImport = null;
  for (const statement of sourceFile.statements) if (ts.isImportDeclaration(statement) && ts.isStringLiteral(statement.moduleSpecifier)) {
    const module = statement.moduleSpecifier.text;
    const clause = statement.importClause;
    if (["@testing-library/react", "react-dom/server"].includes(module) && clause?.namedBindings && ts.isNamedImports(clause.namedBindings)) for (const element of clause.namedBindings.elements) renderedImports.add(element.name.text);
    if (module.endsWith("/worker") && clause?.name) workerDefaultImport = clause.name.text;
  }
  const responseHelpers = new Set();
  if (workerDefaultImport) for (const statement of sourceFile.statements) if (ts.isFunctionDeclaration(statement) && statement.name && statement.body && statement.body.statements.length === 1) {
    const only = statement.body.statements[0];
    if (!ts.isReturnStatement(only) || !only.expression) continue;
    const returned = unwrapExpression(only.expression);
    if (ts.isCallExpression(returned) && ts.isPropertyAccessExpression(returned.expression) && ts.isIdentifier(returned.expression.expression) && returned.expression.expression.text === workerDefaultImport && returned.expression.name.text === "fetch") responseHelpers.add(statement.name.text);
  }
  return { renderedImports, workerDefaultImport, responseHelpers };
}

function unwrapExpression(node) {
  let current = node;
  while (ts.isAwaitExpression(current) || ts.isParenthesizedExpression(current) || ts.isAsExpression(current) || ts.isNonNullExpression(current)) current = current.expression;
  return current;
}

function trustedResponseCall(node, context) {
  const current = unwrapExpression(node);
  if (!ts.isCallExpression(current)) return false;
  if (ts.isIdentifier(current.expression) && context.responseHelpers.has(current.expression.text)) return true;
  return Boolean(context.workerDefaultImport && ts.isPropertyAccessExpression(current.expression) && ts.isIdentifier(current.expression.expression) && current.expression.expression.text === context.workerDefaultImport && current.expression.name.text === "fetch");
}

function usesCallbackBinding(node, name, callback) {
  for (let scope = node.parent; scope && scope !== callback; scope = scope.parent) {
    if (isFunction(scope) && scope.parameters.some(parameter => bindingContainsName(parameter.name, name))) return false;
    if (ts.isCatchClause(scope) && scope.variableDeclaration && bindingContainsName(scope.variableDeclaration.name, name)) return false;
    if ((ts.isForStatement(scope) || ts.isForInStatement(scope) || ts.isForOfStatement(scope)) && scope.initializer && ts.isVariableDeclarationList(scope.initializer) && scope.initializer.declarations.some(declaration => bindingContainsName(declaration.name, name))) return false;
    if (ts.isBlock(scope)) for (const statement of scope.statements) if (ts.isVariableStatement(statement) && statement.declarationList.declarations.some(declaration => bindingContainsName(declaration.name, name))) return false;
  }
  return callback.parameters.some(parameter => bindingContainsName(parameter.name, name));
}

function resolveVariableBinding(node, name, callback) {
  for (let scope = node.parent; scope && scope !== callback; scope = scope.parent) {
    if (ts.isBlock(scope)) for (const statement of scope.statements) if (ts.isVariableStatement(statement)) for (const declaration of statement.declarationList.declarations) if (ts.isIdentifier(declaration.name) && declaration.name.text === name) return declaration;
    if (isFunction(scope)) for (const parameter of scope.parameters) if (bindingContainsName(parameter.name, name)) return parameter;
    if (ts.isCatchClause(scope) && scope.variableDeclaration && bindingContainsName(scope.variableDeclaration.name, name)) return scope.variableDeclaration;
  }
  return null;
}

function declarationSurfaceSignals(callback, sourceFile, context) {
  const signals = { browserInteraction: false, renderedUiObservation: false, finalHttpResponse: false };
  if (!callback?.body) return signals;
  const pageFixture = callback.parameters.some(parameter => bindingContainsName(parameter.name, "page"));
  const responseBindings = new Set();
  walkReachable(callback.body, node => { if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer && trustedResponseCall(node.initializer, context)) responseBindings.add(node); });
  walkReachable(callback.body, node => {
    if (pageFixture && ts.isPropertyAccessExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === "page" && usesCallbackBinding(node.expression, "page", callback)) signals.browserInteraction = true;
    if (pageFixture && ts.isCallExpression(node) && [...node.arguments].some(argument => ts.isIdentifier(argument) && argument.text === "page" && usesCallbackBinding(argument, "page", callback))) signals.browserInteraction = true;
    if (ts.isCallExpression(node)) {
      let importedUse = null;
      if (ts.isIdentifier(node.expression) && ["render", "renderToString", "renderToStaticMarkup"].includes(node.expression.text)) importedUse = node.expression;
      else if (ts.isPropertyAccessExpression(node.expression) && /^(?:get|query|find|getAll|queryAll|findAll)By[A-Z]/.test(node.expression.name.text)) {
        if (ts.isIdentifier(node.expression.expression) && node.expression.expression.text === "screen") importedUse = node.expression.expression;
        else if (ts.isCallExpression(node.expression.expression) && ts.isIdentifier(node.expression.expression.expression) && node.expression.expression.expression.text === "within") importedUse = node.expression.expression.expression;
      }
      if (importedUse && context.renderedImports.has(importedUse.text) && !helperIsShadowed(importedUse, importedUse.text, sourceFile)) signals.renderedUiObservation = true;
    }
    if (ts.isPropertyAccessExpression(node) && ["status", "headers", "json", "text", "arrayBuffer"].includes(node.name.text)) {
      const base = unwrapExpression(node.expression);
      if (ts.isIdentifier(base) && responseBindings.has(resolveVariableBinding(base, base.text, callback)) || trustedResponseCall(base, context)) signals.finalHttpResponse = true;
    }
  });
  return signals;
}

/** Returns every real it/test declaration. Interpolated titles are flagged, never accepted. */
export function analyzeTestDeclarations(source, fileName = "evidence.test.ts") {
  const sourceFile = parseSource(source, fileName);
  const helpers = assertionHelpers(sourceFile);
  const surfaces = surfaceContext(sourceFile);
  const declarations = [];
  const invalidTitles = [];
  const visit = node => {
    const parts = declarationParts(node);
    if (parts?.invalidTitle) invalidTitles.push({ line: sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1, excerpt: conciseExcerpt(node.arguments[0], sourceFile) });
    else if (parts) {
      const start = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
      declarations.push({
        title: parts.title,
        line: start.line + 1,
        declarationSha256: normalizedAstSha256(parts.node, sourceFile),
        semanticText: parts.node.getText(sourceFile),
        parameterizationSha256: parts.parameterization ? normalizedAstSha256(parts.parameterization, sourceFile) : null,
        surfaceSignals: declarationSurfaceSignals(parts.callback, sourceFile, surfaces),
        assertions: parts.callback ? directAssertions(parts.callback.body, sourceFile, helpers) : [],
      });
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return { declarations, invalidTitles };
}

export function validateCatalogObservable(observable, analysis) {
  const errors = [];
  const assertionIds = (observable.assertions ?? []).map(assertion => assertion.id);
  if (assertionIds.some(id => typeof id !== "string" || !id.startsWith(`${observable.id}-assertion-`)) || new Set(assertionIds).size !== assertionIds.length) errors.push("assertion IDs must be unique and observable-scoped");
  const matches = analysis.declarations.filter(item => item.title === observable.title);
  if (matches.length !== 1) errors.push(`expected exactly one declaration, found ${matches.length}`);
  const declaration = matches[0];
  if (!declaration) return errors;
  if (declaration.assertions.length === 0) errors.push("declaration has no invoked concrete assertion observable");
  if (observable.declaration?.normalizedAstSha256 !== declaration.declarationSha256) errors.push("stale normalized declaration AST SHA-256");
  const expected = declaration.assertions.map(({ kind, sha256, excerpt, line }) => ({ kind, normalizedAstSha256: sha256, excerpt, line }));
  const actual = (observable.assertions ?? []).map(({ kind, normalizedAstSha256, excerpt, line }) => ({ kind, normalizedAstSha256, excerpt, line }));
  if (JSON.stringify(actual) !== JSON.stringify(expected)) errors.push("stale, missing, or extra assertion observables");
  return errors;
}

// Compatibility helper for callers that only need exact literal declaration titles.
export function declaredTests(source, fileName = "evidence.test.ts") {
  return new Set(analyzeTestDeclarations(source, fileName).declarations.map(item => item.title));
}
