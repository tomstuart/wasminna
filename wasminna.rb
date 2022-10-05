require 's_expression_parser'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    Interpreter.new.interpret(s_expression)
  end
end

class Interpreter
  Parameter = Struct.new(:name, keyword_init: true)
  Function = Struct.new(:name, :parameters, :body, keyword_init: true)

  def interpret(script)
    functions = []

    script.each do |command|
      case command
      in ['module', *expressions]
        expressions.each do |expression|
          case expression
          in ['func', ['export', name], *parameters, ['result', _], body]
            parameters =
              parameters.map do |parameter; name|
                parameter => ['param', name, _]
                Parameter.new(name:)
              end
            functions << Function.new(name:, parameters:, body:)
          end
        end
      in [
        'assert_return',
        ['invoke', name, *arguments],
        [%r{\Ai(?<bits>32|64)\.const\z} => instruction, expected]
      ]
        match = Regexp.last_match
        bits = match[:bits].to_i

        function = functions.detect { |function| function.name == name }
        raise "couldn’t find function #{name}" if function.nil?

        expected_value = interpret_integer(expected, bits:)

        parameter_names = function.parameters.map(&:name)
        argument_values =
          arguments.map { |argument| evaluate(argument, locals: {}) }
        locals = parameter_names.zip(argument_values).to_h
        actual_value = evaluate(function.body, locals:)

        if actual_value == expected_value
          puts "#{actual_value.inspect} == #{expected_value.inspect}"
        else
          raise "expected #{expected_value.inspect}, got #{actual_value.inspect}"
        end
      in ['assert_malformed' | 'assert_trap', *]
        # TODO
      end
    end
  end

  private

  def evaluate(expression, locals:)
    case expression
    in ['return', return_expression]
      evaluate(return_expression, locals:)
    in ['local.get', name]
      locals.fetch(name)
    in [%r{\Ai(?<bits>32|64)\.(?<operation>.+)\z}, *arguments]
      match = Regexp.last_match
      bits = match[:bits].to_i
      operation = match[:operation]

      case [operation, *arguments]
      in ['const', value]
        interpret_integer(value, bits:)
      in ['add', left, right]
        evaluate(left, locals:) + evaluate(right, locals:)
      in ['sub', left, right]
        evaluate(left, locals:) - evaluate(right, locals:)
      in ['mul', left, right]
        evaluate(left, locals:) * evaluate(right, locals:)
      in ['div_s', left, right]
        signed_left = signed(evaluate(left, locals:), bits:)
        signed_right = signed(evaluate(right, locals:), bits:)
        signed_result = signed_left / signed_right
        unsigned(signed_result, bits:)
      end.then { |value| mask(value, bits:) }
    end
  end

  def signed(unsigned, bits:)
    size = 1 << bits

    if unsigned < size / 2
      unsigned
    else
      unsigned - size
    end
  end

  def unsigned(signed, bits:)
    size = 1 << bits

    if signed.negative?
      signed + size
    else
      signed
    end
  end

  def interpret_integer(string, bits:)
    negated = string.start_with?('-')
    string = string.tr('-', '')

    magnitude =
      if string.start_with?('0x')
        string.to_i(16)
      else
        string.to_i(10)
      end

    if negated
      (1 << bits) - magnitude
    else
      magnitude
    end
  end

  def mask(value, bits:)
    size = 1 << bits
    value & (size - 1)
  end
end

main
