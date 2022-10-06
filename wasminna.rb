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
      in ['assert_malformed' | 'assert_trap' | 'assert_invalid', *]
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
        signed_result = divide(signed_left, signed_right)
        unsigned(signed_result, bits:)
      in ['div_u', left, right]
        divide(evaluate(left, locals:), evaluate(right, locals:))
      in ['rem_s', left, right]
        signed_left = signed(evaluate(left, locals:), bits:)
        signed_right = signed(evaluate(right, locals:), bits:)
        signed_result = modulo(signed_left, signed_right)
        unsigned(signed_result, bits:)
      in ['rem_u', left, right]
        modulo(evaluate(left, locals:), evaluate(right, locals:))
      in ['and', left, right]
        evaluate(left, locals:) & evaluate(right, locals:)
      in ['or', left, right]
        evaluate(left, locals:) | evaluate(right, locals:)
      in ['xor', left, right]
        evaluate(left, locals:) ^ evaluate(right, locals:)
      in ['shl', left, right]
        evaluate(left, locals:) << (evaluate(right, locals:) % bits)
      in ['shr_s', left, right]
        signed_left = signed(evaluate(left, locals:), bits:)
        signed_result = signed_left >> (evaluate(right, locals:) % bits)
        unsigned(signed_result, bits:)
      in ['shr_u', left, right]
        evaluate(left, locals:) >> (evaluate(right, locals:) % bits)
      in ['rotl', left, right]
        value = evaluate(left, locals:)
        distance = evaluate(right, locals:) % bits
        (value << distance) | (value >> (bits - distance))
      in ['rotr', left, right]
        value = evaluate(left, locals:)
        distance = evaluate(right, locals:) % bits
        (value << (bits - distance)) | (value >> distance)
      in ['clz', value]
        value = evaluate(value, locals:)
        count = 0
        (bits - 1).downto(0) do |position|
          break if value[position].nonzero?
          count += 1
        end
        count
      in ['ctz', value]
        value = evaluate(value, locals:)
        count = 0
        0.upto(bits - 1) do |position|
          break if value[position].nonzero?
          count += 1
        end
        count
      in ['popcnt', value]
        value = evaluate(value, locals:)
        count = 0
        0.upto(bits - 1) do |position|
          count += 1 if value[position].nonzero?
        end
        count
      in [%r{\Aextend(?:_i)?(?<bits>8|16|32)_s\z}, value]
        match = Regexp.last_match
        extend_bits = match[:bits].to_i
        value = evaluate(value, locals:)
        unsigned(signed(value, bits: extend_bits), bits:)
      in ['eqz', value]
        bool(evaluate(value, locals:).zero?)
      in ['eq', left, right]
        bool(evaluate(left, locals:) == evaluate(right, locals:))
      in ['ne', left, right]
        bool(evaluate(left, locals:) != evaluate(right, locals:))
      in ['lt_s', left, right]
        bool(signed(evaluate(left, locals:), bits:) < signed(evaluate(right, locals:), bits:))
      in ['lt_u', left, right]
        bool(evaluate(left, locals:) < evaluate(right, locals:))
      in ['le_s', left, right]
        bool(signed(evaluate(left, locals:), bits:) <= signed(evaluate(right, locals:), bits:))
      in ['le_u', left, right]
        bool(evaluate(left, locals:) <= evaluate(right, locals:))
      in ['gt_s', left, right]
        bool(signed(evaluate(left, locals:), bits:) > signed(evaluate(right, locals:), bits:))
      in ['gt_u', left, right]
        bool(evaluate(left, locals:) > evaluate(right, locals:))
      in ['ge_s', left, right]
        bool(signed(evaluate(left, locals:), bits:) >= signed(evaluate(right, locals:), bits:))
      in ['ge_u', left, right]
        bool(evaluate(left, locals:) >= evaluate(right, locals:))
      in ['wrap_i64', value]
        evaluate(value, locals:)
      end.then { |value| mask(value, bits:) }
    end
  end

  def divide(dividend, divisor)
    quotient = dividend / divisor

    if quotient.negative? && (dividend % divisor).nonzero?
      quotient + 1
    else
      quotient
    end
  end

  def modulo(dividend, divisor)
    dividend - (divisor * divide(dividend, divisor))
  end

  def bool(value)
    value ? 1 : 0
  end

  def signed(unsigned, bits:)
    unsigned = mask(unsigned, bits:)
    size = 1 << bits

    if unsigned < size / 2
      unsigned
    else
      unsigned - size
    end
  end

  def unsigned(signed, bits:)
    signed = mask(signed, bits:)
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
