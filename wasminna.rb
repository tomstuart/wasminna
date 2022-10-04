require 's_expression_parser'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    Interpreter.new.interpret(s_expression)
  end
end

class Interpreter
  def interpret(script)
    script.each do |command|
      case command
      in ['module', *]
        # TODO
      in ['assert_return', *]
        # TODO
      in ['assert_malformed', *]
        # TODO
      end
    end
  end
end

main
