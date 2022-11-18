require 'ast'
require 'float'
require 'helpers'

class ASTParser
  include AST
  include Helpers::Mask

  def parse(s_expression)
    end_of_input = Object.new
    self.s_expression = s_expression.flat_map { unfold(_1) } + [end_of_input]
    parse_expression(terminated_by: end_of_input)
  end

  private

  attr_accessor :s_expression

  def unfold(s_expression)
    case s_expression
    in ['i32.const' | 'i64.const' | 'f32.const' | 'f64.const' | 'local.get' | 'local.set' | 'local.tee' | 'global.set' | 'br' | 'br_if' | 'call' => opcode, argument, *rest]
      [*rest.flat_map { unfold(_1) }, opcode, argument]
    in ['i32.load' | 'i64.load' | 'i64.load8_s' | 'f32.load' | 'f64.load' | 'i32.store' | 'i32.store8' | 'i64.store' | 'i64.store16' | 'f32.store' | 'f64.store' => opcode, %r{\Aoffset=\d+\z} => static_offset, *rest]
      [*rest.flat_map { unfold(_1) }, opcode, static_offset]
    in ['block' | 'loop' | 'if' => opcode, *rest]
      rest in [%r{\A\$} => label, *rest]
      rest in [['result', *] => type, *rest]

      case opcode
      in 'block' | 'loop'
        rest => [*body]
        [
          opcode,
          label,
          type,
          *body.flat_map { unfold(_1) },
          'end'
        ].compact
      in 'if'
        rest => [*condition, ['then', *consequent], *rest]
        rest in [['else', *alternative], *rest]
        rest => []
        [
          *condition.flat_map { unfold(_1) },
          opcode,
          label,
          type,
          *consequent.flat_map { unfold(_1) },
          'else',
          *alternative&.flat_map { unfold(_1) },
          'end'
        ].compact
      end
    in ['br_table' => opcode, *rest]
      rest => [%r{\A(\d+|\$.+)\z} => index, *rest]
      indexes = [index]
      while rest in [%r{\A(\d+|\$.+)\z} => index, *rest]
        indexes << index
      end

      [*rest.flat_map { unfold(_1) }, opcode, *indexes]
    in ['call_indirect' => opcode, *rest]
      rest in [%r{\A(\d+|\$.+)\z} => table_index, *rest]
      rest => [['type', %r{\A(\d+|\$.+)\z}] => typeuse, *rest]

      [
        *rest.flat_map { unfold(_1) },
        opcode,
        table_index,
        typeuse
      ].compact
    in [opcode, *rest]
      [*rest.flat_map { unfold(_1) }, opcode]
    else
      [s_expression]
    end
  end

  NUMERIC_OPCODE_REGEXP =
    %r{
      \A
      (?<type>[fi]) (?<bits>32|64) \. (?<operation>.+)
      \z
    }x

  def parse_expression(terminated_by:)
    with_input(read_until(terminated_by:)) do
      [].tap do |expression|
        expression << parse_instruction until finished?
      end
    end
  end

  def with_input(s_expression)
    previous_s_expression, self.s_expression =
      self.s_expression, s_expression

    begin
      yield
    ensure
      self.s_expression = previous_s_expression
    end
  end

  def parse_instruction
    case peek
    in NUMERIC_OPCODE_REGEXP
      parse_numeric_instruction
    in 'block' | 'loop' | 'if'
      parse_structured_instruction
    else
      parse_normal_instruction
    end
  end

  def parse_numeric_instruction
    read => opcode

    opcode.match(NUMERIC_OPCODE_REGEXP) =>
      { type:, bits:, operation: }
    type = { 'f' => :float, 'i' => :integer }.fetch(type)
    bits = bits.to_i(10)

    case operation
    in 'const'
      number =
        case type
        in :integer
          parse_integer(bits:)
        in :float
          parse_float(bits:)
        end

      Const.new(type:, bits:, number:)
    in 'load' | 'load8_s' | 'store' | 'store8' | 'store16'
      offset =
        if peek in %r{\Aoffset=\d+\z}
          read => %r{\Aoffset=\d+\z} => offset
          offset.split('=') => [_, offset]
          offset.to_i(10)
        else
          0
        end

      {
        'load' => Load,
        'load8_s' => Load,
        'store' => Store,
        'store8' => Store,
        'store16' => Store
      }.fetch(operation).new(type:, bits:, offset:)
    else
      case type
      in :integer
        case operation
        in 'add' | 'sub' | 'mul' | 'div_s' | 'div_u' | 'rem_s' | 'rem_u' | 'and' | 'or' | 'xor' | 'shl' | 'shr_s' | 'shr_u' | 'rotl' | 'rotr' | 'eq' | 'ne' | 'lt_s' | 'lt_u' | 'le_s' | 'le_u' | 'gt_s' | 'gt_u' | 'ge_s' | 'ge_u'
          BinaryOp.new(type:, bits:, operation:)
        in 'clz' | 'ctz' | 'popcnt' | 'extend8_s' | 'extend16_s' | 'extend32_s' | 'extend_i32_s' | 'extend_i32_u' | 'eqz' | 'wrap_i64' | 'reinterpret_f32' | 'reinterpret_f64' | 'trunc_f32_s' | 'trunc_f64_s' | 'trunc_f32_u' | 'trunc_f64_u' | 'trunc_sat_f32_s' | 'trunc_sat_f64_s' | 'trunc_sat_f32_u' | 'trunc_sat_f64_u'
          UnaryOp.new(type:, bits:, operation:)
        end
      in :float
        case operation
        in 'add' | 'sub' | 'mul' | 'div' | 'min' | 'max' | 'copysign' | 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge'
          BinaryOp.new(type:, bits:, operation:)
        in 'sqrt' | 'floor' | 'ceil' | 'trunc' | 'nearest' | 'abs' | 'neg' | 'convert_i32_s' | 'convert_i64_s' | 'convert_i32_u' | 'convert_i64_u' | 'promote_f32' | 'demote_f64' | 'reinterpret_i32' | 'reinterpret_i64'
          UnaryOp.new(type:, bits:, operation:)
        end
      end
    end
  end

  def parse_structured_instruction
    read => opcode

    if peek in %r{\A\$}
      read => %r{\A\$} => label
    end
    if peek in ['result', *]
      read => ['result', *results]
    else
      results = []
    end

    case opcode
    in 'block'
      Block.new(label:, results:, body: parse_expression(terminated_by: 'end'))
    in 'loop'
      Loop.new(label:, results:, body: parse_expression(terminated_by: 'end'))
    in 'if'
      If.new \
        label:,
        results:,
        consequent: parse_expression(terminated_by: 'else'),
        alternative: parse_expression(terminated_by: 'end')
    end
  end

  def parse_normal_instruction
    read => opcode

    case opcode
    in 'return' | 'select' | 'nop' | 'drop' | 'unreachable' | 'memory.grow'
      {
        'return' => Return,
        'select' => Select,
        'nop' => Nop,
        'drop' => Drop,
        'unreachable' => Unreachable,
        'memory.grow' => MemoryGrow
      }.fetch(opcode).new
    in 'local.get' | 'local.set' | 'local.tee' | 'global.set' | 'br' | 'br_if' | 'call'
      read => index
      index =
        if index.start_with?('$')
          index
        else
          index.to_i(10)
        end

      {
        'local.get' => LocalGet,
        'local.set' => LocalSet,
        'local.tee' => LocalTee,
        'global.set' => GlobalSet,
        'br' => Br,
        'br_if' => BrIf,
        'call' => Call
      }.fetch(opcode).new(index:)
    in 'br_table'
      read => %r{\A(\d+|\$.+)\z} => index
      indexes = [index]
      while peek in %r{\A(\d+|\$.+)\z}
        read => %r{\A(\d+|\$.+)\z} => index
        indexes << index
      end
      indexes =
        indexes.map do |index|
          if index.start_with?('$')
            index
          else
            index.to_i(10)
          end
        end
      indexes => [*target_indexes, default_index]

      BrTable.new(target_indexes:, default_index:)
    in 'call_indirect'
      if peek in %r{\A(\d+|\$.+)\z}
        read => %r{\A(\d+|\$.+)\z} => table_index
        table_index =
          if table_index.start_with?('$')
            table_index
          else
            table_index.to_i(10)
          end
      else
        table_index = 0
      end
      read => ['type', %r{\A(\d+|\$.+)\z} => type_index]

      CallIndirect.new(table_index:, type_index:)
    end
  end

  def read_until(terminated_by:)
    [].tap do |atoms|
      loop do
        read => opcode
        break if opcode == terminated_by

        atoms << opcode
        if opcode in 'block' | 'loop' | 'if'
          atoms.concat(read_until(terminated_by: 'end'))
          atoms << 'end'
        end
      end
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

  def parse_integer(bits:)
    read => string
    value =
      if string.delete_prefix('-').start_with?('0x')
        string.to_i(16)
      else
        string.to_i(10)
      end

    unsigned(value, bits:)
  end

  def parse_float(bits:)
    format = Wasminna::Float::Format.for(bits:)
    Wasminna::Float.parse(read).encode(format:)
  end

  def finished?
    s_expression.empty?
  end

  def peek
    s_expression.first
  end

  def read
    s_expression.shift
  end
end
