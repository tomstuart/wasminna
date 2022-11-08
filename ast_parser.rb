require 'ast'

class ASTParser
  include AST

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

  def parse_expression(s_expression)
    result = []

    while s_expression in [instruction, *rest]
      result <<
        case instruction
        in 'return'
          Return.new
        in 'local.get' | 'local.set' | 'local.tee' | 'br_if'
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
            'br_if' => BrIf
          }.fetch(instruction).new(index:)
        in 'select'
          Select.new
        else
          instruction
        end

      s_expression = rest
    end

    result
  end
end
