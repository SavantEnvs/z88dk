#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for z88dk z80asm. RUNS the pre-built clean assembler
# (/mayhem/bin/z80asm-test, produced by mayhem/build.sh) as a set of known-answer tests:
# assemble small Z80 programs and assert the EXACT emitted machine-code bytes, and assert that
# invalid source is REJECTED with an error. This asserts BEHAVIOR/OUTPUT (not just exit code):
# a PATCH that neuters the assembler to exit(0) produces no/empty object output and thus FAILS.
#
# Emits a CTRF (ctrf.io) summary and exits non-zero iff any test failed. Does NOT compile —
# build.sh already built the binary; if it's missing that's a build.sh bug, so fail loudly.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

Z80ASM="$SRC/bin/z80asm-test"
if [ ! -x "$Z80ASM" ]; then
  echo "FATAL: $Z80ASM not found/executable — mayhem/build.sh did not build the oracle binary" >&2
  # still emit a CTRF failure so the grader records it
  printf 'CTRF {"results":{"tool":{"name":"z80asm-kat"},"summary":{"tests":1,"passed":0,"failed":1,"pending":0,"skipped":0,"other":0}}}\n'
  exit 1
fi

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

PASS=0; FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# assemble_hex <asm-source> -> prints the emitted .bin as space-separated lowercase hex on stdout;
# returns z80asm's exit code.
assemble_hex() {
  local src="$1" f="$WORK/t.asm"
  printf '%s' "$src" > "$f"
  rm -f "$WORK/t.bin" "$WORK/t.o"
  ( cd "$WORK" && "$Z80ASM" -b t.asm ) >/dev/null 2>&1
  local rc=$?
  if [ -f "$WORK/t.bin" ]; then od -An -v -tx1 "$WORK/t.bin" | tr -s ' ' | sed 's/^ //; s/ $//' | tr '\n' ' ' | tr -s ' ' | sed 's/ $//'; fi
  return $rc
}

# kat <name> <asm> <expected-hex>: known-answer test on emitted bytes.
kat() {
  local name="$1" asm="$2" want="$3" got
  got="$(assemble_hex "$asm")"
  if [ "$got" = "$want" ]; then
    echo "ok   $name  -> [$got]"; PASS=$((PASS+1))
  else
    echo "FAIL $name  want=[$want] got=[$got]"; FAIL=$((FAIL+1))
  fi
}

# rejects <name> <asm>: assembler must exit non-zero (invalid source is diagnosed).
rejects() {
  local name="$1" asm="$2" f="$WORK/bad.asm"
  printf '%s' "$asm" > "$f"
  if ( cd "$WORK" && "$Z80ASM" -b bad.asm ) >/dev/null 2>&1; then
    echo "FAIL $name  (invalid source accepted — expected an error)"; FAIL=$((FAIL+1))
  else
    echo "ok   $name  (invalid source rejected)"; PASS=$((PASS+1))
  fi
}

# ---- Known-answer opcode tests (canonical Z80 encodings) -----------------------------------------
kat "ld-a-imm/ld-b-imm/ret" $'    org 0\n    ld a,1\n    ld b,2\n    ret\n'       "3e 01 06 02 c9"
kat "add-a-b"               $'    org 0\n    ld a,1\n    ld b,2\n    add a,b\n    ret\n' "3e 01 06 02 80 c9"
kat "nop-halt"             $'    org 0\n    nop\n    halt\n'                       "00 76"
kat "inc-a-dec-b"          $'    org 0\n    inc a\n    dec b\n    ret\n'           "3c 05 c9"
kat "defb-bytes"           $'    org 0\n    defb 1,2,3,4\n'                        "01 02 03 04"
kat "ld-hl-imm16"          $'    org 0\n    ld hl,0x1234\n    ret\n'               "21 34 12 c9"
kat "jp-nn"                $'    org 0\n    jp 0x1234\n'                           "c3 34 12"

# ---- Negative tests: malformed source is rejected ------------------------------------------------
rejects "garbage-mnemonic"  $'    ld a, garbage !!\n'
rejects "unterminated-str"  $'xx: defb "\n'
rejects "bad-directive"     $'    org\n'

emit_ctrf "z80asm-kat" "$PASS" "$FAIL"
