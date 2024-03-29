assert_preprocess <<'--', <<'--'
  (module
    (type $t (func (param i32)))
    (func (import "spectest" "print_i32") (type $t))
  )
--
  (module
    (type $t (func (param i32)))
    (import "spectest" "print_i32" (func (type $t)))
  )
--

assert_preprocess <<'--', <<'--'
  (module $mymodule
    (type $t (func (param i32)))
    (func (import "spectest" "print_i32") (type $t))
  )
--
  (module $mymodule
    (type $t (func (param i32)))
    (import "spectest" "print_i32" (func (type $t)))
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32)))
  (func $myfunction (import "spectest" "print_i32") (type $t))
--
  (type $t (func (param i32)))
  (import "spectest" "print_i32" (func $myfunction (type $t)))
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
  (type $t (func (result i32)))
  (func (export "i32.test") (type $t)
    i32.const 0x0bAdD00D
    return
  )
--
  (type $t (func (result i32)))
  (export "i32.test" (func $__fresh_0))
  (func $__fresh_0 (type $t)
    i32.const 0x0bAdD00D
    return
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (result i32)))
  (func (export "i32.test") (type $t)
    i32.const 0x0bAdD00D
    return
  )
  (func (export "i32.umax") (type $t)
    i32.const 0xffffffff
    return
  )
--
  (type $t (func (result i32)))
  (export "i32.test" (func $__fresh_0))
  (func $__fresh_0 (type $t)
    i32.const 0x0bAdD00D
    return
  )
  (export "i32.umax" (func $__fresh_1))
  (func $__fresh_1 (type $t)
    i32.const 0xffffffff
    return
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (result i32)))
  (func
    (export "i32.test1")
    (export "i32.test2")
    (export "i32.test3")
    (type $t)
    i32.const 0x0bAdD00D
    return
  )
--
  (type $t (func (result i32)))
  (export "i32.test1" (func $__fresh_0))
  (export "i32.test2" (func $__fresh_0))
  (export "i32.test3" (func $__fresh_0))
  (func $__fresh_0 (type $t)
    i32.const 0x0bAdD00D
    return
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (result i32)))
  (func
    (export "i32.test1")
    (export "i32.test2")
    (export "i32.test3")
    (import "mymodule" "bad_dude")
    (type $t)
  )
--
  (type $t (func (result i32)))
  (export "i32.test1" (func $__fresh_0))
  (export "i32.test2" (func $__fresh_0))
  (export "i32.test3" (func $__fresh_0))
  (import "mymodule" "bad_dude" (func $__fresh_0 (type $t)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (table (export "a") 0 1 funcref)
--
  (export "a" (table $__fresh_0))
  (table $__fresh_0 0 1 funcref)
--

assert_preprocess <<'--', <<'--'
  (type $t (func))
  (func (type $t))
  (memory 0)
  (func (export "f") (type $t))
--
  (module
    (type $t (func))
    (func (type $t))
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0 (type $t))
  )
--

assert_preprocess <<'--', <<'--'
  (type $t (func))
  (func (type $t))
  (memory 0)
  (func (export "f") (type $t))
  (invoke "f")
--
  (module
    (type $t (func))
    (func (type $t))
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0 (type $t))
  )
  (invoke "f")
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (result i32)))
  (func (type $t) (local i32 f64 funcref)
    i32.const 0x0bAdD00D
    return
  )
--
  (type $t (func (result i32)))
  (func (type $t) (local i32) (local f64) (local funcref)
    i32.const 0x0bAdD00D
    return
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i64) (result i64) (result i32)))
  (func (type $t) (param i32 i64) (result i64 i32)
    i64.const 1
    i32.const 2
  )
