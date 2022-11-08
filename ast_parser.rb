class ASTParser
  def parse(s_expression)
    parse_expression(s_expression.flat_map { unfold(_1) })
  end

  private

  def unfold(s_expression)
    [s_expression]
  end

  def parse_expression(s_expression)
    s_expression
  end
end
