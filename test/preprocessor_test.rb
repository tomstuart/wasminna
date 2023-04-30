require 'wasminna/preprocessor'

input = [['module', ['func', %w[import "spectest" "print_i32"], %w[param i32]]]]
expected = [['module', [*%w[import "spectest" "print_i32"], ['func', %w[param i32]]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [['module', '$mymodule', ['func', %w[import "spectest" "print_i32"], %w[param i32]]]]
expected = [['module', '$mymodule', [*%w[import "spectest" "print_i32"], ['func', %w[param i32]]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [['module', ['func', '$myfunction', %w[import "spectest" "print_i32"], %w[param i32]]]]
expected = [['module', [*%w[import "spectest" "print_i32"], ['func', '$myfunction', %w[param i32]]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [['module', ['table', %w[import "spectest" "table"], *%w[0 funcref]]]]
expected = [['module', [*%w[import "spectest" "table"], ['table', *%w[0 funcref]]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [['module', ['memory', %w[import "spectest" "memory"], *%w[1 2]]]]
expected = [['module', [*%w[import "spectest" "memory"], ['memory', *%w[1 2]]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [['module', ['global', %w[import "spectest" "global_i32"], 'i32']]]
expected = [['module', [*%w[import "spectest" "global_i32"], %w[global i32]]]]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
    ['func', %w[export "i32.test"], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
expected = [
  ['module',
    [*%w[export "i32.test"], %w[func $__fresh_0]],
    [*%w[func $__fresh_0], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
    ['func', %w[export "i32.test"], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]],
    ['func', %w[export "i32.umax"], %w[result i32], ['return', %w[i32.const 0xffffffff]]]
  ]
]
expected = [
  ['module',
    [*%w[export "i32.test"], %w[func $__fresh_0]],
    [*%w[func $__fresh_0], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]],
    [*%w[export "i32.umax"], %w[func $__fresh_1]],
    [*%w[func $__fresh_1], %w[result i32], ['return', %w[i32.const 0xffffffff]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
   ['func', %w[export "i32.test1"], %w[export "i32.test2"], %w[export "i32.test3"], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
expected = [
  ['module',
    [*%w[export "i32.test1"], %w[func $__fresh_0]],
    [*%w[export "i32.test2"], %w[func $__fresh_0]],
    [*%w[export "i32.test3"], %w[func $__fresh_0]],
    [*%w[func $__fresh_0], %w[result i32], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
   ['func', %w[export "i32.test1"], %w[export "i32.test2"], %w[export "i32.test3"], %w[import "mymodule" "bad_dude"], %w[result i32]]
  ]
]
expected = [
  ['module',
    [*%w[export "i32.test1"], %w[func $__fresh_0]],
    [*%w[export "i32.test2"], %w[func $__fresh_0]],
    [*%w[export "i32.test3"], %w[func $__fresh_0]],
    [*%w[import "mymodule" "bad_dude"], [*%w[func $__fresh_0], %w[result i32]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
    ['table', %w[export "a"], *%w[0 1 funcref]]
  ]
]
expected = [
  ['module',
    [*%w[export "a"], %w[table $__fresh_0]],
    %w[table $__fresh_0 0 1 funcref]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  %w[func],
  %w[memory 0],
  ['func', %w[export "f"]]
]
expected = [
  ['module',
    %w[func],
    %w[memory 0],
    [*%w[export "f"], %w[func $__fresh_0]],
    %w[func $__fresh_0]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  %w[func],
  %w[memory 0],
  ['func', %w[export "f"]],
  %w[invoke "f"]
]
expected = [
  ['module',
    %w[func],
    %w[memory 0],
    [*%w[export "f"], %w[func $__fresh_0]],
    %w[func $__fresh_0]
  ],
  %w[invoke "f"]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
    ['func', %w[result i32], %w[local i32 f64 funcref], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
expected = [
  ['module',
    ['func', %w[result i32], %w[local i32], %w[local f64], %w[local funcref], ['return', %w[i32.const 0x0bAdD00D]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
   ['func', %w[param i32 i64], %w[result i64 i32], %w[i64.const 1], %w[i32.const 2]]
  ]
]
expected = [
  ['module',
   ['func', %w[param i32], %w[param i64], %w[result i64], %w[result i32], %w[i64.const 1], %w[i32.const 2]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = [
  ['module',
    ['type', ['func', %w[param i32 i64], %w[result f32 f64]]]
  ]
]
expected = [
  ['module',
    ['type', ['func', %w[param i32], %w[param i64], %w[result f32], %w[result f64]]]
  ]
]
actual = Wasminna::Preprocessor.new.process_script(input)
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

puts
