#!/bin/sh

set -e

WASMINNA_PATH=$(dirname "$0")
if [ -z "$WASM_SPEC_PATH" ]; then
  WASM_SPEC_PATH="$WASMINNA_PATH"/../spec
  printf "\e[33mno WASM_SPEC_PATH set, guessing %s\e[0m\n" "$WASM_SPEC_PATH"
fi

for test in s_expression_parser_test float_test
do
  file=$test.rb
  printf "\e[1m%s\e[0m: " "$file"
  ruby -I"$WASMINNA_PATH"/lib "$WASMINNA_PATH"/test/$file
done

for script in int_literals i32 i64 int_exprs float_literals conversions f32 f32_bitwise f32_cmp f64 f64_bitwise f64_cmp float_memory float_exprs float_misc const local_set local_get store br labels return br_if call local_tee stack nop func comments if block loop load memory endianness fac forward unwind left-to-right memory_size memory_grow address align exports global br_table names func_ptrs data select elem call_indirect table bulk table-sub table_copy table_init table_get table_set binary-leb128 binary custom memory_copy memory_fill memory_init memory_redundancy memory_trap ref_func ref_is_null switch token traps type unreachable unreached-invalid unreached-valid utf8-custom-section-id utf8-import-field utf8-import-module utf8-invalid-encoding tokens imports inline-module
do
  file=$script.wast
  printf "\e[1m%s\e[0m: " "$file"
  ruby -I"$WASMINNA_PATH"/lib "$WASMINNA_PATH"/run_wast.rb "$WASM_SPEC_PATH"/test/core/$file
done

for pending in
do
  file=$pending.wast
  printf "\e[1m%s\e[0m (pending): " "$file"
  if ruby -I"$WASMINNA_PATH"/lib "$WASMINNA_PATH"/run_wast.rb "$WASM_SPEC_PATH"/test/core/$file; then
    printf "\e[31merror: pending test passed\e[0m\n"
    exit 1
  else
    printf "\e[32mpending test failed successfully\e[0m\n"
  fi
done
