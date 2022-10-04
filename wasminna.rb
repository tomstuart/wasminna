require 's_expression_parser'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    Interpreter.new.interpret(s_expression)
  end
end

class Interpreter
  Function = Struct.new(:name, :body, keyword_init: true)

  def interpret(script)
    functions = []

    script.each do |command|
      case command
      in ['module', *expressions]
        expressions.each do |expression|
          case expression
          in ['func', ['export', name], ['result', _], body]
            functions << Function.new(name:, body:)
          end
        end
      in ['assert_return', ['invoke', name], [%r{i(?<bits>32|64).const} => instruction, expected]]
        match = Regexp.last_match
        bits = match[:bits].to_i

        function = functions.detect { |function| function.name == name }
        raise "couldn’t find function #{name}" if function.nil?

        expected_value = interpret_integer(expected, bits:)
        actual_value = evaluate(function.body)

        if actual_value == expected_value
          puts "#{actual_value.inspect} == #{expected_value.inspect}"
        else
          raise "expected #{expected_value.inspect}, got #{actual_value.inspect}"
        end
      in ['assert_malformed', *]
        # TODO
      end
    end
  end

  private

  def evaluate(expression)
    case expression
    in ['return', return_expression]
      evaluate(return_expression)
    in [%r{i(?<bits>32|64).(?<operation>.+)}, *arguments]
      match = Regexp.last_match
      bits = match[:bits].to_i
      operation = match[:operation]

      case [operation, *arguments]
      in ['const', value]
        interpret_integer(value, bits:)
      in ['add', left, right]
        evaluate(left) + evaluate(right)
      end
    end
  end

  def interpret_integer(string, bits:)
    signed = string.start_with?('-')
    string = string.tr('-', '')

    magnitude =
      if string.start_with?('0x')
        string.to_i(16)
      else
        string.to_i(10)
      end

    value =
      if signed
        (1 << bits) - magnitude
      else
        magnitude
      end

    mask(value, bits:)
  end

  def mask(value, bits:)
    value & ((1 << bits) - 1)
  end
end

main
