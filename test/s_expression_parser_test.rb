input = 'hello'
expected = ['hello']
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello)'
expected = [['hello']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello world)'
expected = [['hello', 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '((hello goodbye) world)'
expected = [[['hello', 'goodbye'], 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = "(module\n  (func (nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = "(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = "(module\n  (func (nop)nop)\n)"
expected = [['module', ['func', ['nop'], 'nop']]]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(module) (module)'
expected = [['module'], ['module']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = ";; Tokens can be delimited by parentheses\n\n(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = "(module\n  (func;;bla\n  )\n)"
expected = [['module', ['func']]]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '"(hello world) ;; comment"'
expected = ['"(hello world) ;; comment"']
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '"hello \" world"'
expected = ['"hello \" world"']
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello (; cruel ;) world)'
expected = [['hello', 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello (; this; is; ( totally; ); fine ;) world)'
expected = [['hello', 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello (; cruel (; very cruel ;) extremely cruel ;) world)'
expected = [['hello', 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

input = '(hello (; cruel ;) happy (; terrible ;) world)'
expected = [['hello', 'happy', 'world']]
actual = Wasminna::SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise "expected #{expected}, got #{actual}"
end

BEGIN {
  require 'wasminna/s_expression_parser'
}

END {
  puts
}
