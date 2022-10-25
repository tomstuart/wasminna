#!/bin/sh

set -ex

WASMINNA_PATH=$(dirname "$0")

for test in s_expression_parser_test float_test
do
  ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/$test.rb
done

for script in int_literals i32 i64 int_exprs float_literals conversions f32 f32_bitwise f32_cmp
do
  ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/wasminna.rb "$WASM_SPEC_PATH"/test/core/$script.wast
done

for pending in
do
  if ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/wasminna.rb "$WASM_SPEC_PATH"/test/core/$pending.wast; then
    echo "error: pending test passed"
    exit 1
  else
    echo "pending test failed successfully"
  fi
done
