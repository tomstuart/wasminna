require 's_expression_parser'

input = 'hello'
expected = ['hello']
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '(hello)'
expected = [['hello']]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '(hello world)'
expected = [['hello', 'world']]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '((hello goodbye) world)'
expected = [[['hello', 'goodbye'], 'world']]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = "(module\n  (func (nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = "(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = "(module\n  (func (nop)nop)\n)"
expected = [['module', ['func', ['nop'], 'nop']]]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '(module) (module)'
expected = [['module'], ['module']]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = ";; Tokens can be delimited by parentheses\n\n(module\n  (func(nop))\n)"
expected = [['module', ['func', ['nop']]]]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = "(module\n  (func;;bla\n  )\n)"
expected = [['module', ['func']]]
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '"(hello world) ;; comment"'
expected = ['"(hello world) ;; comment"']
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

input = '"hello \" world"'
expected = ['"hello \" world"']
actual = SExpressionParser.new.parse(input)
raise actual.inspect unless actual == expected

