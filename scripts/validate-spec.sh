#!/usr/bin/env bash
# validate-spec.sh — Full spec validation pack for K8sManager.
# Lane 2 (default): ~10s. Runs all available validators in the local matrix.
# When ~/bin/spec is present, delegates entirely to the user-global spec framework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_ROOT="${REPO_ROOT}/docs/arch"
DECISIONS_DIR="${ARCH_ROOT}/decisions"
CONTEXTS_DIR="${ARCH_ROOT}/contexts"

PASS=0
FAIL=0
SKIP=0

# ── helpers ────────────────────────────────────────────────────────────────────

_pass() { echo "[PASS] $1"; ((PASS+=1)); }
_fail() { echo "[FAIL] $1"; ((FAIL+=1)); }
_skip() { echo "[SKIP] $1 — $2"; ((SKIP+=1)); }

_cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# ── delegate to user-global spec framework ─────────────────────────────────────
# Probe the framework with --version before delegating; if the binary exits
# non-zero (e.g. framework directory not installed), fall through to the local
# validation matrix instead of propagating an unhelpful error.

_SPEC_BIN="${HOME}/bin/spec"
if [[ -x "${_SPEC_BIN}" ]] && "${_SPEC_BIN}" --version >/dev/null 2>&1; then
  echo "spec framework found — delegating to ~/bin/spec validate $*"
  exec "${_SPEC_BIN}" validate "$@"
fi

echo "spec framework NOT found — running local validation matrix"
echo "------------------------------------------------------------"

# ── STEP 1: GFM-table sentinel ─────────────────────────────────────────────────
# Fail if any GFM pipe-table row is found inside docs/arch/.
# Tables are forbidden everywhere in docs/arch/ (see conventions).

echo ""
echo "==> [1/9] GFM-table sentinel"

# Collect candidate markdown files (exclude _rendered/)
mapfile -t _md_files < <(find "${ARCH_ROOT}" -name "*.md" ! -path "${ARCH_ROOT}/_rendered/*" 2>/dev/null)

_gfm_hits=0
for _f in "${_md_files[@]}"; do
  _matches=$(grep -nE '^\|[^|]+\|' "${_f}" 2>/dev/null || true)
  if [[ -n "${_matches}" ]]; then
    echo "  GFM table in ${_f}:"
    echo "${_matches}" | sed 's/^/    /'
    ((_gfm_hits+=1))
  fi
done

if [[ ${_gfm_hits} -eq 0 ]]; then
  _pass "GFM-table sentinel — no pipe tables in docs/arch/"
else
  _fail "GFM-table sentinel — ${_gfm_hits} file(s) contain GFM tables"
fi

# ── STEP 2: MADR section-header conformance ────────────────────────────────────

echo ""
echo "==> [2/9] MADR section-header conformance"

_required_sections=(
  "## Context and problem statement"
  "## Decision drivers"
  "## Decision outcome"
  "## More information"
)

_madr_fail=0
mapfile -t _adr_files < <(find "${DECISIONS_DIR}" -name "adr-*.md" 2>/dev/null | sort)

