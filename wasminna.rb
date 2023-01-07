require 'ast_parser'
require 'interpreter'
require 's_expression_parser'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    script = ASTParser.new.parse_script(s_expression)
    Interpreter.new.evaluate_script(script)
    puts
  end
end

main
