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