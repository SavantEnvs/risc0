#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the known-answer probe /mayhem/kat (built by mayhem/build.sh) and emit CTRF.
#
# The probe feeds a committed, genuine rv32im proof (mayhem/receipt_seal/testsuite/valid_po2_14.seal, a
# po2=14 seal produced by risc0's own CPU prover and accepted by its verifier) plus fixed corruptions of it
# to risc0_circuit_rv32im::verify, and prints the exact verdict of each. Each check asserts an exact verdict
# line: the real seal verifies Ok, and every malformed/tampered variant is rejected with a specific error.
# A neutered binary prints nothing, and a "fix" that makes verify() accept everything (or reject everything)
# fails these lines, so a no-op patch cannot pass.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASSED=0; FAILED=0; SKIPPED=0
SEAL="$SRC/mayhem/receipt_seal/testsuite/valid_po2_14.seal"

if [ ! -x /mayhem/kat ] || [ ! -f "$SEAL" ]; then
  echo "ERROR: /mayhem/kat or $SEAL missing — mayhem/build.sh should have produced the probe" >&2
  emit_ctrf "kat" 0 1 0
  exit 1
fi

KAT_OUT="$(/mayhem/kat "$SEAL" 2>/dev/null)"
kat_rc=$?
if [ "$kat_rc" -ne 0 ]; then
  echo "KAT FAIL: /mayhem/kat exited $kat_rc (neutered, missing, or verifier broken)" >&2
  FAILED=$(( FAILED + 1 ))
fi

kat_expect() {
  local label="$1" line="$2"
  if printf '%s\n' "$KAT_OUT" | grep -qxF "$line"; then
    echo "KAT PASS: $label"
    PASSED=$(( PASSED + 1 ))
  else
    echo "KAT FAIL: $label — expected exact line: $line" >&2
    FAILED=$(( FAILED + 1 ))
  fi
}

kat_expect "seal size"                    'KAT_SEAL_WORDS=45986'
kat_expect "seal version"                 'KAT_SEAL_VERSION=3'
kat_expect "seal po2"                     'KAT_SEAL_PO2=14'
kat_expect "genuine seal verifies"        'KAT_VALID=Ok(())'
kat_expect "empty seal rejected"          'KAT_EMPTY=Err(invalid receipt format)'
kat_expect "wrong version rejected"       'KAT_BAD_VERSION=Err(invalid receipt format)'
kat_expect "oversized po2 rejected"       'KAT_PO2_TOO_BIG=Err(invalid receipt format)'
kat_expect "flipped last word rejected"   'KAT_FLIPPED_LAST=Err(verification indicates proof is invalid)'
kat_expect "flipped middle word rejected" 'KAT_FLIPPED_MID=Err(verification indicates proof is invalid)'
kat_expect "wrong po2 rejected"           'KAT_WRONG_PO2=Err(verification indicates proof is invalid)'
kat_expect "truncated seal rejected"      'KAT_TRUNCATED=Err(invalid receipt format)'
kat_expect "header-only seal rejected"    'KAT_HEADER_ONLY=Err(invalid receipt format)'

emit_ctrf "kat" "$PASSED" "$FAILED" "$SKIPPED"
