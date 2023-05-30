input = parse <<'--'
  (module
    (func (import "spectest" "print_i32") (param i32))
  )
--
expected = parse <<'--'
  (module
    (import "spectest" "print_i32" (func (param i32)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module $mymodule
    (func (import "spectest" "print_i32") (param i32))
  )
--
expected = parse <<'--'
  (module $mymodule
    (import "spectest" "print_i32" (func (param i32)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func $myfunction (import "spectest" "print_i32") (param i32))
  )
--
expected = parse <<'--'
  (module
    (import "spectest" "print_i32" (func $myfunction (param i32)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (table (import "spectest" "table") 0 funcref)
  )
--
expected = parse <<'--'
  (module
    (import "spectest" "table" (table 0 funcref))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (memory (import "spectest" "memory") 1 2)
  )
--
expected = parse <<'--'
  (module
    (import "spectest" "memory" (memory 1 2))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (global (import "spectest" "global_i32") i32)
  )
--
expected = parse <<'--'
  (module
    (import "spectest" "global_i32" (global i32))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
  )
--
expected = parse <<'--'
  (module
    (export "i32.test" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func (export "i32.test") (result i32) (return (i32.const 0x0bAdD00D)))
    (func (export "i32.umax") (result i32) (return (i32.const 0xffffffff)))
  )
--
expected = parse <<'--'
  (module
    (export "i32.test" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
    (export "i32.umax" (func $__fresh_1))
    (func $__fresh_1 (result i32) (return (i32.const 0xffffffff)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
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
expected = parse <<'--'
  (module
    (export "i32.test1" (func $__fresh_0))
    (export "i32.test2" (func $__fresh_0))
    (export "i32.test3" (func $__fresh_0))
    (func $__fresh_0 (result i32) (return (i32.const 0x0bAdD00D)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
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
expected = parse <<'--'
  (module
    (export "i32.test1" (func $__fresh_0))
    (export "i32.test2" (func $__fresh_0))
    (export "i32.test3" (func $__fresh_0))
    (import "mymodule" "bad_dude" (func $__fresh_0 (result i32)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (table (export "a") 0 1 funcref)
  )
--
expected = parse <<'--'
  (module
    (export "a" (table $__fresh_0))
    (table $__fresh_0 0 1 funcref)
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (func)
  (memory 0)
  (func (export "f"))
--
expected = parse <<'--'
  (module
    (func)
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0)
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (func)
  (memory 0)
  (func (export "f"))
  (invoke "f")
--
expected = parse <<'--'
  (module
    (func)
    (memory 0)
    (export "f" (func $__fresh_0))
    (func $__fresh_0)
  )
  (invoke "f")
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func (result i32) (local i32 f64 funcref)
      (return (i32.const 0x0bAdD00D))
    )
  )
--
expected = parse <<'--'
  (module
    (func (result i32) (local i32) (local f64) (local funcref)
      (return (i32.const 0x0bAdD00D))
    )
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func (param i32 i64) (result i64 i32)
      (i64.const 1)
      (i32.const 2)
    )
  )
--
expected = parse <<'--'
  (module
    (func (param i32) (param i64) (result i64) (result i32)
      (i64.const 1)
      (i32.const 2)
    )
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (type (func (param i32 i64) (result f32 f64)))
  )
--
expected = parse <<'--'
  (module
    (type (func (param i32) (param i64) (result f32) (result f64)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (import a b (func (param i32 i64) (result f32 f64)))
  )
--
expected = parse <<'--'
  (module
    (import a b (func (param i32) (param i64) (result f32) (result f64)))
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func
      (block (param i32 i32) (result i32 i32)
        (i32 add)
        (i32.const 1)
      )
    )
  )
--
expected = parse <<'--'
  (module
    (func
      (block (param i32) (param i32) (result i32) (result i32)
        (i32 add)
        (i32.const 1)
      )
    )
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module
    (func
      (call_indirect
        (param i64) (param) (param f64 i32 i64)
        (result f32 f64) (result i32)
      )
    )
  )
--
expected = parse <<'--'
  (module
    (func
      (call_indirect
        (param i64) (param f64) (param i32) (param i64)
        (result f32) (result f64) (result i32)
      )
    )
  )
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = parse <<'--'
  (module $M2 binary "\00asm" "\01\00\00\00")
--
expected = parse <<'--'
  (module $M2 binary "\00asm" "\01\00\00\00")
--
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

BEGIN {
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  def parse(string)
    Wasminna::SExpressionParser.new.parse(string)
  end
}

END {
  puts
}
