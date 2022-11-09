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
    in ['i32.const' | 'i64.const' | 'f32.const' | 'f64.const' | 'local.get' | 'local.set' | 'local.tee' | 'br_if' | 'call' => instruction, argument, *rest]
      [*rest.flat_map { unfold(_1) }, instruction, argument]
    in ['i32.load' | 'i64.load' | 'f32.load' | 'f64.load' | 'i32.store' | 'i64.store' | 'f32.store' | 'f64.store' => instruction, %r{\Aoffset=\d+\z} => static_offset, *rest]
      [*rest.flat_map { unfold(_1) }, instruction, static_offset]
    in ['block' | 'loop' | 'if' => instruction, *rest]
      rest in [%r{\A\$} => label, *rest]
      rest in [['result', *] => type, *rest]

      case instruction
      in 'block' | 'loop'
        rest => [*instructions]
        [
          instruction,
          label,
          type,
          *instructions.flat_map { unfold(_1) },
          'end'
        ].compact
      in 'if'
        rest => [*condition, ['then', *consequent], *rest]
        rest in [['else', *alternative], *rest]
        rest => []
        [
          *condition.flat_map { unfold(_1) },
          instruction,
          label,
          type,
          *consequent.flat_map { unfold(_1) },
          'else',
          *alternative&.flat_map { unfold(_1) },
          'end'
        ].compact
      end
    in [instruction, *rest]
      [*rest.flat_map { unfold(_1) }, instruction]
    else
      [s_expression]
    end
  end

  NUMERIC_INSTRUCTION_REGEXP =
    %r{
      \A
      (?<type>[fi]) (?<bits>32|64) \. (?<operation>.+)
      \z
    }x

  using Helpers::MatchPattern

  def parse_expression(s_expression)
    result = []

    while s_expression in [instruction, *rest]
      result <<
        case instruction
        in %r{\A[fi](32|64)\.(const|load)\z}
          parse_numeric_instruction(s_expression) =>
            [numeric_instruction, rest]
          numeric_instruction
        in 'return'
          Return.new
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
          }.fetch(instruction).new(index:)
        in 'select'
          Select.new
        in 'nop'
          Nop.new
        in 'drop'
          Drop.new
        in 'block' | 'loop' | 'if' => instruction
          label =
            if rest in [%r{\A\$} => label, *rest]
              label.to_sym
            else
              0
            end
          rest in [['result', *], *rest]

          case instruction
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
          end
        else
          instruction
        end

      s_expression = rest
    end

    result
  end

  def parse_numeric_instruction(s_expression)
    s_expression => [instruction, *rest]

    instruction.match(NUMERIC_INSTRUCTION_REGEXP) =>
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
      in 'load'
        offset =
          if rest in [%r{\Aoffset=\d+\z} => offset, *rest]
            offset.split('=') => [_, offset]
            offset.to_i(10)
          else
            0
          end

        Load.new(type:, bits:, offset:)
      end

    [result, rest]
  end

  def consume_structured_instruction(s_expression, terminated_by:)
    rest = s_expression
    instructions = []

    until rest in [^terminated_by, *]
      case rest
      in ['block' | 'loop' | 'if' => instruction, *rest]
        consume_structured_instruction(rest, terminated_by: 'end') =>
          [s_expression, ['end' => terminator, *rest]]
        instructions.concat([instruction, *s_expression, terminator])
      in [instruction, *rest]
        instructions << instruction
      end
    end

    [instructions, rest]
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
