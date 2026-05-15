#!/usr/bin/env node
// check-mermaid.mjs — extract every ```mermaid block under docs/arch and README.md,
// pipe each to mmdc, report parse failures only. Exits 0 (informational sweep).
import { readdirSync, statSync, readFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

const REPO_ROOT = new URL("..", import.meta.url).pathname;
const ARCH_ROOT = join(REPO_ROOT, "docs/arch");

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === "_rendered" || entry === "node_modules") continue;
    const p = join(dir, entry);
    const s = statSync(p);
    if (s.isDirectory()) walk(p, acc);
    else if (entry.endsWith(".md")) acc.push(p);
  }
  return acc;
}

function extractBlocks(content) {
  const blocks = [];
  const lines = content.split("\n");
  let inBlock = false;
  let buf = [];
  let startLine = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!inBlock && /^\s*```mermaid\s*$/.test(line)) {
      inBlock = true;
      startLine = i + 2;
      buf = [];
      continue;
    }
    if (inBlock && /^\s*```\s*$/.test(line)) {
      blocks.push({ startLine, body: buf.join("\n") });
      inBlock = false;
      continue;
    }
    if (inBlock) buf.push(line);
  }
  return blocks;
}

const files = [...walk(ARCH_ROOT), join(REPO_ROOT, "README.md")];
const tmpRoot = mkdtempSync(join(tmpdir(), "mermaid-check-"));
let failures = 0;
let totalBlocks = 0;

for (const file of files) {
  const content = readFileSync(file, "utf8");
  const blocks = extractBlocks(content);
  for (let idx = 0; idx < blocks.length; idx++) {
    totalBlocks++;
    const { startLine, body } = blocks[idx];
    const inPath = join(tmpRoot, `block-${failures}-${idx}.mmd`);
    const outPath = join(tmpRoot, `block-${failures}-${idx}.svg`);
    writeFileSync(inPath, body);
    const res = spawnSync("mmdc", ["-i", inPath, "-o", outPath, "-q"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    if (res.status !== 0) {
      failures++;
      const err = (res.stderr || res.stdout || "").trim();
      const firstLine = err.split("\n").find((l) => l.includes("error") || l.includes("Parse")) || err.split("\n")[0];
      console.log(`${relative(REPO_ROOT, file)}:${startLine} — ${firstLine.slice(0, 200)}`);
    }
  }
}

rmSync(tmpRoot, { recursive: true, force: true });
console.log(`---\n${totalBlocks} mermaid blocks scanned, ${failures} failed to render.`);
