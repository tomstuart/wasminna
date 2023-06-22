assert_preprocess <<'--', <<'--'
  (module
    (func (import "spectest" "print_i32") (param i32))
  )
--
  (module
    (import "spectest" "print_i32" (func (param i32)))
  )
--

assert_preprocess <<'--', <<'--'
  (module $mymodule
    (func (import "spectest" "print_i32") (param i32))
  )
--
  (module $mymodule
    (import "spectest" "print_i32" (func (param i32)))
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (func $myfunction (import "spectest" "print_i32") (param i32))
--
  (import "spectest" "print_i32" (func $myfunction (param i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (table (import "spectest" "table") 0 funcref)
--
  (import "spectest" "table" (table 0 funcref))
--

assert_preprocess_module_fields <<'--', <<'--'
  (memory (import "spectest" "memory") 1 2)
--
  (import "spectest" "memory" (memory 1 2))
--

assert_preprocess_module_fields <<'--', <<'--'
  (global (import "spectest" "global_i32") i32)
--
  (import "spectest" "global_i32" (global i32))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
--
  (export "i32.test" (func $__fresh_0))
  (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
  (func (export "i32.umax") (result i32) (return (i32.const 0xffffffff)))
--
  (export "i32.test" (func $__fresh_0))
  (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
  (export "i32.umax" (func $__fresh_1))
  (func $__fresh_1 (result i32) (return (i32.const 0xffffffff)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func
    (export "i32.test1")
    (export "i32.test2")
    (export "i32.test3")
    (result i32)
    (return (i32.const 0x0bAdD00D))
  )
--
  (export "i32.test1" (func $__fresh_0))
  (export "i32.test2" (func $__fresh_0))
  (export "i32.test3" (func $__fresh_0))
  (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func
    (export "i32.test1")
    (export "i32.test2")
    (export "i32.test3")
    (import "mymodule" "bad_dude")
    (result i32)
  )
--
  (export "i32.test1" (func $__fresh_0))
  (export "i32.test2" (func $__fresh_0))
  (export "i32.test3" (func $__fresh_0))
  (import "mymodule" "bad_dude" (func $__fresh_0 (result i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (table (export "a") 0 1 funcref)
--
  (export "a" (table $__fresh_0))
  (table $__fresh_0 0 1 funcref)
--

assert_preprocess <<'--', <<'--'
  (func)
  (memory 0)
  (func (export "f"))
--
  (module
    (func)
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0)
  )
--

assert_preprocess <<'--', <<'--'
  (func)
  (memory 0)
  (func (export "f"))
  (invoke "f")
--
  (module
    (func)
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0)
  )
  (invoke "f")
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (result i32) (local i32 f64 funcref)
    (return (i32.const 0x0bAdD00D))
  )
--
  (func (result i32) (local i32) (local f64) (local funcref)
    (return (i32.const 0x0bAdD00D))
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32 i64) (result i64 i32)
    (i64.const 1)
    (i32.const 2)
  )
--
  (func (param i32) (param i64) (result i64) (result i32)
    (i64.const 1)
    (i32.const 2)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type (func (param i32 i64) (result f32 f64)))
--
  (type (func (param i32) (param i64) (result f32) (result f64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (import "a" "b" (func (param i32 i64) (result f32 f64)))
--
  (import "a" "b" (func (param i32) (param i64) (result f32) (result f64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func
    (block (param i32 i32) (result i32 i32)
      (i32.add)
      (i32.const 1)
    )
  )
--
  (func
    (block (param i32) (param i32) (result i32) (result i32)
      (i32.add)
      (i32.const 1)
    )
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (func
    (call_indirect
      (param i64) (param) (param f64 i32 i64)
      (result f32 f64) (result i32)
    )
  )
--
  (func
    (call_indirect
      (param i64) (param f64) (param i32) (param i64)
      (result f32) (result f64) (result i32)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module $M2 binary "\00asm" "\01\00\00\00")
--
  (module $M2 binary "\00asm" "\01\00\00\00")
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table $t)
    (offset
      (call_indirect (param i32 i64) (result f32 f64))
    )
    funcref (item ref.func $f)
  )
--
  (elem (table $t)
    (offset
      (call_indirect (param i32) (param i64) (result f32) (result f64))
    )
    funcref (item ref.func $f)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table $t) (offset i32.const 0) funcref
    (item (call_indirect (param i32 i64) (result f32 f64)))
  )
--
  (elem (table $t) (offset i32.const 0) funcref
    (item (call_indirect (param i32) (param i64) (result f32) (result f64)))
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table $t) (i32.const 0) funcref (item ref.func $f))
--
  (elem (table $t) (offset i32.const 0) funcref (item ref.func $f))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem funcref (ref.func $f))
--
  (elem funcref (item ref.func $f))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table 0) (offset i32.const 0) funcref (ref.func $f))
--
  (elem (table 0) (offset i32.const 0) funcref (item ref.func $f))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem declare funcref (ref.func $f))
--
  (elem declare funcref (item ref.func $f))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem
    func $f $g
  )
--
  (elem
    funcref (item ref.func $f) (item ref.func $g)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table 0) (offset i32.const 0)
    func $f $g
  )
--
  (elem (table 0) (offset i32.const 0)
    funcref (item ref.func $f) (item ref.func $g)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem declare
    func $f $g
  )
--
  (elem declare
    funcref (item ref.func $f) (item ref.func $g)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (offset i32.const 0) funcref (item ref.func $f))
--
  (elem (table 0) (offset i32.const 0) funcref (item ref.func $f))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (offset i32.const 0)
    $f $g
  )
--
  (elem (table 0) (offset i32.const 0)
    funcref (item ref.func $f) (item ref.func $g)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (table $t funcref (elem (item ref.func $f) (item ref.func $g)))
--
  (table $t 2 2 funcref)
  (elem (table $t) (offset i32.const 0) funcref (item ref.func $f) (item ref.func $g))
--

assert_preprocess_module_fields <<'--', <<'--'
  (table $t funcref (elem $f $g))
--
  (table $t 2 2 funcref)
  (elem (table $t) (offset i32.const 0) funcref (item ref.func $f) (item ref.func $g))
--

assert_preprocess_module_fields <<'--', <<'--'
  (data (memory $m)
    (offset
      (call_indirect (param i32 i64) (result f32 f64))
    )
    "hello" "world"
  )
--
  (data (memory $m)
    (offset
      (call_indirect (param i32) (param i64) (result f32) (result f64))
    )
    "hello" "world"
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (data $d (memory $m) (i32.const 0) "hello" "world")
--
  (data $d (memory $m) (offset i32.const 0) "hello" "world")
--

assert_preprocess_module_fields <<'--', <<'--'
  (data $d (offset i32.const 0) "hello" "world")
--
  (data $d (memory 0) (offset i32.const 0) "hello" "world")
--

assert_preprocess_module_fields <<'--', <<'--'
  (memory (data "hello" "world"))
--
  (memory $__fresh_0 1 1)
  (data (memory $__fresh_0) (offset i32.const 0) "hello" "world")
--

BEGIN {
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  def parse(string)
    Wasminna::SExpressionParser.new.parse(string)
  end

  def assert_preprocess(input, expected)
    input = parse(input)
    expected = parse(expected)
    actual = Wasminna::Preprocessor.new.process_script(input)

    if actual == expected
      print "\e[32m.\e[0m"
    else
      raise "expected #{expected}, got #{actual}"
    end
  end

  def assert_preprocess_module_fields(input, expected)
    assert_preprocess "(module #{input})", "(module #{expected})"
  end
}

END {
  puts
}
