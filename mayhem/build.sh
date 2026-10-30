#!/usr/bin/env bash
#
# mayhem/build.sh — build risc0's upstream cargo-fuzz target (risc0/fuzz: receipt_seal) as an
# ASan-instrumented libFuzzer binary, plus the mayhem/kat known-answer probe that mayhem/test.sh runs.
#
# AIR-GAPPED CONTRACT (SPEC 6.5): the PATCH tier re-runs this script offline. The first (online) build
# populates the cargo registry under $CARGO_HOME (/opt/toolchains/rust/cargo, pinned by the Dockerfile).
# The committed Cargo.lock files pin the same graph; the rlenv runtime exports CARGO_NET_OFFLINE=true
# for the re-run, so --offline is deliberately NOT hard-coded here. Every step is safe to repeat.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# $SANITIZER_FLAGS is the clang-oriented contract; rustc gets its own sanitizer via RUSTFLAGS below.
echo "SANITIZER_FLAGS (clang contract; informational for Rust)=${SANITIZER_FLAGS:-}"

: "${SRC:=/mayhem}"
cd "$SRC"

# Upstream's rust-toolchain.toml pins a stable channel that would override every bare `cargo`, and
# -Zsanitizer needs nightly, so every cargo call passes an explicit +<nightly>.
: "${RUST_FUZZ_TOOLCHAIN:?RUST_FUZZ_TOOLCHAIN must be set by mayhem/Dockerfile}"
TC="+$RUST_FUZZ_TOOLCHAIN"

# DWARF<=3 via the Dockerfile's anchor object linker wrapper (SPEC 6.2 item 10).
: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh}"
# Leak detection is disabled at build time for every ASan target: link a tiny TU defining
# __lsan_is_turned_off() into the harness.
mkdir -p "$SRC/target"
clang++ -c -O1 -g -gdwarf-3 mayhem/lsan_off.cc -o "$SRC/target/lsan_off.o"
# -asan-globals=0: with ASan global instrumentation on, every nightly 2025-12..2026-10 fails to link the
# harness (undefined `__sancov_gen_.N` referenced from `asan.module_dtor.*`), the "build issues" upstream's
# risc0/fuzz/README.md mentions. Heap/stack/UAF checks stay on; only global-variable redzones are lost.
FUZZ_RUSTFLAGS="--cfg fuzzing -Zsanitizer=address -Cllvm-args=-asan-globals=0 -Cforce-frame-pointers -Clink-arg=$SRC/target/lsan_off.o $RUST_DEBUG_FLAGS"

FUZZ_DIR="risc0/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"
FUZZ_TARGETS=(receipt_seal)

echo "=== cargo fuzz build (ASan via RUSTFLAGS, DWARF3 anchor) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo "$TC" fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  # risc0/fuzz is a member of upstream's root workspace, so cargo writes to $SRC/target.
  bin="$SRC/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp -f "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# KAT probe for mayhem/test.sh: normal (non-sanitized) flags, its own workspace + target dir. The repo's
# .cargo/config.toml sets -Dwarnings; clear it so the probe builds with plain flags.
echo "=== building /mayhem/kat (known-answer probe, normal flags) ==="
( cd mayhem/kat && env -u RUSTFLAGS cargo "$TC" build --release --config 'build.rustflags=[]' )
cp -f mayhem/kat/target/release/kat /mayhem/kat
if ! file /mayhem/kat | grep -q 'dynamically linked'; then
  echo "FATAL: /mayhem/kat is not dynamically linked — the sabotage check could not neuter it" >&2
  exit 1
fi

echo "build.sh complete:"
ls -la /mayhem/receipt_seal /mayhem/kat
