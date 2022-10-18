#!/bin/sh

set -ex

WASMINNA_PATH=$(dirname "$0")

ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/s_expression_parser_test.rb

for script in int_literals i32 i64 int_exprs float_literals conversions
do
  ruby -I"$WASMINNA_PATH" "$WASMINNA_PATH"/wasminna.rb "$WASM_SPEC_PATH"/test/core/$script.wast
done
