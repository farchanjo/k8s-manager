#!/usr/bin/env bash
# validate-spec-fast.sh — Quick lane spec validation for K8sManager.
# Lane 1 (fast): ~2s. Static lint only; no external tools required.
# When ~/bin/spec is present, delegates to the user-global spec framework fast lane.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_ROOT="${REPO_ROOT}/docs/arch"
DECISIONS_DIR="${ARCH_ROOT}/decisions"
CONTEXTS_DIR="${ARCH_ROOT}/contexts"

PASS=0
FAIL=0

_pass() { echo "[PASS] $1"; ((PASS+=1)); }
_fail() { echo "[FAIL] $1"; ((FAIL+=1)); }

# ── delegate to user-global spec framework ─────────────────────────────────────

_SPEC_BIN="${HOME}/bin/spec"
if [[ -x "${_SPEC_BIN}" ]] && "${_SPEC_BIN}" --version >/dev/null 2>&1; then
  echo "spec framework found — delegating to ~/bin/spec validate --lane fast $*"
  exec "${_SPEC_BIN}" validate --lane fast "$@"
fi

echo "spec framework NOT found — running local fast lane"
echo "---------------------------------------------------"

# ── STEP 1: GFM-table sentinel ─────────────────────────────────────────────────

echo ""
echo "==> [1/4] GFM-table sentinel"

_gfm_hits=0
mapfile -t _md_files < <(find "${ARCH_ROOT}" -name "*.md" ! -path "${ARCH_ROOT}/_rendered/*" 2>/dev/null)
for _f in "${_md_files[@]}"; do
  _matches=$(grep -nE '^\|[^|]+\|' "${_f}" 2>/dev/null || true)
  if [[ -n "${_matches}" ]]; then
    echo "  GFM table in ${_f#"${REPO_ROOT}/"}:"
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
echo "==> [2/4] MADR section-header conformance"

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
    echo "  ${_adr##*/}: missing:"
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
echo "==> [3/4] DDD-role header on domain artefacts"

_ddd_fail=0

mapfile -t _cue_files < <(find "${CONTEXTS_DIR}" -name "*.cue" 2>/dev/null)
for _f in "${_cue_files[@]}"; do
  _first=$(head -1 "${_f}")
  if [[ "${_first}" != "// DDD role:"* ]]; then
    echo "  Missing DDD-role header: ${_f#"${REPO_ROOT}/"}"
    ((_ddd_fail+=1))
  fi
done

mapfile -t _rego_files < <(find "${CONTEXTS_DIR}" -name "*.rego" 2>/dev/null)
for _f in "${_rego_files[@]}"; do
  _first=$(head -1 "${_f}")
  if [[ "${_first}" != "# DDD role:"* ]] && [[ "${_first}" != "// DDD role:"* ]]; then
    echo "  Missing DDD-role header: ${_f#"${REPO_ROOT}/"}"
    ((_ddd_fail+=1))
  fi
done

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
echo "==> [4/4] kebab-case filename check"

_kebab_fail=0
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

# ── SUMMARY ────────────────────────────────────────────────────────────────────

echo ""
echo "============================================================"
echo "  Fast-lane summary"
echo "  PASS: ${PASS}   FAIL: ${FAIL}"
echo "============================================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi

exit 0
