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

assert_preprocess <<'--', <<'--'
  (module
    (func $myfunction (import "spectest" "print_i32") (param i32))
  )
--
  (module
    (import "spectest" "print_i32" (func $myfunction (param i32)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (table (import "spectest" "table") 0 funcref)
  )
--
  (module
    (import "spectest" "table" (table 0 funcref))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (memory (import "spectest" "memory") 1 2)
  )
--
  (module
    (import "spectest" "memory" (memory 1 2))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (global (import "spectest" "global_i32") i32)
  )
--
  (module
    (import "spectest" "global_i32" (global i32))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
  )
--
  (module
    (export "i32.test" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
    (func (export "i32.umax") (result i32) (return (i32.const 0xffffffff)))
  )
--
  (module
    (export "i32.test" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
    (export "i32.umax" (func $__fresh_1))
    (func $__fresh_1 (result i32) (return (i32.const 0xffffffff)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func
      (export "i32.test1")
      (export "i32.test2")
      (export "i32.test3")
      (result i32)
      (return (i32.const 0x0bAdD00D))
    )
  )
--
  (module
    (export "i32.test1" (func $__fresh_0))
    (export "i32.test2" (func $__fresh_0))
    (export "i32.test3" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func
      (export "i32.test1")
      (export "i32.test2")
      (export "i32.test3")
      (import "mymodule" "bad_dude")
      (result i32)
    )
  )
--
  (module
    (export "i32.test1" (func $__fresh_0))
    (export "i32.test2" (func $__fresh_0))
    (export "i32.test3" (func $__fresh_0))
    (import "mymodule" "bad_dude" (func $__fresh_0 (result i32)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (table (export "a") 0 1 funcref)
  )
--
  (module
    (export "a" (table $__fresh_0))
    (table $__fresh_0 0 1 funcref)
  )
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

assert_preprocess <<'--', <<'--'
  (module
    (func (result i32) (local i32 f64 funcref)
      (return (i32.const 0x0bAdD00D))
    )
  )
--
  (module
    (func (result i32) (local i32) (local f64) (local funcref)
      (return (i32.const 0x0bAdD00D))
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func (param i32 i64) (result i64 i32)
      (i64.const 1)
      (i32.const 2)
    )
  )
--
  (module
    (func (param i32) (param i64) (result i64) (result i32)
      (i64.const 1)
      (i32.const 2)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (type (func (param i32 i64) (result f32 f64)))
  )
--
  (module
    (type (func (param i32) (param i64) (result f32) (result f64)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (import a b (func (param i32 i64) (result f32 f64)))
  )
--
  (module
    (import a b (func (param i32) (param i64) (result f32) (result f64)))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func
      (block (param i32 i32) (result i32 i32)
        (i32 add)
        (i32.const 1)
      )
    )
  )
--
  (module
    (func
      (block (param i32) (param i32) (result i32) (result i32)
        (i32 add)
        (i32.const 1)
      )
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (func
      (call_indirect
        (param i64) (param) (param f64 i32 i64)
        (result f32 f64) (result i32)
      )
    )
  )
--
  (module
    (func
      (call_indirect
        (param i64) (param f64) (param i32) (param i64)
        (result f32) (result f64) (result i32)
      )
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module $M2 binary "\00asm" "\01\00\00\00")
--
  (module $M2 binary "\00asm" "\01\00\00\00")
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (table $t)
      (offset
        (call_indirect (param i32 i64) (result f32 f64))
      )
      funcref (item ref.func $f)
    )
  )
--
  (module
    (elem (table $t)
      (offset
        (call_indirect (param i32) (param i64) (result f32) (result f64))
      )
      funcref (item ref.func $f)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (table $t) (offset i32.const 0) funcref
      (item (call_indirect (param i32 i64) (result f32 f64)))
    )
  )
--
  (module
    (elem (table $t) (offset i32.const 0) funcref
      (item (call_indirect (param i32) (param i64) (result f32) (result f64)))
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (table $t) (i32.const 0) funcref (item ref.func $f))
  )
--
  (module
    (elem (table $t) (offset i32.const 0) funcref (item ref.func $f))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem funcref (ref.func $f))
  )
--
  (module
    (elem funcref (item ref.func $f))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (table 0) (offset i32.const 0) funcref (ref.func $f))
  )
--
  (module
    (elem (table 0) (offset i32.const 0) funcref (item ref.func $f))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem declare funcref (ref.func $f))
  )
--
  (module
    (elem declare funcref (item ref.func $f))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem
      func $f $g
    )
  )
--
  (module
    (elem
      funcref (item ref.func $f) (item ref.func $g)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (table 0) (offset i32.const 0)
      func $f $g
    )
  )
--
  (module
    (elem (table 0) (offset i32.const 0)
      funcref (item ref.func $f) (item ref.func $g)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem declare
      func $f $g
    )
  )
--
  (module
    (elem declare
      funcref (item ref.func $f) (item ref.func $g)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (offset i32.const 0) funcref (item ref.func $f))
  )
--
  (module
    (elem (table 0) (offset i32.const 0) funcref (item ref.func $f))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (elem (offset i32.const 0)
      $f $g
    )
  )
--
  (module
    (elem (table 0) (offset i32.const 0)
      funcref (item ref.func $f) (item ref.func $g)
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (table $t funcref (elem (item ref.func $f) (item ref.func $g)))
  )
--
  (module
    (table $t 2 2 funcref)
    (elem (table $t) (offset i32.const 0) funcref (item ref.func $f) (item ref.func $g))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (table $t funcref (elem $f $g))
  )
--
  (module
    (table $t 2 2 funcref)
    (elem (table $t) (offset i32.const 0) funcref (item ref.func $f) (item ref.func $g))
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (data (memory $m)
      (offset
        (call_indirect (param i32 i64) (result f32 f64))
      )
      "hello" "world"
    )
  )
--
  (module
    (data (memory $m)
      (offset
        (call_indirect (param i32) (param i64) (result f32) (result f64))
      )
      "hello" "world"
    )
  )
--

assert_preprocess <<'--', <<'--'
  (module
    (data $d (memory $m) (i32.const 0) "hello" "world")
  )
--
  (module
    (data $d (memory $m) (offset i32.const 0) "hello" "world")
  )
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
}

END {
  puts
}
