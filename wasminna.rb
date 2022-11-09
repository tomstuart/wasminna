require 'ast'
require 'ast_parser'
require 'float'
require 'helpers'
require 's_expression_parser'
require 'sign'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    Interpreter.new.interpret_script(s_expression)
    puts
  end
end

class Interpreter
  include AST
  include Helpers::Mask

  Parameter = Struct.new(:name, keyword_init: true)
  Local = Struct.new(:name, keyword_init: true)
  Function = Struct.new(:name, :parameters, :locals, :body, keyword_init: true)

  class Memory < Struct.new(:bytes, keyword_init: true)
    include Helpers::Mask
    include Helpers::SizeOf
    extend Helpers::SizeOf

    BITS_PER_BYTE = 8
    BYTES_PER_PAGE = 0xffff

    def self.from_string(string:)
      size_in_pages = size_of(string.bytesize, in: BYTES_PER_PAGE)
      bytes = "\0" * (size_in_pages * BYTES_PER_PAGE)
      bytes[0, string.length] = string
      new(bytes:)
    end

    def self.from_limits(minimum_size:, maximum_size:)
      bytes = "\0" * (minimum_size * BYTES_PER_PAGE)
      new(bytes:)
    end

    def load(offset:, bits:)
      size_of(bits, in: BITS_PER_BYTE).times
        .map { |index| bytes.getbyte(offset + index) }
        .map.with_index { |byte, index| byte << index * BITS_PER_BYTE }
        .inject(0, &:|)
    end

    def store(value:, offset:, bits:)
      size_of(bits, in: BITS_PER_BYTE).times do |index|
        byte = mask(value >> index * BITS_PER_BYTE, bits: BITS_PER_BYTE)
        bytes.setbyte(offset + index, byte)
      end
    end
  end

  attr_accessor :stack

  def interpret_script(script)
    functions = nil
    @memory = nil
    self.stack = []

    script.each do |command|
      begin
        case command
        in ['module', 'binary', *]
          # TODO
        in ['module', *expressions]
          functions = []

          expressions.each do |expression|
            case expression
            in ['func', *expressions]
              functions << define_function(expressions:)
            in ['memory', ['data', *strings]]
              @memory = Memory.from_string(string: strings.map { parse_string(_1) }.join)
            in ['memory', minimum_size, maximum_size]
              minimum_size, maximum_size =
                [minimum_size, maximum_size].map { interpret_integer(_1, bits: 32) }
              @memory = Memory.from_limits(minimum_size:, maximum_size:)
            in ['memory', minimum_size]
              minimum_size = interpret_integer(minimum_size, bits: 32)
              @memory = Memory.from_limits(minimum_size:, maximum_size: nil)
            in ['type' | 'table' | 'global', *]
              # TODO
            end
          end
        in ['invoke', name, *arguments]
          function = functions.detect { |function| function.name == name }
          if function.nil?
            puts
            puts "\e[33mWARNING: couldn’t find function #{name} (could be binary?), skipping\e[0m"
            next
          end

          invoke_function(function:, arguments:)
        in ['assert_return', ['invoke', name, *arguments], *expected]
          function = functions.detect { |function| function.name == name }
          if function.nil?
            puts
            puts "\e[33mWARNING: couldn’t find function #{name} (could be binary?), skipping\e[0m"
            next
          end

          invoke_function(function:, arguments:)
          actual_value = stack.pop
          raise unless stack.empty?

          case expected.first
          in nil
            success = true
          in ['f32.const' | 'f64.const' => instruction, 'nan:canonical' | 'nan:arithmetic' => nan]
            expected_value = nan
            bits = instruction.slice(%r{\d+}).to_i(10)
            format = Wasminna::Float::Format.for(bits:)
            float = Wasminna::Float.decode(actual_value, format:).to_f
            success = float.nan? # TODO check whether canonical or arithmetic
          else
            evaluate(ASTParser.new.parse(expected.first), locals: [])
            stack.pop(1) => [expected_value]
            raise unless stack.empty?
            success = actual_value == expected_value
          end

          if success
            print "\e[32m.\e[0m"
          else
            puts
            puts "\e[31mFAILED\e[0m: \e[33m#{pretty_print(command)}\e[0m"
            puts "expected #{expected_value.inspect}, got #{actual_value.inspect}"
            exit 1
          end
        in ['assert_malformed' | 'assert_trap' | 'assert_invalid', *]
          # TODO
          print "\e[33m.\e[0m"
        end
      rescue
        puts
        puts "\e[31mERROR\e[0m: \e[33m#{pretty_print(command)}\e[0m"
        raise
      end
    end
  end

  private

  using Sign::Conversion

  def define_function(expressions:)
    Function.new(parameters: [], locals: [], body: []).tap do |function|
      expressions.each do |expression|
        case expression
        in ['export', name]
          function.name = name
        in ['param', name, _]
          function.parameters << Parameter.new(name:)
        in ['param', _]
          function.parameters << Parameter.new
        in ['result', *]
        in ['local', %r{\A\$} => name, _]
          function.locals << Local.new(name:)
        in ['local', *types]
          types.each do
            function.locals << Local.new
          end
        else
          function.body << expression
        end
      end
    end
  end

  def pretty_print(expression)
    case expression
    in [*expressions]
      "(#{expressions.map { pretty_print(_1) }.join(' ')})"
    else
      expression
    end
  end

  def parse_string(string)
    encoding = string.encoding
    string.
      delete_prefix('"').delete_suffix('"').
      force_encoding(Encoding::ASCII_8BIT).
      gsub!(%r{\\\h{2}}) do |digits|
        digits.delete_prefix('\\').to_i(16).chr(Encoding::ASCII_8BIT)
      end.
      force_encoding(encoding)
  end

  def invoke_function(function:, arguments:)
    parameter_names = function.parameters.map(&:name)
    evaluate(ASTParser.new.parse(arguments), locals: [])
    argument_values = stack.pop(arguments.length)
    raise unless stack.empty?
    parameters = parameter_names.zip(argument_values)
    locals = function.locals.map(&:name).map { [_1, 0] }
    locals = parameters + locals

    evaluate(ASTParser.new.parse(function.body), locals:)
  end

  def evaluate(expression, locals:)
    while expression in [instruction, *rest]
      case instruction
      in Const(type:, bits:, number:)
        stack.push(number)
      in Load(type:, bits:, offset: static_offset)
        stack.pop(1) => [offset]
        value = @memory.load(offset: offset + static_offset, bits:)
        stack.push(value)
      in Store(type:, bits:, offset: static_offset)
        stack.pop(2) => [offset, value]
        @memory.store(value:, offset: offset + static_offset, bits:)
      in NumericOp(type: :integer, bits:, operation:)
        evaluate_integer_instruction(instruction)
      in NumericOp(type: :float, bits:, operation:)
        evaluate_float_instruction(instruction)
      in Return
        # TODO some control flow effect
      in LocalGet(index:)
        case index
        in String
          locals.assoc(index)[1]
        in Integer
          locals.slice(index)[1]
        end.tap { stack.push(_1) }
      in LocalSet | LocalTee
        instruction => { index: }
        stack.pop(1) => [value]

        case index
        in String
          locals.assoc(index)[1] = value
        in Integer
          locals.slice(index)[1] = value
        end.tap { stack.push(_1) if instruction in LocalTee }
      in BrIf(index:)
        stack.pop(1) => [condition]

        unless condition.zero?
          tag =
            case index
            in String
              index.to_sym
            in Integer
              index
            end
          throw(tag, :branch)
        end
      in Select
        stack.pop(3) => [value_1, value_2, condition]

        if condition.zero?
          value_2
        else
          value_1
        end.tap { stack.push(_1) }
      in Nop
        # do nothing
      in Call(index:)
        # TODO actually call the function
      in Drop
        stack.pop(1)
      in Block(label:, body:)
        catch(label) do
          evaluate(body, locals:)
        end
      in Loop(label:, body:)
        loop do
          result =
            catch(label) do
              evaluate(body, locals:)
            end
          break unless result == :branch
        end
      in If(label:, consequent:, alternative:)
        stack.pop(1) => [condition]
        evaluate(condition.zero? ? alternative : consequent, locals:)
      end

      expression = rest
    end
  end

  def evaluate_integer_instruction(instruction)
    instruction => { operation:, bits: }

    case operation
    in 'add' | 'sub' | 'mul' | 'div_s' | 'div_u' | 'rem_s' | 'rem_u' | 'and' | 'or' | 'xor' | 'shl' | 'shr_s' | 'shr_u' | 'rotl' | 'rotr' | 'eq' | 'ne' | 'lt_s' | 'lt_u' | 'le_s' | 'le_u' | 'gt_s' | 'gt_u' | 'ge_s' | 'ge_u'
      stack.pop(2) => [left, right]

      case operation
      in 'add'
        left + right
      in 'sub'
        left - right
      in 'mul'
        left * right
      in 'div_s'
        with_signed(left, right, bits:) do |left, right|
          divide(left, right)
        end
      in 'div_u'
        divide(left, right)
      in 'rem_s'
        with_signed(left, right, bits:) do |left, right|
          modulo(left, right)
        end
      in 'rem_u'
        modulo(left, right)
      in 'and'
        left & right
      in 'or'
        left | right
      in 'xor'
        left ^ right
      in 'shl'
        right %= bits
        left << right
      in 'shr_s'
        right %= bits
        with_signed(left, bits:) do |left|
          left >> right
        end
      in 'shr_u'
        right %= bits
        left >> right
      in 'rotl'
        right %= bits
        (left << right) | (left >> (bits - right))
      in 'rotr'
        right %= bits
        (left << (bits - right)) | (left >> right)
      in 'eq'
        bool(left == right)
      in 'ne'
        bool(left != right)
      in 'lt_s'
        with_signed(left, right, bits:) do |left, right|
          bool(left < right)
        end
      in 'lt_u'
        bool(left < right)
      in 'le_s'
        with_signed(left, right, bits:) do |left, right|
          bool(left <= right)
        end
      in 'le_u'
        bool(left <= right)
      in 'gt_s'
        with_signed(left, right, bits:) do |left, right|
          bool(left > right)
        end
      in 'gt_u'
        bool(left > right)
      in 'ge_s'
        with_signed(left, right, bits:) do |left, right|
          bool(left >= right)
        end
      in 'ge_u'
        bool(left >= right)
      end
    in 'clz' | 'ctz' | 'popcnt' | 'extend8_s' | 'extend16_s' | 'extend32_s' | 'extend_i32_s' | 'extend_i32_u' | 'eqz' | 'wrap_i64' | 'reinterpret_f32' | 'reinterpret_f64' | 'trunc_f32_s' | 'trunc_f64_s' | 'trunc_f32_u' | 'trunc_f64_u' | 'trunc_sat_f32_s' | 'trunc_sat_f64_s' | 'trunc_sat_f32_u' | 'trunc_sat_f64_u'
      stack.pop(1) => [value]

      case operation
      in 'clz'
        0.upto(bits).take_while { |count| value[bits - count, count].zero? }.last
      in 'ctz'
        0.upto(bits).take_while { |count| value[0, count].zero? }.last
      in 'popcnt'
        0.upto(bits - 1).count { |position| value[position].nonzero? }
      in 'extend8_s' | 'extend16_s' | 'extend32_s' | 'extend_i32_s'
        extend_bits = operation.slice(%r{\d+}).to_i(10)
        unsigned(signed(value, bits: extend_bits), bits:)
      in 'extend_i32_u'
        value
      in 'eqz'
        bool(value.zero?)
      in 'wrap_i64'
        value
      in 'reinterpret_f32' | 'reinterpret_f64'
        float_bits = operation.slice(%r{\d+}).to_i(10)
        raise unless bits == float_bits
        value
      in 'trunc_f32_s' | 'trunc_f64_s' | 'trunc_f32_u' | 'trunc_f64_u' | 'trunc_sat_f32_s' | 'trunc_sat_f64_s' | 'trunc_sat_f32_u' | 'trunc_sat_f64_u'
        float_bits = operation.slice(%r{\d+}).to_i(10)
        signed_input = operation.end_with?('_s')
        saturating = operation.include?('_sat')
        format = Wasminna::Float::Format.for(bits: float_bits)
        result = Wasminna::Float.decode(value, format:).to_f

        result =
          if saturating && result.nan?
            0
          elsif saturating && result.infinite?
            result
          else
            result.truncate
          end

        if saturating
          size = 1 << bits
          min, max =
            if signed_input
              [-(size / 2), (size / 2) - 1]
            else
              [0, size - 1]
            end
          result = result.clamp(min, max)
        end

        if signed_input
          unsigned(result, bits:)
        else
          result
        end
      end
    end.then { |value| mask(value, bits:) }.tap { stack.push(_1) }
  end

  def evaluate_float_instruction(instruction)
    instruction => { operation:, bits: }
    format = Wasminna::Float::Format.for(bits:)

    case operation
    in 'add' | 'sub' | 'mul' | 'div' | 'min' | 'max' | 'copysign' | 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge'
      stack.pop(2) => [left, right]

      case operation
      in 'add' | 'sub' | 'mul' | 'div' | 'min' | 'max'
        with_float(left, right, format:) do |left, right|
          case operation
          in 'add'
            left + right
          in 'sub'
            left - right
          in 'mul'
            left * right
          in 'div'
            left / right
          in 'min' | 'max'
            arguments = [left, right]
            if arguments.any?(&:nan?)
              ::Float::NAN
            elsif arguments.all?(&:zero?)
              arguments.send(:"#{operation}_by", &:sign)
            else
              arguments.send(operation)
            end
          end
        end
      in 'copysign'
        left, right =
          [left, right].map { Wasminna::Float.decode(_1, format:) }
        left.sign = right.sign
        left.encode(format:)
      in 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge'
        left, right =
          [left, right].map { Wasminna::Float.decode(_1, format:).to_f }
        operation =
          {
            'eq' => '==', 'ne' => '!=',
            'lt' => '<', 'le' => '<=',
            'gt' => '>', 'ge' => '>='
          }.fetch(operation).to_sym.to_proc
        bool(operation.call(left, right))
      end
    in 'sqrt' | 'floor' | 'ceil' | 'trunc' | 'nearest' | 'abs' | 'neg' | 'convert_i32_s' | 'convert_i64_s' | 'convert_i32_u' | 'convert_i64_u' | 'promote_f32' | 'demote_f64' | 'reinterpret_i32' | 'reinterpret_i64'
      stack.pop(1) => [value]

      case operation
      in 'sqrt' | 'floor' | 'ceil' | 'trunc' | 'nearest'
        with_float(value, format:) do |value|
          case operation
          in 'sqrt'
            if value.zero?
              value
            elsif value.negative?
              ::Float::NAN
            else
              Math.sqrt(value)
            end
          in 'floor' | 'ceil' | 'trunc' | 'nearest'
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
      in 'abs'
        value = Wasminna::Float.decode(value, format:)
        value.sign = Sign::PLUS
        value.encode(format:)
      in 'neg'
        value = Wasminna::Float.decode(value, format:)
        value.sign = !value.sign
        value.encode(format:)
      in 'convert_i32_s' | 'convert_i64_s'
        integer_bits = operation.slice(%r{\d+}).to_i(10)
        integer = signed(value, bits: integer_bits)
        Wasminna::Float.from_integer(integer).encode(format:)
      in 'convert_i32_u' | 'convert_i64_u'
        Wasminna::Float.from_integer(value).encode(format:)
      in 'promote_f32'
        raise unless bits == 64
        input_format = Wasminna::Float::Format.for(bits: 32)
        float = Wasminna::Float.decode(value, format: input_format)

        case float
        in Wasminna::Float::Nan
          Wasminna::Float::Nan.new(payload: 0, sign: float.sign)
        else
          float
        end.encode(format:)
      in 'demote_f64'
        raise unless bits == 32
        input_format = Wasminna::Float::Format.for(bits: 64)
        float = Wasminna::Float.decode(value, format: input_format)

        case float
        in Wasminna::Float::Nan
          Wasminna::Float::Nan.new(payload: 0, sign: float.sign)
        else
          float
        end.encode(format:)
      in 'reinterpret_i32' | 'reinterpret_i64'
        integer_bits = operation.slice(%r{\d+}).to_i(10)
        raise unless bits == integer_bits
        value
      end
    end.tap { stack.push(_1) }
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
end

main
