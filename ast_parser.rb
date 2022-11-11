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
    s_expression => [opcode, *rest]

    case opcode
    in NUMERIC_OPCODE_REGEXP
      parse_numeric_instruction(s_expression) =>
        [numeric_instruction, rest]
      numeric_instruction
    in 'return' | 'select' | 'nop' | 'drop' | 'unreachable'
      {
        'return' => Return,
        'select' => Select,
        'nop' => Nop,
        'drop' => Drop,
        'unreachable' => Unreachable
      }.fetch(opcode).new
    in 'local.get' | 'local.set' | 'local.tee' | 'br_if' | 'call'
      rest => [index, *rest]
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
    in 'block' | 'loop' | 'if'
      parse_structured_instruction(s_expression) =>
        [structured_instruction, rest]
      structured_instruction
    end.then do |result|
      [result, rest]
    end
  end

  def parse_numeric_instruction(s_expression)
    s_expression => [opcode, *rest]

    opcode.match(NUMERIC_OPCODE_REGEXP) =>
      { type:, bits:, operation: }
    type = { 'f' => :float, 'i' => :integer }.fetch(type)
    bits = bits.to_i(10)

    result =
      case operation
      in 'const'
        rest => [string, *rest]
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
          if rest in [%r{\Aoffset=\d+\z} => offset, *rest]
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

    [result, rest]
  end

  def parse_structured_instruction(s_expression)
    s_expression => [opcode, *rest]

    label =
      if rest in [%r{\A\$} => label, *rest]
        label.to_sym
      else
        0
      end
    rest in [['result', *], *rest]

    case opcode
    in 'block'
      consume_structured_instruction(rest, terminated_by: 'end') =>
        [body, ['end', *rest]]
      body = parse_expression(body)
      Block.new(label:, body:)
    in 'loop'
      consume_structured_instruction(rest, terminated_by: 'end') =>
        [body, ['end', *rest]]
      body = parse_expression(body)
      Loop.new(label:, body:)
    in 'if'
      consume_structured_instruction(rest, terminated_by: 'else') =>
        [consequent, ['else', *rest]]
      consume_structured_instruction(rest, terminated_by: 'end') =>
        [alternative, ['end', *rest]]
      [consequent, alternative].map { parse_expression(_1) } =>
        [consequent, alternative]
      If.new(label:, consequent:, alternative:)
    end.then do |result|
      [result, rest]
    end
  end

  def consume_structured_instruction(s_expression, terminated_by:)
    rest = s_expression
    atoms = []

    until rest in [^terminated_by, *]
      case rest
      in ['block' | 'loop' | 'if' => opcode, *rest]
        consume_structured_instruction(rest, terminated_by: 'end') =>
          [s_expression, ['end' => terminator, *rest]]
        atoms.concat([opcode, *s_expression, terminator])
      in [opcode, *rest]
        atoms << opcode
      end
    end

    [atoms, rest]
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
