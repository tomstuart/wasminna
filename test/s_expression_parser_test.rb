assert_parse 'hello', ['hello']
assert_parse '(hello)', [['hello']]
assert_parse '(hello world)', [['hello', 'world']]
assert_parse '((hello goodbye) world)', [[['hello', 'goodbye'], 'world']]
assert_parse "(module\n  (func (nop))\n)", [['module', ['func', ['nop']]]]
assert_parse "(module\n  (func(nop))\n)", [['module', ['func', ['nop']]]]
assert_parse "(module\n  (func (nop)nop)\n)", [['module', ['func', ['nop'], 'nop']]]
assert_parse '(module) (module)', [['module'], ['module']]
assert_parse ";; Tokens can be delimited by parentheses\n\n(module\n  (func(nop))\n)", [['module', ['func', ['nop']]]]
assert_parse "(module\n  (func;;bla\n  )\n)", [['module', ['func']]]
assert_parse '"(hello world) ;; comment"', ['"(hello world) ;; comment"']
assert_parse '"hello \" world"', ['"hello \" world"']
assert_parse '(hello (; cruel ;) world)', [['hello', 'world']]
assert_parse '(hello (; this; is; ( totally; ); fine ;) world)', [['hello', 'world']]
assert_parse '(hello (; cruel (; very cruel ;) extremely cruel ;) world)', [['hello', 'world']]
assert_parse '(hello (; cruel ;) happy (; terrible ;) world)', [['hello', 'happy', 'world']]

BEGIN {
  require 'wasminna/s_expression_parser'

  def assert_parse(input, expected)
    actual = Wasminna::SExpressionParser.new.parse(input)
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
