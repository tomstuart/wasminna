#!/bin/sh

set -e
export RUBY_YJIT_ENABLE=1

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

for file in "$WASM_SPEC_PATH"/test/core/*.wast
do
  printf "\e[1m%s\e[0m: " "$file"
  ruby -I"$WASMINNA_PATH"/lib "$WASMINNA_PATH"/run_wast.rb $file
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
