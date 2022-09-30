def main
  input = 'hello'
  expected = 'hello'
  actual = SExpressionParser.new.parse(input)
  raise actual.inspect unless actual == expected

  input = '(hello)'
  expected = ['hello']
  actual = SExpressionParser.new.parse(input)
  raise actual.inspect unless actual == expected

  input = '(hello world)'
  expected = ['hello', 'world']
  actual = SExpressionParser.new.parse(input)
  raise actual.inspect unless actual == expected

  input = '((hello goodbye) world)'
  expected = [['hello', 'goodbye'], 'world']
  actual = SExpressionParser.new.parse(input)
  raise actual.inspect unless actual == expected

  input = "(module\n  (func (nop))\n)"
  expected = ['module', ['func', ['nop']]]
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
    expression = parse_expression
    read %r{\z}
    expression
  end

  def parse_expression
    if can_read? %r{\(}
      expressions = []
      read %r{\(}
      loop do
        skip_whitespace
        break if can_read? %r{\)}
        expressions << parse_expression
      end
      read %r{\)}
      expressions
    else
      parse_atom
    end
  end

  private

  def skip_whitespace
    if can_read? %r{[ \n]+}
      read %r{[ \n]+}
    end
  end

  def parse_atom
    read %r{[^) \n]+}
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
