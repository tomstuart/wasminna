def main
  input = 'hello'
  expected = 'hello'
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
  end

  private

  attr_accessor :string
end

main