for _adr in "${_adr_files[@]}"; do
  _missing=()
  for _section in "${_required_sections[@]}"; do
    if ! grep -qF "${_section}" "${_adr}"; then
      _missing+=("${_section}")
    fi
  done
  if [[ ${#_missing[@]} -gt 0 ]]; then
    echo "  ${_adr##*/}: missing sections:"
    for _s in "${_missing[@]}"; do echo "    ${_s}"; done
    ((_madr_fail+=1))
  fi
done

if [[ ${_madr_fail} -eq 0 ]]; then
  _pass "MADR conformance — ${#_adr_files[@]} ADR(s) all have required sections"
else
  _fail "MADR conformance — ${_madr_fail} ADR(s) missing required sections"
fi

# ── STEP 3: DDD-role header ────────────────────────────────────────────────────

echo ""
echo "==> [3/9] DDD-role header on domain artefacts"

_ddd_fail=0

# CUE files: first line must match "// DDD role:"
mapfile -t _cue_files < <(find "${CONTEXTS_DIR}" -name "*.cue" 2>/dev/null)
for _f in "${_cue_files[@]}"; do
  _first=$(head -1 "${_f}")
  if [[ "${_first}" != "// DDD role:"* ]]; then
    echo "  Missing DDD-role header: ${_f#"${REPO_ROOT}/"}"
    ((_ddd_fail+=1))
  fi
done

# Rego files: first line must match "# DDD role:" or "// DDD role:"
mapfile -t _rego_files < <(find "${CONTEXTS_DIR}" -name "*.rego" 2>/dev/null)
for _f in "${_rego_files[@]}"; do
  _first=$(head -1 "${_f}")
  if [[ "${_first}" != "# DDD role:"* ]] && [[ "${_first}" != "// DDD role:"* ]]; then
    echo "  Missing DDD-role header: ${_f#"${REPO_ROOT}/"}"
    ((_ddd_fail+=1))
  fi
done

# Gherkin feature files: first non-blank line must match "# DDD role:"
mapfile -t _feature_files < <(find "${CONTEXTS_DIR}" -name "*.feature" 2>/dev/null)
for _f in "${_feature_files[@]}"; do
  _first=$(grep -m1 "." "${_f}" || true)
  if [[ "${_first}" != "# DDD role:"* ]]; then
    echo "  Missing DDD-role header: ${_f#"${REPO_ROOT}/"}"
    ((_ddd_fail+=1))
  fi
done

if [[ ${_ddd_fail} -eq 0 ]]; then
  _pass "DDD-role header — all .cue/.rego/.feature files conform"
else
  _fail "DDD-role header — ${_ddd_fail} file(s) missing header"
fi

# ── STEP 4: kebab-case filename check ─────────────────────────────────────────

echo ""
echo "==> [4/9] kebab-case filename check"

_kebab_fail=0

# Markdown files inside docs/arch/ must be kebab-case (allow digits, hyphens, dots).
# README.md is the universal repository standard; exempt it explicitly.
while IFS= read -r -d '' _f; do
  _base=$(basename "${_f}")
  if [[ "${_base}" == "README.md" ]]; then continue; fi
  if [[ "${_base}" =~ [A-Z_\ ] ]]; then
    echo "  Non-kebab filename: ${_f#"${REPO_ROOT}/"}"
    ((_kebab_fail+=1))
  fi
done < <(find "${ARCH_ROOT}" -name "*.md" ! -path "${ARCH_ROOT}/_rendered/*" -print0 2>/dev/null)

if [[ ${_kebab_fail} -eq 0 ]]; then
  _pass "kebab-case filenames — all .md files conform"
else
  _fail "kebab-case filenames — ${_kebab_fail} file(s) violate convention"
fi

# ── STEP 5: CUE schema validation ─────────────────────────────────────────────

echo ""
echo "==> [5/9] CUE schema validation"

if _cmd_exists cue; then
  # cue vet requires relative paths from a module root; pass `./...` from the repo.
  if ( cd "${REPO_ROOT}" && cue vet ./docs/arch/contexts/... ) 2>/tmp/k8s-spec-cue-err.txt; then
    _pass "CUE vet — all schema packages pass"
  else
    echo "  CUE vet errors:"
    sed 's/^/    /' /tmp/k8s-spec-cue-err.txt
    _fail "CUE vet — schema packages failed"
  fi
else
  _skip "CUE vet" "cue binary not found; install via go install cuelang.org/go/cmd/cue@latest"
fi

# ── STEP 6: Rego policy validation ────────────────────────────────────────────

echo ""
echo "==> [6/9] Rego policy validation (conftest)"

if _cmd_exists opa; then
  _rego_fail=0

  # `opa check` validates Rego policy syntax + references.
  # conftest does NOT have a `.rego` parser (it parses input data, not policies).
  # --v0-compatible accepts Rego v0 syntax (no `if`/`contains` requirement)
  # while OPA 0.69+ defaults to Rego v1. Pin v0 compat until policies migrate.
  mapfile -t _rego_files < <(find "${CONTEXTS_DIR}" -name "*.rego" | sort)
  for _rego in "${_rego_files[@]}"; do
    if ! opa check --v0-compatible "${_rego}" >/tmp/k8s-spec-rego-err.txt 2>&1; then
      echo "  opa check error in ${_rego#"${REPO_ROOT}/"}:"
      sed 's/^/    /' /tmp/k8s-spec-rego-err.txt
      ((_rego_fail+=1))
    fi
  done
  if [[ ${_rego_fail} -eq 0 ]]; then
    _pass "Rego policy validation — ${#_rego_files[@]} policy file(s) parse cleanly"
  else
    _fail "Rego policy validation — ${_rego_fail} policy file(s) failed"
  fi
else
  _skip "Rego policy validation" "opa not found; install via 'brew install opa' or https://www.openpolicyagent.org/docs/latest/#running-opa"
fi

# ── STEP 7: Gherkin lint ──────────────────────────────────────────────────────

echo ""
echo "==> [7/9] Gherkin lint"

if _cmd_exists gherkin-lint; then
  if ! gherkin-lint "${CONTEXTS_DIR}"/**/*.feature "${CONTEXTS_DIR}"/**/**/*.feature 2>/tmp/k8s-spec-gherkin-err.txt; then
    echo "  gherkin-lint errors:"
    sed 's/^/    /' /tmp/k8s-spec-gherkin-err.txt
    _fail "Gherkin lint — errors found"
  else
    _pass "Gherkin lint — all .feature files conform"
  fi
else
  # Fallback: regex check that every Scenario block has at least one When and one Then
  echo "  gherkin-lint not found — running basic When/Then regex check"
  _gherkin_fail=0
  for _f in "${_feature_files[@]}"; do
    _scenarios=$(grep -c "^\s*Scenario" "${_f}" 2>/dev/null || echo 0)
    _whens=$(grep -c "^\s*When" "${_f}" 2>/dev/null || echo 0)
    _thens=$(grep -c "^\s*Then" "${_f}" 2>/dev/null || echo 0)
    if [[ ${_scenarios} -gt 0 ]] && { [[ ${_whens} -eq 0 ]] || [[ ${_thens} -eq 0 ]]; }; then
      echo "  Scenario missing When or Then: ${_f#"${REPO_ROOT}/"}"
      ((_gherkin_fail+=1))
    fi
  done
  if [[ ${_gherkin_fail} -eq 0 ]]; then
    _pass "Gherkin basic When/Then check — all scenarios pass"
  else
    _fail "Gherkin basic When/Then check — ${_gherkin_fail} file(s) failed"
  fi
fi

# ── STEP 8: DBML lint ─────────────────────────────────────────────────────────
#
# Uses @dbml/core Parser directly. dbml2sql tolerates duplicate-endpoint refs
# and exits 0 on broken files; @dbml/core enforces structural rules and is
# the parser used by dbdocs and dbdiagram.io. This step exits non-zero on
# any parse error so CI catches the class of bug fixed in May 2026.

echo ""
echo "==> [8/9] DBML lint (@dbml/core parser)"

_dbml_file="${CONTEXTS_DIR}/local_persistence/schemas/storage.dbml"

if [[ -f "${_dbml_file}" ]]; then
  if [[ -d "${REPO_ROOT}/node_modules/@dbml/core" ]] && _cmd_exists node; then
    if node -e "const {Parser}=require('@dbml/core'); const fs=require('fs'); try { Parser.parse(fs.readFileSync(process.argv[1],'utf8'),'dbml'); } catch (e) { console.error(e.message); process.exit(1); }" "${_dbml_file}" 2>/tmp/k8s-spec-dbml-err.txt; then
      _pass "DBML lint — storage.dbml parses cleanly"
    else
      echo "  @dbml/core error:"
      sed 's/^/    /' /tmp/k8s-spec-dbml-err.txt
      _fail "DBML lint — storage.dbml parse failed"
    fi
  else
    _skip "DBML lint" "@dbml/core not installed; run pnpm install"
  fi
else
  _skip "DBML lint" "storage.dbml not found at expected path"
fi

# ── STEP 9: Structurizr DSL validation ────────────────────────────────────────

echo ""
echo "==> [9/9] Structurizr DSL validation"

_workspace="${ARCH_ROOT}/architecture/workspace.dsl"

if [[ -f "${_workspace}" ]]; then
  if _cmd_exists structurizr-cli; then
    if ! structurizr-cli validate -workspace "${_workspace}" 2>/tmp/k8s-spec-structurizr-err.txt; then
      echo "  structurizr-cli error:"
      sed 's/^/    /' /tmp/k8s-spec-structurizr-err.txt
      _fail "Structurizr DSL — workspace.dsl validation failed"
    else
      _pass "Structurizr DSL — workspace.dsl is valid"
    fi
  else
    _skip "Structurizr DSL" "structurizr-cli not found; install from github.com/structurizr/cli/releases"
  fi
else
  _skip "Structurizr DSL" "workspace.dsl not found at ${_workspace}"
fi

# ── SUMMARY ────────────────────────────────────────────────────────────────────

echo ""
echo "============================================================"
echo "  Validation summary"
echo "  PASS: ${PASS}   FAIL: ${FAIL}   SKIP: ${SKIP}"
echo "============================================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi

exit 0
