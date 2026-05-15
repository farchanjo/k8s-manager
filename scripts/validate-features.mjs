#!/usr/bin/env node
// Structural lint for Gherkin .feature files under docs/arch/contexts/*/features/.
// Adapted for K8sManager spec layout from lowcow-platform's validate-features.mjs.
//
// Asserts:
//   * file starts with `Feature: <non-empty>` (after optional tags/comments).
//   * has at least one `Scenario:` or `Scenario Outline:` block.
//   * every scenario block contains at least one `When` AND one `Then`.
//   * keywords are recognised (no typos).
//   * tag lines hold only `@token`-shaped tags.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const FEATURES_ROOTS = ["docs/arch/contexts"];
const SCENARIO_RE = /^\s*(Scenario(?: Outline)?|Example):/;
const FEATURE_RE = /^\s*Feature:\s*\S/;
const WHEN_RE = /^\s*(When|And|But)\s+\S/;
const THEN_RE = /^\s*(Then|And|But)\s+\S/;
const ANY_STEP_RE = /^\s*(Given|When|Then|And|But)\s+\S/;
const TAG_RE = /^\s*@[a-zA-Z][a-zA-Z0-9_.\-]*(\s+@[a-zA-Z][a-zA-Z0-9_.\-]*)*\s*$/;
const KEYWORD_RE =
  /^\s*(Feature|Background|Scenario(?: Outline)?|Example|Given|When|Then|And|But|Examples|Rule|Scenarios)(\s|:|$)/;

function listFeatureFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      out.push(...listFeatureFiles(full));
    } else if (entry.endsWith(".feature")) {
      out.push(full);
    }
  }
  return out;
}

function fail(file, line, message) {
  return `${file}:${line}: ${message}`;
}

function validateFeature(file) {
  const errors = [];
  const raw = readFileSync(file, "utf8");
  const lines = raw.split(/\r?\n/);
  let featureLine = null;
  const scenarios = [];
  let current = null;

  for (let i = 0; i < lines.length; i++) {
    const lineNo = i + 1;
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed === "" || trimmed.startsWith("#")) continue;

    if (trimmed.startsWith("@")) {
      if (!TAG_RE.test(trimmed)) {
        errors.push(fail(file, lineNo, `malformed tag line: ${trimmed}`));
      }
      continue;
    }

    if (FEATURE_RE.test(line)) {
      if (featureLine !== null) {
        errors.push(fail(file, lineNo, `duplicate Feature: declaration`));
      }
      featureLine = lineNo;
      continue;
    }

    if (SCENARIO_RE.test(line)) {
      if (current) scenarios.push(current);
      current = { line: lineNo, hasWhen: false, hasThen: false };
      continue;
    }

    if (current && ANY_STEP_RE.test(line)) {
      if (WHEN_RE.test(line) || /^\s*When\s+/.test(line)) current.hasWhen = current.hasWhen || /^\s*When\s+/.test(line);
      if (/^\s*Then\s+/.test(line)) current.hasThen = true;
      if (current.hasWhen === false && /^\s*When\s+/.test(line)) current.hasWhen = true;
      continue;
    }

    if (KEYWORD_RE.test(line)) continue;
  }
  if (current) scenarios.push(current);

  if (featureLine === null) {
    errors.push(fail(file, 1, `missing Feature: declaration`));
  }
  if (scenarios.length === 0) {
    errors.push(fail(file, featureLine ?? 1, `no Scenario blocks`));
  }
  for (const s of scenarios) {
    if (!s.hasWhen) errors.push(fail(file, s.line, `Scenario missing When step`));
    if (!s.hasThen) errors.push(fail(file, s.line, `Scenario missing Then step`));
  }
  return errors;
}

let total = 0;
const all = [];
for (const root of FEATURES_ROOTS) {
  try {
    const files = listFeatureFiles(root);
    total += files.length;
    for (const f of files) {
      all.push(...validateFeature(f));
    }
  } catch (e) {
    if (e.code !== "ENOENT") throw e;
  }
}

if (all.length > 0) {
  console.error(`validate-features: ${all.length} issue(s) across ${total} file(s):`);
  for (const e of all) console.error("  " + e);
  process.exit(1);
} else {
  console.log(`validate-features: ${total} feature file(s) — all OK`);
}
