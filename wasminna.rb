require 'bigdecimal'
require 'float'
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

        parameter_names = function.parameters.map(&:name)
        argument_values =
          arguments.map { |argument| evaluate(argument, locals: {}) }
        locals = parameter_names.zip(argument_values).to_h
        begin
          actual_value = evaluate(function.body, locals:)
        rescue
          raise "failure during #{command}"
        end

        case expected
        in ['f32.const' | 'f64.const' => instruction, 'nan:canonical' | 'nan:arithmetic' => nan]
          expected_value = nan
          bits = instruction.slice(%r{\d+}).to_i(10)
          format = Wasminna::Float::Format.for(bits:)
          float = Wasminna::Float.decode(actual_value, format:).to_f
          success = float.nan? # TODO check whether canonical or arithmetic
        else
          begin
            expected_value = evaluate(expected, locals: {})
          rescue
            raise "failure during #{command}"
          end

          success = actual_value == expected_value
        end

        if success
          puts "#{name.tr('"', '')}: #{actual_value.inspect} == #{expected_value.inspect}"
        else
          raise "failure during #{command}: expected #{expected_value.inspect}, got #{actual_value.inspect}"
        end
      in ['assert_malformed' | 'assert_trap' | 'assert_invalid', *]
        # TODO
      end
    end
  end

  private

  module FloatSign
    refine ::Float do
      def sign = angle.zero? ? 1 : -1
    end
  end

  using FloatSign

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
      format = Wasminna::Float::Format.for(bits:)
      Wasminna::Float.parse(value).encode(format:)
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
      in ['extend8_s' | 'extend16_s' | 'extend32_s' | 'extend_i32_s', value]
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
      in ['trunc_f32_s', value]
        format = Wasminna::Float::Format.for(bits: 32)
        float = Wasminna::Float.decode(value, format:).to_f
        unsigned(float.truncate, bits:)
      in ['trunc_sat_f32_s', value]
        format = Wasminna::Float::Format.for(bits: 32)
        result = Wasminna::Float.decode(value, format:).to_f
        result =
          if result.nan?
            0
          elsif result.infinite?
            result
          else
            result.truncate
          end

        size = 1 << bits
        min, max = -(size / 2), (size / 2) - 1
        result = result.clamp(min, max)

        unsigned(result, bits:)
      in ['trunc_f64_s', value]
        format = Wasminna::Float::Format.for(bits: 64)
        float = Wasminna::Float.decode(value, format:).to_f
        unsigned(float.truncate, bits:)
      in ['trunc_sat_f64_s', value]
        format = Wasminna::Float::Format.for(bits: 64)
        result = Wasminna::Float.decode(value, format:).to_f
        result =
          if result.nan?
            0
          elsif result.infinite?
            result
          else
            result.truncate
          end

        size = 1 << bits
        min, max = -(size / 2), (size / 2) - 1
        result = result.clamp(min, max)

        unsigned(result, bits:)
      in ['trunc_f32_u', value]
        format = Wasminna::Float::Format.for(bits: 32)
        Wasminna::Float.decode(value, format:).to_f.truncate
      in ['trunc_sat_f32_u', value]
        format = Wasminna::Float::Format.for(bits: 32)
        result = Wasminna::Float.decode(value, format:).to_f
        result =
          if result.nan?
            0
          elsif result.infinite?
            result
          else
            result.truncate
          end

        size = 1 << bits
        min, max = 0, size - 1
        result = result.clamp(min, max)

        result
      in ['trunc_f64_u', value]
        format = Wasminna::Float::Format.for(bits: 64)
        Wasminna::Float.decode(value, format:).to_f.truncate
      in ['trunc_sat_f64_u', value]
        format = Wasminna::Float::Format.for(bits: 64)
        result = Wasminna::Float.decode(value, format:).to_f
        result =
          if result.nan?
            0
          elsif result.infinite?
            result
          else
            result.truncate
          end

        size = 1 << bits
        min, max = 0, size - 1
        result = result.clamp(min, max)

        result
      end.then { |value| mask(value, bits:) }
    in [%r{\Af(32|64)\.} => instruction, *arguments]
      type, operation = instruction.split('.')
      bits = type.slice(%r{\d+}).to_i(10)
      format = Wasminna::Float::Format.for(bits:)
      arguments = arguments.map { |arg| evaluate(arg, locals:) }

      case [operation, *arguments]
      in ['add' | 'sub' | 'mul' | 'div' | 'min' | 'max' | 'sqrt' | 'floor' | 'ceil' | 'trunc' | 'nearest', *]
        with_float(*arguments, format:) do |*arguments|
          case [operation, *arguments]
          in ['add', left, right]
            left + right
          in ['sub', left, right]
            left - right
          in ['mul', left, right]
            left * right
          in ['div', left, right]
            left / right
          in ['min', _, _]
            if arguments.any?(&:nan?)
              ::Float::NAN
            elsif arguments.all?(&:zero?)
              arguments.min_by(&:sign)
            else
              arguments.min
            end
          in ['max', _, _]
            if arguments.any?(&:nan?)
              ::Float::NAN
            elsif arguments.all?(&:zero?)
              arguments.max_by(&:sign)
            else
              arguments.max
            end
          in ['sqrt', value]
            if value.zero?
              value
            elsif value.negative?
              ::Float::NAN
            else
              Math.sqrt(value)
            end
          in ['floor' | 'ceil' | 'trunc' | 'nearest', value]
            if value.zero? || value.infinite? || value.nan?
              value
            else
              case operation
              in 'floor'
                value.floor
              in 'ceil'
                value.ceil
              in 'trunc'
                value.truncate
              in 'nearest'
                value.round(half: :even)
              end.then do |result|
                if result.zero? && value.negative?
                  -0.0
                else
                  result
                end
              end
            end
          end
        end
      in ['convert_i32_s' | 'convert_i64_s', value]
        integer_bits = operation.slice(%r{\d+}).to_i(10)
        integer = signed(value, bits: integer_bits)
        Wasminna::Float.from_integer(integer).encode(format:)
      in ['convert_i32_u' | 'convert_i64_u', value]
        Wasminna::Float.from_integer(value).encode(format:)
      in ['promote_f32', value]
        raise unless bits == 64
        input_format = Wasminna::Float::Format.for(bits: 32)
        Wasminna::Float.decode(value, format: input_format).encode(format:)
      in ['demote_f64', value]
        raise unless bits == 32
        input_format = Wasminna::Float::Format.for(bits: 64)
        Wasminna::Float.decode(value, format: input_format).encode(format:)
      in ['reinterpret_i32' | 'reinterpret_i64', value]
        integer_bits = operation.slice(%r{\d+}).to_i(10)
        raise unless bits == integer_bits
        value
      end
    end
  end

  def with_signed(*unsigned_args, bits:)
    signed_args = unsigned_args.map { |arg| signed(arg, bits:) }
    signed_result = yield *signed_args
    unsigned(signed_result, bits:)
  end

  def with_float(*integer_args, format:)
    float_args = integer_args.map { |arg| Wasminna::Float.decode(arg, format:).to_f }
    float_result = yield *float_args
    Wasminna::Float.from_float(float_result).encode(format:)
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

  def mask(value, bits:)
    size = 1 << bits
    value & (size - 1)
  end
end

main
