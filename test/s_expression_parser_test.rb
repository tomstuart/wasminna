require 'wasminna/s_expression_parser'

input = 'hello'
expected = ['hello']
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello)'
expected = [['hello']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello world)'
expected = [['hello', 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '((hello goodbye) world)'
expected = [[['hello', 'goodbye'], 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = "(module\n  (func (nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = "(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = "(module\n  (func (nop)nop)\n)"
expected = [['module', ['func', ['nop'], 'nop']]]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(module) (module)'
expected = [['module'], ['module']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = ";; Tokens can be delimited by parentheses\n\n(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = "(module\n  (func;;bla\n  )\n)"
expected = [['module', ['func']]]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '"(hello world) ;; comment"'
expected = ['"(hello world) ;; comment"']
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '"hello \" world"'
expected = ['"hello \" world"']
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello (; cruel ;) world)'
expected = [['hello', 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello (; this; is; ( totally; ); fine ;) world)'
expected = [['hello', 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello (; cruel (; very cruel ;) extremely cruel ;) world)'
expected = [['hello', 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

input = '(hello (; cruel ;) happy (; terrible ;) world)'
expected = [['hello', 'happy', 'world']]
actual = SExpressionParser.new.parse(input).entries
if actual == expected
  print "\e[32m.\e[0m"
else
  raise actual.inspect unless actual == expected
end

puts
