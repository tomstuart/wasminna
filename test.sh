#!/bin/sh

ruby -Iwasminna wasminna/s_expression_parser_test.rb

for script in int_literals i32 i64 int_exprs float_literals
do
  ruby -Iwasminna wasminna/wasminna.rb spec/test/core/$script.wast
done
