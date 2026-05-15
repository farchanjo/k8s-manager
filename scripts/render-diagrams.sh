#!/usr/bin/env bash
# render-diagrams.sh — Render all Mermaid blocks and Structurizr views to PNG/SVG.
# Outputs artefacts into docs/arch/_rendered/.
# Tools are optional; the script skips gracefully when absent.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_ROOT="${REPO_ROOT}/docs/arch"
RENDERED_DIR="${ARCH_ROOT}/_rendered"
WORKSPACE="${ARCH_ROOT}/architecture/workspace.dsl"

RENDERED=0
SKIPPED=0

_cmd_exists() { command -v "$1" >/dev/null 2>&1; }
_skip()  { echo "[SKIP] $1 — $2"; ((SKIPPED+=1)); }
_done()  { echo "[DONE] $1"; ((RENDERED+=1)); }

mkdir -p "${RENDERED_DIR}"

echo "Rendering diagrams for K8sManager spec"
echo "Output: ${RENDERED_DIR}"
echo "---------------------------------------"

# ── Mermaid blocks from markdown files ────────────────────────────────────────

echo ""
echo "==> Mermaid blocks"

if _cmd_exists mmdc || pnpm dlx @mermaid-js/mermaid-cli --version >/dev/null 2>&1; then
  _mmdc="mmdc"
  if ! _cmd_exists mmdc; then
    _mmdc="pnpm dlx @mermaid-js/mermaid-cli mmdc"
  fi

  _md_files=()
  mapfile -t _md_files < <(find "${ARCH_ROOT}" -name "*.md" ! -path "${ARCH_ROOT}/_rendered/*" 2>/dev/null)

  for _md in "${_md_files[@]}"; do
    _rel="${_md#"${ARCH_ROOT}/"}"
    _stem="${_rel//\//-}"
    _stem="${_stem%.md}"

    # Extract each fenced ```mermaid block as a temp .mmd file then render
    _block_idx=0
    _in_block=0
    _block_lines=()

    while IFS= read -r _line; do
      if [[ "${_line}" == '```mermaid' ]]; then
        _in_block=1
        _block_lines=()
        continue
      fi
      if [[ "${_in_block}" -eq 1 ]] && [[ "${_line}" == '```' ]]; then
        _in_block=0
        ((_block_idx+=1))
        _tmp_mmd="${RENDERED_DIR}/${_stem}-${_block_idx}.mmd"
        printf '%s\n' "${_block_lines[@]}" > "${_tmp_mmd}"
        _out_svg="${RENDERED_DIR}/${_stem}-${_block_idx}.svg"
        if ${_mmdc} -i "${_tmp_mmd}" -o "${_out_svg}" 2>/dev/null; then
          _done "Mermaid block ${_block_idx} from ${_rel} → ${_stem}-${_block_idx}.svg"
        else
          echo "[WARN] Mermaid render failed for block ${_block_idx} in ${_rel}"
        fi
        rm -f "${_tmp_mmd}"
        _block_lines=()
        continue
      fi
      if [[ "${_in_block}" -eq 1 ]]; then
        _block_lines+=("${_line}")
      fi
    done < "${_md}"
  done
else
  _skip "Mermaid blocks" "mmdc not installed — run: pnpm dlx @mermaid-js/mermaid-cli"
fi

# ── Structurizr views ─────────────────────────────────────────────────────────

echo ""
echo "==> Structurizr views"

if [[ ! -f "${WORKSPACE}" ]]; then
  _skip "Structurizr export" "workspace.dsl not found at ${WORKSPACE}"
elif _cmd_exists structurizr-cli; then
  _struct_out="${RENDERED_DIR}/structurizr"
  mkdir -p "${_struct_out}"

  if structurizr-cli export \
      -format mermaid \
      -workspace "${WORKSPACE}" \
      -output "${_struct_out}" 2>/tmp/k8s-structurizr-render.txt; then
    _done "Structurizr views exported as Mermaid to ${_struct_out}"

    # Now render exported .mmd files if mmdc is available
    if _cmd_exists mmdc; then
      for _mmd in "${_struct_out}"/*.mmd; do
        _svg="${_mmd%.mmd}.svg"
        if mmdc -i "${_mmd}" -o "${_svg}" 2>/dev/null; then
          _done "Structurizr view → ${_svg##*/}"
        fi
      done
    fi
  else
    echo "[WARN] structurizr-cli export failed:"
    sed 's/^/    /' /tmp/k8s-structurizr-render.txt
  fi
else
  _skip "Structurizr export" "structurizr-cli not found; install from github.com/structurizr/cli/releases"
fi

# ── SUMMARY ────────────────────────────────────────────────────────────────────

echo ""
echo "============================================================"
echo "  Diagram render summary"
echo "  RENDERED: ${RENDERED}   SKIPPED: ${SKIPPED}"
echo "  Output dir: ${RENDERED_DIR}"
echo "============================================================"

exit 0
