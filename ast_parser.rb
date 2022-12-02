require 'ast'
require 'float'
require 'helpers'

class ASTParser
  include AST
  include Helpers::Mask

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
        parse_unsupported_assertion
      end
    end
  end

  def parse_module
    read => 'module'
    fields =
      case peek
      in 'binary'
        parse_binary_fields
      else
        parse_text_fields
      end

    Module.new(**fields)
  end

  def parse_binary_fields
    # TODO
    repeatedly { read }

    { functions: [], memory: nil, tables: [], globals: [], types: [] }
  end

  Context = Data.define(:types, :functions, :globals, :locals, :typedefs) do
    def initialize(types: [], functions: [], globals: [], locals: [], typedefs: [])
      super
    end

    def +(other)
      index_spaces =
        to_h.merge(other.to_h) do |key, left, right|
          raise unless left.intersection(right).compact.empty? || key == :typedefs
          left + right
        end
      Context.new(**index_spaces)
    end
  end

  def parse_text_fields
    functions, memory, tables, globals, types, generated_types =
      [], nil, [], [], [], []
    context =
      read_list(from: Marshal.load(Marshal.dump(s_expression))) do
        build_initial_context
      end

    repeatedly do
      read_list do
        case peek
        in 'func'
          parse_function(context:) => [function, context, type]
          functions << function
          generated_types << type unless type.nil?
        in 'memory'
          memory = parse_memory
        in 'table'
          tables << parse_table(context:)
        in 'global'
          globals << parse_global(context:)
        in 'type'
          types << parse_type
        end
      end
    end

    { functions:, memory:, tables:, globals:, types: types + generated_types }
  end

  def build_initial_context
    repeatedly do
      read_list do
        case read
        in 'func'
          if peek in ID_REGEXP
            read => ID_REGEXP => name
          end
          repeatedly { read }
          Context.new(functions: [name])
        in 'memory'
          repeatedly { read }
          Context.new
        in 'table'
          repeatedly { read }
          Context.new
        in 'global'
          if peek in ID_REGEXP
            read => ID_REGEXP => name
          end
          repeatedly { read }
          Context.new(globals: [name])
        in 'type'
          if peek in ID_REGEXP
            read => ID_REGEXP => name
          end
          functype =
            read_list(starting_with: 'func') do
              parameters = parse_parameters
              results = parse_results
              { parameters:, results: }
            end
          Context.new(types: [name], typedefs: [functype])
        end
      end
    end.inject(Context.new, :+)
  end

  def parse_invoke
    read => 'invoke'
    read => name
    arguments = parse_instructions(context: Context.new)

    Invoke.new(name:, arguments:)
  end

  def parse_assert_return
    read => 'assert_return'
    invoke = read_list { parse_invoke }
    expecteds = parse_expecteds

    AssertReturn.new(invoke:, expecteds:)
  end

  def parse_expecteds
    repeatedly do
      read_list do
        case peek
        in 'f32.const' | 'f64.const'
          parse_float_expectation
        else
          parse_instructions(context: Context.new)
        end
      end
    end
  end

  def parse_float_expectation
    read => 'f32.const' | 'f64.const' => opcode
    bits = opcode.slice(%r{\d+}).to_i(10)

    if peek in 'nan:canonical' | 'nan:arithmetic'
      read => 'nan:canonical' | 'nan:arithmetic' => nan
      NanExpectation.new(nan:, bits:)
    else
      number = parse_float(bits:)
      [Const.new(type: :float, bits:, number:)]
    end
  end

  def parse_unsupported_assertion
    # TODO
    repeatedly { read }
    SkippedAssertion.new
  end

  ID_REGEXP = %r{\A\$}

  def parse_type
    read => 'type'
    if peek in ID_REGEXP
      read => ID_REGEXP => name
    end

    read_list do
      read => 'func'
      parameters = parse_parameters
      results = parse_results

      Type.new(name:, parameters:, results:)
    end
  end

  def parse_parameters
    read_lists(starting_with: 'param') { parse_parameter }
  end

  def parse_results
    read_lists(starting_with: 'result') { parse_result }
  end

  def parse_locals
    read_lists(starting_with: 'local') { parse_local }
  end

  def read_lists(starting_with:)
    [].tap do |results|
      while can_read_list?(starting_with:)
        read_list do
          results.concat(yield)
        end
      end
    end
  end

  def parse_parameter
    read => 'param'
    if peek in ID_REGEXP
      read => ID_REGEXP => name
      read => type
      [Parameter.new(name:, type:)]
    else
      repeatedly { read }.map { |type| Parameter.new(name: nil, type:) }
    end
  end

  def parse_result
    read => 'result'
    repeatedly { read }.map { |type| Result.new(type:) }
  end

  def parse_local
    read => 'local'
    if peek in ID_REGEXP
      read => ID_REGEXP => name
      read
      [[name, Local.new]]
    else
      repeatedly { read }.map { [nil, Local.new] }
    end
  end

  def parse_function(context:)
    read => 'func'
    if peek in ID_REGEXP
      read => ID_REGEXP
    end
    exported_name = parse_export
    parse_typeuse(context:) => [type_index, parameters, results]
    if type_index.nil?
      type_index =
        context.typedefs.find_index do |typedef|
          typedef.fetch(:parameters).map(&:type) == parameters.map(&:type) &&
            typedef.fetch(:results).map(&:type) == results.map(&:type)
        end

      if type_index.nil?
        type_index = context.typedefs.length
        typedefs_context = Context.new(typedefs: [{ parameters:, results: }])
        context = context + typedefs_context
        generated_type = Type.new(name: nil, parameters:, results:)
      end
    elsif [parameters, results].all?(&:empty?)
      context.typedefs.slice(type_index) => { parameters: }
    end
    local_names, locals = [], []
    parse_locals.each do |local_name, local|
      local_names << local_name
      locals << local
    end
    locals_context = Context.new(locals: parameters.map(&:name) + local_names)
    body = parse_instructions(context: context + locals_context)

    [
      Function.new(exported_name:, type_index:, locals:, body:),
      context,
      generated_type
    ]
  end

  def parse_export
    if can_read_list?(starting_with: 'export')
      read_list(starting_with: 'export') { read }
    end
  end

  def parse_typeuse(context:)
    if can_read_list?(starting_with: 'type')
      index = read_list(starting_with: 'type') { parse_index }
      if index.is_a?(String)
        index = context.types.index(index) || raise
      end
    end
    parameters = parse_parameters
    results = parse_results

    [index, parameters, results]
  end

  INDEX_REGEXP = %r{\A(\d+|\$.+)\z}

  def parse_index
    read => INDEX_REGEXP => index
    if index.start_with?('$')
      index
    else
      index.to_i(10)
    end
  end

  def parse_memory
    read => 'memory'
    if can_read_list?(starting_with: 'data')
      string = read_list { parse_memory_data }
    else
      parse_memory_sizes => [minimum_size, maximum_size]
    end

    Memory.new(string:, minimum_size:, maximum_size:)
  end

  def parse_memory_data
    read => 'data'
    repeatedly { parse_string }.join
  end

  def parse_memory_sizes
    case repeatedly { parse_integer(bits: 32) }
    in [minimum_size]
      [minimum_size, nil]
    in [minimum_size, maximum_size]
      [minimum_size, maximum_size]
    end
  end

  def parse_table(context:)
    read => 'table'
    if peek in ID_REGEXP
      read => ID_REGEXP => name
    end
    repeatedly(until: -> { !%r{\A\d+\z}.match(_1) }) do
      parse_integer(bits: 32)
    end

    read => 'funcref'
    elements = parse_elements(context:)

    Table.new(name:, elements:)
  end

  def parse_elements(context:)
    if can_read_list?(starting_with: 'elem')
      read_list(starting_with: 'elem') do
        repeatedly { context.functions.index(read) }
      end
    else
      []
    end
  end

  def parse_global(context:)
    read => 'global'
    if peek in ID_REGEXP
      read => ID_REGEXP
    end
    read_list(starting_with: 'mut') { read }
    value = parse_instructions(context:)

    Global.new(value:)
  end

  NUMERIC_OPCODE_REGEXP =
    %r{
      \A
      (?<type>[fi]) (?<bits>32|64) \. (?<operation>.+)
      \z
    }x

  def parse_instructions(context:)
    repeatedly do
      if can_read_list?
        parse_folded_instruction(context:)
      else
        [parse_instruction(context:)]
      end
    end.flatten(1)
  end

  def read_list(from: read, starting_with: nil)
    raise unless from in [*]
    previous_s_expression, self.s_expression = self.s_expression, from

    read => ^starting_with unless starting_with.nil?

    yield.tap do
      raise unless finished?
      self.s_expression = previous_s_expression
    end
  end

  def parse_instruction(context:)
    case peek
    in NUMERIC_OPCODE_REGEXP
      parse_numeric_instruction
    in 'block' | 'loop' | 'if'
      parse_structured_instruction(context:)
    else
      parse_normal_instruction(context:)
    end
  end

  def parse_folded_instruction(context:)
    read_list do
      case peek
      in 'block' | 'loop' | 'if'
        parse_folded_structured_instruction(context:)
      else
        parse_folded_plain_instruction(context:)
      end
    end
  end

  def parse_folded_structured_instruction(context:)
    read_labelled => [opcode, label]
    results = parse_results

    case opcode
    in 'block'
      body = parse_instructions(context:)
      [Block.new(label:, results:, body:)]
    in 'loop'
      body = parse_instructions(context:)
      [Loop.new(label:, results:, body:)]
    in 'if'
      condition = []
      until can_read_list?(starting_with: 'then')
        condition.concat(parse_folded_instruction(context:))
      end
      consequent =
        read_list(starting_with: 'then') do
          parse_instructions(context:)
        end
      alternative =
        if can_read_list?(starting_with: 'else')
          read_list(starting_with: 'else') do
            parse_instructions(context:)
          end
        else
          []
        end
      [*condition, If.new(label:, results:, consequent:, alternative:)]
    end
  end

  def parse_folded_plain_instruction(context:)
    parse_instructions(context:) => [first, *rest]
    [*rest, first]
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

  def parse_structured_instruction(context:)
    read_labelled => [opcode, label]
    results = parse_results

    read_list(from: read_until('end')) do
      case opcode
      in 'block'
        body = parse_instructions(context:)
        Block.new(label:, results:, body:)
      in 'loop'
        body = parse_instructions(context:)
        Loop.new(label:, results:, body:)
      in 'if'
        consequent = parse_consequent(context:)
        read_labelled('else', label:) if peek in 'else'
        alternative = parse_alternative(context:)

        If.new(label:, results:, consequent:, alternative:)
      end
    end.tap do
      read_labelled('end', label:)
    end
  end

  def parse_consequent(context:)
    read_list(from: read_until('else')) do
      parse_instructions(context:)
    end
  end

  def parse_alternative(context:)
    parse_instructions(context:)
  end

  def read_labelled(atom = nil, label: nil)
    if atom.nil?
      read => atom
    else
      read => ^atom
    end

    if peek in ID_REGEXP
      if label.nil?
        read => ID_REGEXP => label
      else
        read => ^label
      end
    end

    [atom, label]
  end

  def parse_normal_instruction(context:)
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
      index = parse_index

      if index.is_a?(String)
        index =
          case opcode
          in 'local.get' | 'local.set' | 'local.tee'
            context.locals.index(index) || raise
          in 'global.get' | 'global.set'
            context.globals.index(index) || raise
          in 'call'
            context.functions.index(index) || raise
          else
            index
          end
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
        repeatedly(until: -> { can_read_list? || !INDEX_REGEXP.match(_1) }) do
          parse_index
        end
      indexes => [*target_indexes, default_index]

      BrTable.new(target_indexes:, default_index:)
    in 'call_indirect'
      table_index =
        if peek in INDEX_REGEXP
          parse_index
        else
          0
        end
      type_index =
        if can_read_list?(starting_with: 'type')
          read_list(starting_with: 'type') do
            parse_index
          end
        end
      while can_read_list?(starting_with: 'param')
        read_list(starting_with: 'param') do
          repeatedly { read }
        end
      end
      while can_read_list?(starting_with: 'result')
        read_list(starting_with: 'result') do
          repeatedly { read }
        end
      end

      CallIndirect.new(table_index:, type_index:)
    in 'select'
      if can_read_list?(starting_with: 'result')
        read_list(starting_with: 'result') do
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
