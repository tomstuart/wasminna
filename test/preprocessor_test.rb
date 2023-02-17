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
