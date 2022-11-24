require 'ast'
require 'float'
require 'helpers'

class ASTParser
  include AST
  include Helpers::Mask

  def parse_expression(s_expression)
    read_list(from: s_expression) do
      parse_instructions
    end
  end

  def parse_script(s_expression)
    read_list(from: s_expression) do
      parse_commands
    end
  end

  private

  attr_accessor :s_expression

  def parse_commands
    repeatedly { parse_command }
  end

  def parse_command
    read_list do
      case peek
      in 'module'
        parse_module
      in 'invoke'
        parse_invoke
      in 'assert_return'
        parse_assert_return
      in 'assert_malformed' | 'assert_trap' | 'assert_invalid' | 'assert_exhaustion'
        # TODO
        repeatedly { read }
        SkippedAssertion.new
      end
    end
  end

  def parse_module
    read => 'module'
    functions, memory, tables, globals, types = [], nil, [], [], []

    case peek
    in 'binary'
      # TODO
      repeatedly { read }
    else
      repeatedly do
        read_list do
          case peek
          in 'func'
            functions << parse_function
          in 'memory'
            memory = parse_memory
          in 'table'
            tables << parse_table
          in 'global'
            globals << parse_global
          in 'type'
            types << parse_type
          end
        end
      end
    end

    Module.new(functions:, memory:, tables:, globals:, types:)
  end

  def parse_invoke
    read => 'invoke'
    read => name
    arguments = parse_instructions

    Invoke.new(name:, arguments:)
  end

  def parse_assert_return
    read => 'assert_return'
    invoke = read_list { parse_invoke }

    expecteds =
      repeatedly do
        case peek
        in ['f32.const' | 'f64.const', 'nan:canonical' | 'nan:arithmetic']
          read_list do
            read => 'f32.const' | 'f64.const' => instruction
            bits = instruction.slice(%r{\d+}).to_i(10)
            read => 'nan:canonical' | 'nan:arithmetic' => nan

            NanExpectation.new(nan:, bits:)
          end
        else
          read_list { parse_instructions }
        end
      end

    AssertReturn.new(invoke:, expecteds:)
  end

  def parse_type
    read => 'type'
    if peek in %r{\A\$}
      read => %r{\A\$} => name
    end

    parameters, results = [], []
    read_list do
      read => 'func'

      repeatedly do
        read_list do
          case read
          in 'param'
            parameters.concat(
              if peek in %r{\A\$}
                read => %r{\A\$} => parameter_name
                read
                [Parameter.new(name: parameter_name)]
              else
                repeatedly { read }.map { Parameter.new(name: nil) }
              end
            )
          in 'result'
            results.concat(repeatedly { read })
          end
        end
      end
    end

    Type.new(name:, parameters:, results:)
  end

  def parse_function
    read => 'func'
    if peek in %r{\A\$}
      read => %r{\A\$} => name
    end

    exported_name, type_index, parameters, results, locals, body =
      nil, nil, [], [], [], []
    repeatedly do
      if can_read_list?
        read_list do
          case peek
          in 'export' | 'type' | 'param' | 'result' | 'local'
            case read
            in 'export'
              read => exported_name
            in 'type'
              read => %r{\A(\d+|\$.+)\z} => type_index
              type_index =
                if type_index.start_with?('$')
                  type_index
                else
                  type_index.to_i(10)
                end
            in 'param'
              if peek in %r{\A\$}
                read => %r{\A\$} => parameter_name
                read
                parameters << Parameter.new(name: parameter_name)
              else
                repeatedly do
                  read
                  parameters << Parameter.new(name: nil)
                end
              end
            in 'result'
              results.concat(repeatedly { read })
            in 'local'
              if peek in %r{\A\$}
                read => %r{\A\$} => local_name
                read
                locals << Local.new(name: local_name)
              else
                repeatedly do
                  read
                  locals << Local.new(name: nil)
                end
              end
            end
          else
            body << repeatedly { read }
          end
        end
      else
        body << read
      end
    end
    body = read_list(from: body) { parse_instructions }

    Function.new(name:, exported_name:, type_index:, parameters:, results:, locals:, body:)
  end

  def parse_memory
    read => 'memory'
    if can_read_list?(starting_with: 'data')
      string =
        read_list do
          read => 'data'
          repeatedly { parse_string }.join
        end
    else
      minimum_size = parse_integer(bits: 32)
      maximum_size = parse_integer(bits: 32) unless finished?
    end

    Memory.new(string:, minimum_size:, maximum_size:)
  end

  def parse_table
    read => 'table'
    if peek in %r{\A(\d+|\$.+)\z}
      read => %r{\A(\d+|\$.+)\z} => name
    end

    read => 'funcref'

    elements =
      if can_read_list?(starting_with: 'elem')
        read_list do
          read => 'elem'
          repeatedly { read }
        end
      else
        []
      end

    Table.new(name:, elements:)
  end

  def parse_global
    read => 'global'
    read => name
    read_list do
      read => 'mut'
      read
    end
    value = parse_instructions

    Global.new(name:, value:)
  end

  def unfold(s_expression)
    case s_expression
    in ['i32.const' | 'i64.const' | 'f32.const' | 'f64.const' | 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'br' | 'br_if' | 'call' => opcode, argument, *rest]
      [*rest, opcode, argument]
    in ['i32.load' | 'i64.load' | 'i64.load8_s' | 'f32.load' | 'f64.load' | 'i32.store' | 'i32.store8' | 'i64.store' | 'i64.store16' | 'f32.store' | 'f64.store' => opcode, %r{\Aoffset=\d+\z} => static_offset, *rest]
      [*rest, opcode, static_offset]
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
          *body,
          'end'
        ].compact
      in 'if'
        rest => [*condition, ['then', *consequent], *rest]
        rest in [['else', *alternative], *rest]
        rest => []
        [
          *condition,
          opcode,
          label,
          type,
          *consequent,
          'else',
          *alternative,
          'end'
        ].compact
      end
    in ['br_table' => opcode, *rest]
      rest => [%r{\A(\d+|\$.+)\z} => index, *rest]
      indexes = [index]
      while rest in [%r{\A(\d+|\$.+)\z} => index, *rest]
        indexes << index
      end

      [*rest, opcode, *indexes]
    in ['call_indirect' => opcode, *rest]
      rest in [%r{\A(\d+|\$.+)\z} => table_index, *rest]
      rest in [['type', %r{\A(\d+|\$.+)\z}] => typeuse, *rest]
      params = []
      while rest in [['param', *] => param, *rest]
        params << param
      end
      results = []
      while rest in [['result', *] => result, *rest]
        results << result
      end

      [
        *rest,
        opcode,
        table_index,
        typeuse,
        *params,
        *results
      ].compact
    in ['select' => opcode, *rest]
      rest in [['result', *] => type, *rest]

      [
        *rest,
        opcode,
        type
      ].compact
    in [opcode, *rest]
      [*rest, opcode]
    end
  end

  NUMERIC_OPCODE_REGEXP =
    %r{
      \A
      (?<type>[fi]) (?<bits>32|64) \. (?<operation>.+)
      \z
    }x

  def parse_instructions
    repeatedly do
      if can_read_list?
        parse_folded_instruction
      else
        [parse_instruction]
      end
    end.flatten(1)
  end

  def read_list(from: read)
    raise unless from in [*]
    previous_s_expression, self.s_expression = self.s_expression, from

    result = yield
    raise unless self.s_expression.empty?

    self.s_expression = previous_s_expression
    result
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

  def parse_folded_instruction
    read_list(from: unfold(read)) do
      parse_instructions
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
    results =
      if can_read_list?(starting_with: 'result')
        read_list do
          read => 'result'
          repeatedly { read }
        end
      else
        []
      end

    read_list(from: read_until('end')) do
      case opcode
      in 'block'
        body = parse_instructions
        Block.new(label:, results:, body:)
      in 'loop'
        body = parse_instructions
        Loop.new(label:, results:, body:)
      in 'if'
        consequent =
          read_list(from: read_until('else')) do
            parse_instructions
          end
        if peek in 'else'
          read => 'else'
          if !label.nil? && peek in ^label
            read => ^label
          end
          alternative = parse_instructions
        end

        If.new(label:, results:, consequent:, alternative:)
      end
    end.tap do
      read => 'end'
      if !label.nil? && peek in ^label
        read => ^label
      end
    end
  end

  def parse_normal_instruction
    case read
    in 'return' | 'nop' | 'drop' | 'unreachable' | 'memory.grow' => opcode
      {
        'return' => Return,
        'nop' => Nop,
        'drop' => Drop,
        'unreachable' => Unreachable,
        'memory.grow' => MemoryGrow
      }.fetch(opcode).new
    in 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'br' | 'br_if' | 'call' => opcode
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
        'global.get' => GlobalGet,
        'global.set' => GlobalSet,
        'br' => Br,
        'br_if' => BrIf,
        'call' => Call
      }.fetch(opcode).new(index:)
    in 'br_table'
      indexes =
        repeatedly(until: -> { !%r{\A(\d+|\$.+)\z}.match(_1) }) do
          if peek.start_with?('$')
            read
          else
            read.to_i(10)
          end
        end
      indexes => [*target_indexes, default_index]

      BrTable.new(target_indexes:, default_index:)
    in 'call_indirect'
      table_index =
        if peek in %r{\A(\d+|\$.+)\z}
          read => %r{\A(\d+|\$.+)\z} => table_index
          if table_index.start_with?('$')
            table_index
          else
            table_index.to_i(10)
          end
        else
          0
        end
      type_index =
        if can_read_list?(starting_with: 'type')
          read_list do
            read => 'type'
            read => %r{\A(\d+|\$.+)\z}
          end
        end
      while can_read_list?(starting_with: 'param')
        read_list do
          read => 'param'
          repeatedly { read }
        end
      end
      while can_read_list?(starting_with: 'result')
        read_list do
          read => 'result'
          repeatedly { read }
        end
      end

      CallIndirect.new(table_index:, type_index:)
    in 'select'
      if can_read_list?(starting_with: 'result')
        read_list do
          read => 'result'
          repeatedly { read }
        end
      end

      Select.new
    end
  end

  def read_until(terminator)
    repeatedly(until: terminator) do
      if peek in 'block' | 'loop' | 'if'
        [read, *read_until('end'), read]
      else
        [read]
      end
    end.flatten(1)
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

  def parse_string
    read => string
    encoding = string.encoding
    string.
      delete_prefix('"').delete_suffix('"').
      force_encoding(Encoding::ASCII_8BIT).
      gsub!(%r{\\\h{2}}) do |digits|
        digits.delete_prefix('\\').to_i(16).chr(Encoding::ASCII_8BIT)
      end.
      force_encoding(encoding)
  end

  def repeatedly(**kwargs)
    terminator = kwargs[:until]

    [].tap do |results|
      until finished? || (!terminator.nil? && peek in ^terminator)
        results << yield
      end
    end
  end

  def can_read_list?(starting_with: nil)
    if starting_with.nil?
      peek in [*]
    else
      peek in [^starting_with, *]
    end
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
