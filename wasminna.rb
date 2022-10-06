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
        ['i32.const' | 'i64.const' => instruction, expected]
      ]
        bits = instruction.slice(%r{\d+}).to_i(10)

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
    in [%r{\Ai(32|64)\.} => instruction, *arguments]
      type, operation = instruction.split('.')
      bits = type.slice(%r{\d+}).to_i(10)

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
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          divide(left, right)
        end
      in ['div_u', left, right]
        divide(evaluate(left, locals:), evaluate(right, locals:))
      in ['rem_s', left, right]
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          modulo(left, right)
        end
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
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, bits:) do |left|
          left >> (right % bits)
        end
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
        0.upto(bits).take_while { |count| value[bits - count, count].zero? }.last
      in ['ctz', value]
        value = evaluate(value, locals:)
        0.upto(bits).take_while { |count| value[0, count].zero? }.last
      in ['popcnt', value]
        value = evaluate(value, locals:)
        0.upto(bits - 1).count { |position| value[position].nonzero? }
      in [%r{\Aextend(_i)?(8|16|32)_s\z}, value]
        extend_bits = operation.slice(%r{\d+}).to_i(10)
        value = evaluate(value, locals:)
        unsigned(signed(value, bits: extend_bits), bits:)
      in ['extend_i32_u', value]
        evaluate(value, locals:)
      in ['eqz', value]
        bool(evaluate(value, locals:).zero?)
      in ['eq', left, right]
        bool(evaluate(left, locals:) == evaluate(right, locals:))
      in ['ne', left, right]
        bool(evaluate(left, locals:) != evaluate(right, locals:))
      in ['lt_s', left, right]
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          bool(left < right)
        end
      in ['lt_u', left, right]
        bool(evaluate(left, locals:) < evaluate(right, locals:))
      in ['le_s', left, right]
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          bool(left <= right)
        end
      in ['le_u', left, right]
        bool(evaluate(left, locals:) <= evaluate(right, locals:))
      in ['gt_s', left, right]
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          bool(left > right)
        end
      in ['gt_u', left, right]
        bool(evaluate(left, locals:) > evaluate(right, locals:))
      in ['ge_s', left, right]
        left, right = evaluate(left, locals:), evaluate(right, locals:)
        with_signed(left, right, bits:) do |left, right|
          bool(left >= right)
        end
      in ['ge_u', left, right]
        bool(evaluate(left, locals:) >= evaluate(right, locals:))
      in ['wrap_i64', value]
        evaluate(value, locals:)
      end.then { |value| mask(value, bits:) }
    end
  end

  def with_signed(*unsigned_args, bits:)
    signed_args = unsigned_args.map { |arg| signed(arg, bits:) }
    signed_result = yield *signed_args
    unsigned(signed_result, bits:)
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
