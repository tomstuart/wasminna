require 'ast'
require 'ast_parser'
require 'float'
require 'helpers'
require 's_expression_parser'
require 'sign'

def main
  unless ARGV.empty?
    s_expression = SExpressionParser.new.parse(ARGF.read)
    script = ASTParser.new.parse_script(s_expression)
    Interpreter.new.evaluate_script(script)
    puts
  end
end

class Interpreter
  include AST
  include Helpers::Mask

  class Memory < Data.define(:bytes)
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

    def grow_by(pages:)
      bytes << "\0" * (pages * BYTES_PER_PAGE)
    end

    def size_in_pages
      size_of(bytes.bytesize, in: BYTES_PER_PAGE)
    end
  end

  attr_accessor :stack, :functions, :function, :tables, :globals, :types

  def evaluate_script(script)
    @memory = nil
    self.stack = []

    script.each do |command|
      begin
        case command
        in Module(functions:, tables:, memory:, globals:, types:)
          self.functions = functions
          self.tables = tables
          self.types = types

          unless memory.nil?
            @memory =
              if memory.string.nil?
                Memory.from_limits \
                  minimum_size: memory.minimum_size,
                  maximum_size: memory.maximum_size
              else
                Memory.from_string(string: memory.string)
              end
          end

          self.globals =
            globals.map do |global|
              evaluate_expression(global.value, locals: [])
              stack.pop(1) => [value]
              value
            end
        in Invoke(name:, arguments:)
          function = self.functions.detect { |function| function.exported_name == name }
          if function.nil?
            puts
            puts "\e[33mWARNING: couldn’t find function #{name} (could be binary?), skipping\e[0m"
            next
          end

          evaluate_expression(arguments, locals: [])
          invoke_function(function)
        in AssertReturn(invoke: Invoke(name:, arguments:), expecteds:)
          function = self.functions.detect { |function| function.exported_name == name }
          if function.nil?
            puts
            puts "\e[33mWARNING: couldn’t find function #{name} (could be binary?), skipping\e[0m"
            next
          end

          evaluate_expression(arguments, locals: [])
          invoke_function(function)
          actual_values = stack.pop(expecteds.length)
          raise unless stack.empty?

          expecteds.zip(actual_values).each do |expected, actual_value|
            case expected
            in NanExpectation(nan:, bits:)
              expected_value = nan
              format = Wasminna::Float::Format.for(bits:)
              float = Wasminna::Float.decode(actual_value, format:).to_f
              success = float.nan? # TODO check whether canonical or arithmetic
            else
              evaluate_expression(expected, locals: [])
              stack.pop(1) => [expected_value]
              raise unless stack.empty?
              success = actual_value == expected_value
            end

            unless success
              puts
              puts "\e[31mFAILED\e[0m: \e[33m#{pretty_print(command)}\e[0m"
              puts "expected #{expected_value.inspect}, got #{actual_value.inspect}"
              exit 1
            end
          end

          print "\e[32m.\e[0m"
        in SkippedAssertion
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

  def pretty_print(ast)
    ast.inspect
  end

  def with_current_function(function)
    previous_function, self.function = self.function, function

    begin
      yield
    ensure
      self.function = previous_function
    end
  end

  def invoke_function(function)
    type = types.slice(function.type_index) || raise
    arity = type.parameters.length
    argument_values = stack.pop(arity)
    locals = function.locals.map { 0 }
    locals = argument_values + locals

    with_current_function(function) do
      catch(:return) do
        with_branch_handler(label: nil, type:) do
          evaluate_expression(function.body, locals:)
        end
      end
    end
  end

  def evaluate_expression(expression, locals:)
    expression.each do |instruction|
      evaluate_instruction(instruction, locals:)
    end
  end

  def evaluate_instruction(instruction, locals:)
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
    in UnaryOp(type: :integer) | BinaryOp(type: :integer)
      evaluate_integer_instruction(instruction)
    in UnaryOp(type: :float) | BinaryOp(type: :float)
      evaluate_float_instruction(instruction)
    in Return
      type = types.slice(function.type_index) || raise
      stack.pop(type.results.length) => results
      stack.pop until stack.empty? # TODO stop at activation frame
      stack.push(*results)
      throw(:return)
    in LocalGet(index:)
      stack.push(locals.slice(index))
    in LocalSet | LocalTee
      instruction => { index: }
      stack.pop(1) => [value]
      locals[index] = value
      stack.push(value) if instruction in LocalTee
    in GlobalGet(index:)
      stack.push(globals.slice(index))
    in GlobalSet(index:)
      stack.pop(1) => [value]
      globals[index] = value
    in Br(index:)
      throw(:branch, index)
    in BrIf(index:)
      stack.pop(1) => [condition]
      throw(:branch, index) unless condition.zero?
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
      function = functions.slice(index) || raise
      invoke_function(function)
    in CallIndirect(table_index:, type_index:)
      stack.pop(1) => [index]

      table = tables.slice(table_index)
      index = table.elements.slice(index)
      function = functions.slice(index) || raise
      invoke_function(function)
    in Drop
      stack.pop(1)
    in Block(label:, type:, body:)
      type = expand_blocktype(type)
      with_branch_handler(label:, type:) do
        evaluate_expression(body, locals:)
      end
    in Loop(label:, type:, body:)
      type = expand_blocktype(type)
      with_branch_handler(label:, type:, redo_on_branch: true) do
        evaluate_expression(body, locals:)
      end
    in If(label:, type:, consequent:, alternative:)
      type = expand_blocktype(type)
      stack.pop(1) => [condition]
      body = condition.zero? ? alternative : consequent

      with_branch_handler(label:, type:) do
        evaluate_expression(body, locals:)
      end
    in BrTable(target_indexes:, default_index:)
      stack.pop(1) => [table_index]
      index =
        if table_index < target_indexes.length
          target_indexes.slice(table_index)
        else
          default_index
        end
      throw(:branch, index)
    in MemoryGrow
      stack.pop(1) => [pages]
      stack.push(@memory.size_in_pages)
      @memory.grow_by(pages:)
    end
  end

  def expand_blocktype(blocktype)
    case blocktype
    in Integer
      types.slice(blocktype) || raise
    in Array
      Type.new(parameters: [], results: blocktype)
    end
  end

  def with_branch_handler(label:, type:, redo_on_branch: false)
    tap do
      stack_height = stack.length
      result =
        catch(:branch) do
          yield
          :did_not_throw
        end

      case result
      in :did_not_throw
      in String
        if result == label
          stack.pop(type.results.length) => saved_operands
          stack.pop(stack.length - stack_height)
          stack.push(*saved_operands)
          redo if redo_on_branch
        else
          throw(:branch, result)
        end
      in Integer
        if result.zero?
          stack.pop(type.results.length) => saved_operands
          stack.pop(stack.length - stack_height)
          stack.push(*saved_operands)
          redo if redo_on_branch
        else
          throw(:branch, result - 1)
        end
      end
    end
  end

  def evaluate_integer_instruction(instruction)
    case instruction
    in BinaryOp(bits:, operation:)
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
    in UnaryOp(bits:, operation:)
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
    format = Wasminna::Float::Format.for(bits: instruction.bits)

    case instruction
    in BinaryOp(bits:, operation:)
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
        left.with_sign(right.sign).encode(format:)
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
    in UnaryOp(bits:, operation:)
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
        value.with_sign(Sign::PLUS).encode(format:)
      in 'neg'
        value = Wasminna::Float.decode(value, format:)
        value.with_sign(!value.sign).encode(format:)
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
end

main
