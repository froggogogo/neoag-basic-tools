#!/usr/bin/env bash
# Find a case-local wrapper or fail with a clear hint.
# Prefer existing CASE_ROOT scripts (sunbinbin-style) so this skill can drive
# a prepared case without rewriting every tool CLI.

find_wrapper() {
  local stem="$1"
  local cand
  for cand in \
    "${CASE_ROOT}/scripts/run_${stem}.sh" \
    "${CASE_ROOT}/scripts/run_${stem}_${SAMPLE_ID}.sh" \
    "${CASE_ROOT}/short-rna/scripts/run_${stem}.sh" \
    "${CASE_ROOT}/short-rna/scripts/run_${stem}_${SAMPLE_ID}.sh" \
    "${CASE_ROOT}/short-rna/scripts/run_${stem}_all.sh" \
    "${CASE_ROOT}/short-rna/scripts/run_${stem}_all_${SAMPLE_ID}.sh"
  do
    if [[ -f "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

run_wrapper_or_hint() {
  local stem="$1"
  local hint="$2"
  local w
  if w="$(find_wrapper "$stem")"; then
    log "dispatch ${stem} -> ${w}"
    bash "$w"
    return $?
  fi
  die "NO_WRAPPER" "缺少 ${stem} 运行包装脚本。${hint}"
}
