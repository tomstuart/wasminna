def main
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

  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    pp s_expression
  end
end

class SExpressionParser
  def parse(string)
    self.string = string
    expressions = parse_expressions terminated_by: %r{\z}
    read %r{\z}
    expressions
  end

  def parse_expressions(terminated_by:)
    expressions = []
    loop do
      skip_whitespace_and_comments
      break if can_read? terminated_by
      expressions << parse_expression
    end
    expressions
  end

  def parse_expression
    if can_read? %r{\(}
      read %r{\(}
      expressions = parse_expressions terminated_by: %r{\)}
      read %r{\)}
      expressions
    else
      parse_atom
    end
  end

  private

  def skip_whitespace_and_comments
    loop do
      if can_read? %r{[ \n]+}
        read %r{[ \n]+}
      elsif can_read? %r{;;.*$}
        read %r{;;.*$}
      else
        break
      end
    end
  end

  def parse_atom
    read %r{[^() \n;]+}
  end

  def can_read?(pattern)
    %r{\A#{pattern}}.match?(string)
  end

  def read(pattern)
    match = %r{\A#{pattern}}.match(string) or raise "couldn’t match #{pattern} in #{string.inspect}"
    self.string = match.post_match
    match.to_s
  end

  attr_accessor :string
end

main
