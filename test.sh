#!/bin/sh

set -ex

WASMINNA_PATH=$(dirname "$0")

for test in s_expression_parser_test float_test
do
  ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/$test.rb
done

for script in int_literals i32 i64 int_exprs float_literals conversions
do
  ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/wasminna.rb "$WASM_SPEC_PATH"/test/core/$script.wast
done
