require 'ast'
require 'float'
require 'helpers'

class ASTParser
  include AST
  include Helpers::Mask

  def parse(s_expression)
    parse_expression(s_expression.flat_map { unfold(_1) })
  end

  private

  def unfold(s_expression)
    case s_expression
    in ['i32.const' | 'i64.const' | 'f32.const' | 'f64.const' | 'local.get' | 'local.set' | 'local.tee' | 'br_if' | 'call' => opcode, argument, *rest]
      [*rest.flat_map { unfold(_1) }, opcode, argument]
    in ['i32.load' | 'i64.load' | 'f32.load' | 'f64.load' | 'i32.store' | 'i64.store' | 'f32.store' | 'f64.store' => opcode, %r{\Aoffset=\d+\z} => static_offset, *rest]
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

  using Helpers::MatchPattern

  def parse_expression(s_expression)
    result = []

    until s_expression.empty?
      parse_instruction(s_expression) => [instruction, rest]
      result << instruction
      s_expression = rest
    end

    result
  end

  def parse_instruction(s_expression)
    case s_expression.first
    in NUMERIC_OPCODE_REGEXP
      parse_numeric_instruction(s_expression) =>
        [numeric_instruction, s_expression]
      numeric_instruction
    in 'block' | 'loop' | 'if'
      parse_structured_instruction(s_expression) =>
        [structured_instruction, s_expression]
      structured_instruction
    else
      s_expression.shift => opcode

      case opcode
      in 'return' | 'select' | 'nop' | 'drop' | 'unreachable'
        {
          'return' => Return,
          'select' => Select,
          'nop' => Nop,
          'drop' => Drop,
          'unreachable' => Unreachable
        }.fetch(opcode).new
      in 'local.get' | 'local.set' | 'local.tee' | 'br_if' | 'call'
        s_expression.shift => index
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
          'br_if' => BrIf,
          'call' => Call
        }.fetch(opcode).new(index:)
      end
    end.then do |result|
      [result, s_expression]
    end
  end

  def parse_numeric_instruction(s_expression)
    s_expression.shift => opcode

    opcode.match(NUMERIC_OPCODE_REGEXP) =>
      { type:, bits:, operation: }
    type = { 'f' => :float, 'i' => :integer }.fetch(type)
    bits = bits.to_i(10)

    result =
      case operation
      in 'const'
        s_expression.shift => string
        number =
          case type
          in :integer
            parse_integer(string, bits:)
          in :float
            format = Wasminna::Float::Format.for(bits:)
            Wasminna::Float.parse(string).encode(format:)
          end

        Const.new(type:, bits:, number:)
      in 'load' | 'store'
        offset =
          if s_expression.first in %r{\Aoffset=\d+\z}
            s_expression.shift => %r{\Aoffset=\d+\z} => offset
            offset.split('=') => [_, offset]
            offset.to_i(10)
          else
            0
          end

        {
          'load' => Load,
          'store' => Store
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

    [result, s_expression]
  end

  def parse_structured_instruction(s_expression)
    s_expression.shift => opcode

    label =
      if s_expression.first in %r{\A\$}
        s_expression.shift => %r{\A\$} => label
        label.to_sym
      else
        0
      end
    if s_expression.first in ['result', *]
      s_expression.shift
    end

    case opcode
    in 'block'
      consume_structured_instruction(s_expression, terminated_by: 'end') =>
        [body, s_expression]
      s_expression.shift => 'end'
      body = parse_expression(body)
      Block.new(label:, body:)
    in 'loop'
      consume_structured_instruction(s_expression, terminated_by: 'end') =>
        [body, s_expression]
      s_expression.shift => 'end'
      body = parse_expression(body)
      Loop.new(label:, body:)
    in 'if'
      consume_structured_instruction(s_expression, terminated_by: 'else') =>
        [consequent, s_expression]
      s_expression.shift => 'else'
      consume_structured_instruction(s_expression, terminated_by: 'end') =>
        [alternative, s_expression]
      s_expression.shift => 'end'
      [consequent, alternative].map { parse_expression(_1) } =>
        [consequent, alternative]
      If.new(label:, consequent:, alternative:)
    end.then do |result|
      [result, s_expression]
    end
  end

  def consume_structured_instruction(s_expression, terminated_by:)
    atoms = []

    until s_expression in [^terminated_by, *]
      s_expression.shift => opcode

      case opcode
      in 'block' | 'loop' | 'if'
        consume_structured_instruction(s_expression, terminated_by: 'end') =>
          [body, s_expression]
        s_expression.shift => 'end' => terminator
        atoms.concat([opcode, *body, terminator])
      in opcode
        atoms << opcode
      end
    end

    [atoms, s_expression]
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

  def parse_integer(string, bits:)
    value =
      if string.delete_prefix('-').start_with?('0x')
        string.to_i(16)
      else
        string.to_i(10)
      end

    unsigned(value, bits:)
  end
end