--
  (type $t (func (param i32) (param i64) (result i64) (result i32)))
  (func (type $t) (param i32) (param i64) (result i64) (result i32)
    i64.const 1
    i32.const 2
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type (func (param i32 i64) (result f32 f64)))
--
  (type (func (param i32) (param i64) (result f32) (result f64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (import "a" "b" (func (type $t) (param i32 i64) (result f32 f64)))
--
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (import "a" "b" (func (type $t) (param i32) (param i64) (result f32) (result f64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t1 (func))
  (type $t2 (func (param i32) (param i32) (result i32) (result i32)))
  (func (type $t1)
    block (type $t2) (param i32 i32) (result i32 i32)
      i32.add
      i32.const 1
    end
  )
--
  (type $t1 (func))
  (type $t2 (func (param i32) (param i32) (result i32) (result i32)))
  (func (type $t1)
    block (type $t2) (param i32) (param i32) (result i32) (result i32)
      i32.add
      i32.const 1
    end
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t1 (func))
  (type $t2 (func
    (param i64) (param f64) (param i32) (param i64)
    (result f32) (result f64) (result i32))
  )
  (func (type $t1)
    call_indirect 0 (type $t2)
      (param i64) (param) (param f64 i32 i64)
      (result f32 f64) (result i32)
  )
--
  (type $t1 (func))
  (type $t2 (func
    (param i64) (param f64) (param i32) (param i64)
    (result f32) (result f64) (result i32))
  )
  (func (type $t1)
    call_indirect 0 (type $t2)
      (param i64) (param f64) (param i32) (param i64)
      (result f32) (result f64) (result i32)
  )
--

assert_preprocess <<'--', <<'--'
  (module $M2 binary "\00asm" "\01\00\00\00")
--
  (module $M2 binary "\00asm" "\01\00\00\00")
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t1 (func (param i32) (param i64) (result f32) (result f64)))
  (elem (table $t)
    (offset
      call_indirect 0 (type $t1) (param i32 i64) (result f32 f64)
    )
    funcref (item ref.func $f)
  )
--
  (type $t1 (func (param i32) (param i64) (result f32) (result f64)))
  (elem (table $t)
    (offset
      call_indirect 0 (type $t1) (param i32) (param i64) (result f32) (result f64)
    )
    funcref (item ref.func $f)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t1 (func (param i32) (param i64) (result f32) (result f64)))
  (elem (table $t) (offset i32.const 0) funcref
    (item call_indirect 0 (type $t1) (param i32 i64) (result f32 f64))
  )
--
  (type $t1 (func (param i32) (param i64) (result f32) (result f64)))
  (elem (table $t) (offset i32.const 0) funcref
    (item call_indirect 0 (type $t1) (param i32) (param i64) (result f32) (result f64))
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
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (data (memory $m)
    (offset
      call_indirect 0 (type $t) (param i32 i64) (result f32 f64)
    )
    "hello" "world"
  )
--
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (data (memory $m)
    (offset
      call_indirect 0 (type $t) (param i32) (param i64) (result f32) (result f64)
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

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (global $g i32
    call_indirect 0 (type $t) (param i32 i64) (result f32 f64)
  )
--
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (global $g i32
    call_indirect 0 (type $t) (param i32) (param i64) (result f32) (result f64)
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (func (import "a" "b") (type $t) (param i32 i64) (result f32 f64))
--
  (type $t (func (param i32) (param i64) (result f32) (result f64)))
  (import "a" "b" (func (type $t) (param i32) (param i64) (result f32) (result f64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    select (result i32 i32)
  )
  (type (func (result i32) (result i32)))
--
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    select (result i32) (result i32)
  )
  (type (func (result i32) (result i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    i32.const 1
    i32.add
    select (result i32 i32)
  )
  (type (func (result i32) (result i32)))
--
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    i32.const 1
    i32.add
    select (result i32) (result i32)
  )
  (type (func (result i32) (result i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    select (result i32 i32)
    i32.const 1
    i32.add
  )
  (type (func (result i32) (result i32)))
--
  (type $t (func (param i32) (param i32) (param i32) (result i32)))
  (func (type $t)
    local.get 0
    local.get 1
    local.get 2
    select (result i32) (result i32)
    i32.const 1
    i32.add
  )
  (type (func (result i32) (result i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block
    end
  )
--
  (type $t (func))
  (func (type $t)
    block
    end
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block (result)
    end
  )
--
  (type $t (func))
  (func (type $t)
    block
    end
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block (result i64)
      i64.const 1
    end
  )
  (type (func (result i64)))
--
  (type $t (func))
  (func (type $t)
    block (result i64)
      i64.const 1
    end
  )
  (type (func (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block (param) (result i64)
      i64.const 1
    end
  )
  (type (func (result i64)))
--
  (type $t (func))
  (func (type $t)
    block (result i64)
      i64.const 1
    end
  )
  (type (func (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t1 (func (param i32) (result i32)))
  (type $t2 (func (param i32) (param i64) (result f32) (result f64)))
  (func (type $t1)
    call_indirect 0 (type $t2) (param i32 i64) (result f32 f64)
    i32.const 1
    i32.add
  )
--
  (type $t1 (func (param i32) (result i32)))
  (type $t2 (func (param i32) (param i64) (result f32) (result f64)))
  (func (type $t1)
    call_indirect 0 (type $t2) (param i32) (param i64) (result f32) (result f64)
    i32.const 1
    i32.add
  )
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32) (result i64)
    i64.const 1
  )
  (type (func (param i32) (result i64)))
--
  (func (type 0) (param i32) (result i64)
    i64.const 1
  )
  (type (func (param i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32) (result i64)
    i64.const 1
  )
  (type (func (param f32) (result f64)))
  (type (func (param i32) (result i64)))
--
  (func (type 1) (param i32) (result i64)
    i64.const 1
  )
  (type (func (param f32) (result f64)))
  (type (func (param i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (import "a" "b") (param i32))
  (type (func (param i32)))
--
  (import "a" "b" (func (type 0) (param i32)))
  (type (func (param i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (import "a" "b" (func (param i32)))
  (type (func (param i32)))
--
  (import "a" "b" (func (type 0) (param i32)))
  (type (func (param i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func
    (export "a")
    (export "b")
    (import "c" "d")
    (param i32)
  )
  (type (func (param i32)))
--
  (export "a" (func $__fresh_0))
  (export "b" (func $__fresh_0))
  (import "c" "d" (func $__fresh_0 (type 0) (param i32)))
  (type (func (param i32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (global $g i32
    call_indirect 0 (param i32) (result f32)
  )
  (type (func (param i32) (result f32)))
--
  (global $g i32
    call_indirect 0 (type 0) (param i32) (result f32)
  )
  (type (func (param i32) (result f32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table $t)
    (offset
      call_indirect 0 (param i32) (result f32)
    )
    funcref (item ref.func $f)
  )
  (type (func (param i32) (result f32)))
--
  (elem (table $t)
    (offset
      call_indirect 0 (type 0) (param i32) (result f32)
    )
    funcref (item ref.func $f)
  )
  (type (func (param i32) (result f32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (data (memory $m)
    (offset
      call_indirect 0 (param i32) (result f32)
    )
    "hello" "world"
  )
  (type (func (param i32) (result f32)))
--
  (data (memory $m)
    (offset
      call_indirect 0 (type 0) (param i32) (result f32)
    )
    "hello" "world"
  )
  (type (func (param i32) (result f32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block (param i32 i64)
      drop
      drop
    end
  )
  (type (func (param i32) (param i64)))
--
  (type $t (func))
  (func (type $t)
    block (type 1) (param i32) (param i64)
      drop
      drop
    end
  )
  (type (func (param i32) (param i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (type $t (func))
  (func (type $t)
    block (param i32) (result i64)
      drop
      i64.const 1
    end
  )
  (type (func (param i32) (result i64)))
--
  (type $t (func))
  (func (type $t)
    block (type 1) (param i32) (result i64)
      drop
      i64.const 1
    end
  )
  (type (func (param i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (elem (table $t) (offset i32.const 0) funcref
    (item call_indirect 0 (param i32) (result f32))
  )
  (type (func (param i32) (result f32)))
--
  (elem (table $t) (offset i32.const 0) funcref
    (item call_indirect 0 (type 0) (param i32) (result f32))
  )
  (type (func (param i32) (result f32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (table $t funcref
    (elem (item call_indirect 0 (param i32) (result f32)))
  )
  (type (func (param i32) (result f32)))
--
  (table $t 1 1 funcref)
  (elem (table $t) (offset i32.const 0) funcref
    (item call_indirect 0 (type 0) (param i32) (result f32))
  )
  (type (func (param i32) (result f32)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param $x i32) (result i64)
    i64.const 1
  )
  (type (func (param i32) (result i64)))
--
  (func (type 0) (param $x i32) (result i64)
    i64.const 1
  )
  (type (func (param i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32) (result i64)
    i64.const 1
  )
  (type (func (param $x i32) (result i64)))
--
  (func (type 0) (param i32) (result i64)
    i64.const 1
  )
  (type (func (param $x i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param $x i32) (result i64)
    i64.const 1
  )
  (type (func (param $y i32) (result i64)))
--
  (func (type 0) (param $x i32) (result i64)
    i64.const 1
  )
  (type (func (param $y i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32) (result i64)
    i64.const 1
  )
--
  (func (type 0) (param i32) (result i64)
    i64.const 1
  )
  (type (func (param i32) (result i64)))
--

assert_preprocess_module_fields <<'--', <<'--'
  (func (param i32) (result i64)
    i64.const 1
  )
  (func (param i64) (result i32)
    i32.const 2
  )
  (func (param i32) (result i64)
    i64.const 3
  )
--
  (func (type 0) (param i32) (result i64)
    i64.const 1
  )
  (func (type 1) (param i64) (result i32)
    i32.const 2
  )
  (func (type 0) (param i32) (result i64)
    i64.const 3
  )
  (type (func (param i32) (result i64)))
  (type (func (param i64) (result i32)))
--

assert_preprocess_instructions <<'--', <<'--'
  (if $label (result i32)
    (then)
    (else)
  )
--
  if $label (result i32)
  else
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (if $label (result i32)
    (then)
  )
--
  if $label (result i32)
  else
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (if $label1 (result i32)
    (if $label2 (result i32)
      (then)
      (else)
    )
    (then)
    (else)
  )
--
  if $label2 (result i32)
  else
  end
  if $label1 (result i32)
  else
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (block $label (result i32)
    i32.const 1
    i32.const 2
    i32.add
  )
--
  block $label (result i32)
    i32.const 1
    i32.const 2
    i32.add
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (loop $label (result i32)
    i32.const 1
    i32.const 2
    i32.add
  )
--
  loop $label (result i32)
    i32.const 1
    i32.const 2
    i32.add
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (block $label1 (result i64)
    (loop $label2 (result i32)
      i32.const 1
      i32.const 2
      i32.add
    )
  )
--
  block $label1 (result i64)
    loop $label2 (result i32)
      i32.const 1
      i32.const 2
      i32.add
    end
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (if $label (result i32) (i32.const 0)
    (then i32.const 1)
    (else i32.const 2)
  )
--
  i32.const 0
  if $label (result i32)
    i32.const 1
  else
    i32.const 2
  end
--

assert_preprocess_instructions <<'--', <<'--'
  (i32.mul (i32.add (local.get $x) (i32.const 2)) (i32.const 3))
--
  local.get $x
  i32.const 2
  i32.add
  i32.const 3
  i32.mul
--

assert_preprocess_instructions <<'--', <<'--'
  (select (result i32) (local.get 0) (local.get 1) (local.get 2))
--
  local.get 0
  local.get 1
  local.get 2
  select (result i32)
--

assert_preprocess_instructions <<'--', <<'--'
  call_indirect (type $t)
--
  call_indirect 0 (type $t)
--

assert_preprocess_instructions <<'--', <<'--'
  table.get
  table.set
  table.size
  table.grow
  table.fill
  table.copy
  table.init 42
--
  table.get 0
  table.set 0
  table.size 0
  table.grow 0
  table.fill 0
  table.copy 0 0
  table.init 0 42
--

assert_preprocess_instructions <<'--', <<'--'
  if i32.const 0 nop end
--
  if i32.const 0 nop else end
--

BEGIN {
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  def pretty_print(s_expression)
    case s_expression
    in [*items]
      "(#{items.map { pretty_print(_1) }.join(' ')})"
    else
      s_expression
    end
  end

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
      raise "expected #{pretty_print(expected)}, got #{pretty_print(actual)}"
    end
  end

  def assert_preprocess_module_fields(input, expected)
    assert_preprocess "(module #{input})", "(module #{expected})"
  end

  def assert_preprocess_instructions(input, expected)
    assert_preprocess_module_fields \
      "(type (func)) (func (type 0) #{input})",
      "(type (func)) (func (type 0) #{expected})"
  end
}

END {
  puts
}
