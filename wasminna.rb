require 'bigdecimal'
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
      in ['module', 'binary', *]
        # TODO
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
      in ['assert_return', ['invoke', name, *arguments], expected]
        function = functions.detect { |function| function.name == name }
        if function.nil?
          warn "couldn’t find function #{name} (could be binary?), skipping"
          next
        end

        expected_value = evaluate(expected, locals: {})

        parameter_names = function.parameters.map(&:name)
        argument_values =
          arguments.map { |argument| evaluate(argument, locals: {}) }
        locals = parameter_names.zip(argument_values).to_h
        actual_value = evaluate(function.body, locals:)

        if actual_value == expected_value
          puts "#{name.tr('"', '')}: #{actual_value.inspect} == #{expected_value.inspect}"
        else
          raise "#{name.tr('"', '')}: expected #{expected_value.inspect}, got #{actual_value.inspect}"
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
    in ['i32.const' | 'i64.const' => instruction, value]
      bits = instruction.slice(%r{\d+}).to_i(10)
      interpret_integer(value, bits:)
    in ['f32.const' | 'f64.const' => instruction, value]
      bits = instruction.slice(%r{\d+}).to_i(10)
      interpret_float(value, bits:)
    in [%r{\Ai(32|64)\.} => instruction, *arguments]
      type, operation = instruction.split('.')
      bits = type.slice(%r{\d+}).to_i(10)
      arguments = arguments.map { |arg| evaluate(arg, locals:) }

      case [operation, *arguments]
      in ['add', left, right]
        left + right
      in ['sub', left, right]
        left - right
      in ['mul', left, right]
        left * right
      in ['div_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          divide(left, right)
        end
      in ['div_u', left, right]
        divide(left, right)
      in ['rem_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          modulo(left, right)
        end
      in ['rem_u', left, right]
        modulo(left, right)
      in ['and', left, right]
        left & right
      in ['or', left, right]
        left | right
      in ['xor', left, right]
        left ^ right
      in ['shl', left, right]
        right %= bits
        left << right
      in ['shr_s', left, right]
        right %= bits
        with_signed(left, bits:) do |left|
          left >> right
        end
      in ['shr_u', left, right]
        right %= bits
        left >> right
      in ['rotl', left, right]
        right %= bits
        (left << right) | (left >> (bits - right))
      in ['rotr', left, right]
        right %= bits
        (left << (bits - right)) | (left >> right)
      in ['clz', value]
        0.upto(bits).take_while { |count| value[bits - count, count].zero? }.last
      in ['ctz', value]
        0.upto(bits).take_while { |count| value[0, count].zero? }.last
      in ['popcnt', value]
        0.upto(bits - 1).count { |position| value[position].nonzero? }
      in [%r{\Aextend(_i)?(8|16|32)_s\z}, value]
        extend_bits = operation.slice(%r{\d+}).to_i(10)
        unsigned(signed(value, bits: extend_bits), bits:)
      in ['extend_i32_u', value]
        value
      in ['eqz', value]
        bool(value.zero?)
      in ['eq', left, right]
        bool(left == right)
      in ['ne', left, right]
        bool(left != right)
      in ['lt_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          bool(left < right)
        end
      in ['lt_u', left, right]
        bool(left < right)
      in ['le_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          bool(left <= right)
        end
      in ['le_u', left, right]
        bool(left <= right)
      in ['gt_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          bool(left > right)
        end
      in ['gt_u', left, right]
        bool(left > right)
      in ['ge_s', left, right]
        with_signed(left, right, bits:) do |left, right|
          bool(left >= right)
        end
      in ['ge_u', left, right]
        bool(left >= right)
      in ['wrap_i64', value]
        value
      in ['reinterpret_f32' | 'reinterpret_f64', value]
        float_bits = operation.slice(%r{\d+}).to_i(10)
        raise unless bits == float_bits
        value
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
    value =
      if string.delete_prefix('-').start_with?('0x')
        string.to_i(16)
      else
        string.to_i(10)
      end

    unsigned(value, bits:)
  end

  NAN_REGEXP =
    %r{
      \A
      nan
      (
        :0x
        (?<payload>
          [[:xdigit:]]+
        )
      )?
      \z
    }x
  HEXFLOAT_REGEXP =
    %r{
      \A
      0x
      (?<p>
        [[:xdigit:]]+
      )
      (
        \.
        (?<q>
          [[:xdigit:]]*
        )
      )?
      (
        [Pp]
        (?<e>
          [+-]?
          [[:digit:]]+
        )
      )?
      \z
    }x
  FLOAT_REGEXP =
    %r{
      \A
      (?<p>
        [[:digit:]]+
      )
      (
        \.
        (?<q>
          [[:digit:]]*
        )
      )?
      (
        [Ee]
        (?<e>
          [+-]?
          [[:digit:]]+
        )
      )?
      \z
    }x

  def interpret_float(string, bits:)
    pack_format, unpack_format, exponent_bits =
      case bits
      in 32
        ['F', 'L', 8]
      in 64
        ['D', 'Q', 11]
      else
        raise "unsupported float width: #{bits}"
      end

    negated = string.start_with?('-')
    string = string.delete_prefix('+').delete_prefix('-').tr('_', '')

    value =
      if match = NAN_REGEXP.match(string)
        nan = [Float::NAN].pack(pack_format).unpack1(unpack_format)

        unless match[:payload].nil?
          payload = match[:payload].to_i(16)
          mask_bits = exponent_bits + 1
          top_mask = ((1 << mask_bits) - 1) << (bits - mask_bits)
          nan = (nan & top_mask) | payload
        end

        nan
      elsif string == 'inf'
        [Float::INFINITY].pack(pack_format).unpack1(unpack_format)
      elsif match = HEXFLOAT_REGEXP.match(string)
        p, q, e = match.values_at(:p, :q, :e).map(&:to_s)
        value =
          (p.to_i(16) + (q.to_i(16) * (BigDecimal(16) ** -q.length))) * (BigDecimal(2) ** e.to_i(10))

        [value].pack(pack_format).unpack1(unpack_format)
      elsif match = FLOAT_REGEXP.match(string)
        p, q, e = match.values_at(:p, :q, :e).map(&:to_s)
        value =
          (p.to_i(10) + (q.to_i(10) * (BigDecimal(10) ** -q.length))) * (BigDecimal(10) ** e.to_i(10))

        [value].pack(pack_format).unpack1(unpack_format)
      else
        raise "can’t parse float: #{string.inspect}"
      end

    if negated
      value |= 1 << (bits - 1)
    end

    value
  end

  def mask(value, bits:)
    size = 1 << bits
    value & (size - 1)
  end
end

main
