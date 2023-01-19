require 'wasminna/ast'
require 'wasminna/float'
require 'wasminna/float/format'
require 'wasminna/helpers'

module Wasminna
  class ASTParser
    include AST
    include Helpers::Mask

    def parse_script(s_expression)
      read_list(from: s_expression) do
        parse_commands
      end
    end

    private

    attr_accessor :s_expression, :context

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
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end
      fields =
        case peek
        in 'binary'
          parse_binary_fields
        else
          parse_text_fields
        end

      Module.new(name:, **fields)
    end

    def parse_binary_fields
      # TODO
      repeatedly { read }

      { functions: [], memory: nil, tables: [], globals: [], types: [], datas: [], exports: [], imports: [] }
    end

    Context = Data.define(:types, :functions, :globals, :locals, :labels, :typedefs) do
      def initialize(types: [], functions: [], globals: [], locals: [], labels: [], typedefs: [])
        super
      end

      def +(other)
        index_spaces =
          to_h.merge(other.to_h) do |_, left, right|
            left + right
          end
        Context.new(**index_spaces)
      end

      def well_formed?
        to_h
          .reject { |key, _| key == :typedefs }
          .values.map(&:compact)
          .all? { |value| value.uniq.length == value.length }
      end
    end

    def parse_text_fields
      functions, memory, tables, globals, datas, exports, imports =
        [], nil, [], [], [], [], []
      initial_context =
        read_list(from: Marshal.load(Marshal.dump(s_expression))) do
          build_initial_context
        end

      with_context(initial_context) do
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
              parse_type
            in 'data'
              datas << parse_data
            in 'export'
              exports << parse_export
            in 'import'
              imports << parse_import
            end
          end
        end

        { functions:, memory:, tables:, globals:, datas:, exports:, imports:, types: context.typedefs }
      end
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
            type =
              read_list(starting_with: 'func') do
                _, parameters = unzip_pairs(parse_parameters)
                results = parse_results
                Type.new(parameters:, results:)
              end
            Context.new(types: [name], typedefs: [type])
          in 'data'
            repeatedly { read }
            Context.new
          in 'export'
            repeatedly { read }
            Context.new
          in 'import'
            repeatedly { read }
            Context.new
          end
        end
      end.inject(Context.new, :+).tap do |context|
        raise unless context.well_formed?
      end
    end

    def parse_invoke
      read => 'invoke'
      if peek in ID_REGEXP
        read => ID_REGEXP => module_name
      end
      read => name
      arguments = with_context(Context.new) { parse_instructions }

      Invoke.new(module_name:, name:, arguments:)
    end

    def parse_get
      read => 'get'
      if peek in ID_REGEXP
        read => ID_REGEXP => module_name
      end
      read => name

      Get.new(module_name:, name:)
    end

    def parse_assert_return
      read => 'assert_return'
      action =
        if can_read_list?(starting_with: 'invoke')
          read_list { parse_invoke }
        elsif can_read_list?(starting_with: 'get')
          read_list { parse_get }
        else
          raise
        end
      expecteds = parse_expecteds

      AssertReturn.new(action:, expecteds:)
    end

    def parse_expecteds
      repeatedly do
        read_list do
          case peek
          in 'f32.const' | 'f64.const'
            parse_float_expectation
          else
            with_context(Context.new) { parse_instructions }
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
        _, parameters = unzip_pairs(parse_parameters)
        results = parse_results

        Type.new(parameters:, results:)
      end
    end

    def parse_parameters
      read_lists(starting_with: 'param') { parse_parameter_or_local }
    end

    def parse_results
      read_lists(starting_with: 'result') { parse_result }
    end

    def parse_locals
      read_lists(starting_with: 'local') { parse_parameter_or_local }
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

    def parse_parameter_or_local
      read => 'param' | 'local'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
        read => type
        [[name, type]]
      else
        repeatedly { read }.map { |type| [nil, type] }
      end
    end

    def parse_result
      read => 'result'
      repeatedly { read }
    end

    def parse_function
      read => 'func'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      exported_names = []
      while can_read_list?(starting_with: 'export')
        exported_names << read_list(starting_with: 'export') { read }
      end

      if can_read_list?(starting_with: 'import')
        import_module_name, import_name =
          read_list(starting_with: 'import') do
            [read, read]
          end
        import = [import_module_name, import_name]
        parse_typeuse => [type_index, _]
      else
        parse_typeuse => [type_index, parameter_names]
        local_names, locals = unzip_pairs(parse_locals)
        locals_context = Context.new(locals: parameter_names + local_names)
        raise unless locals_context.well_formed?
        body, updated_typedefs =
          with_context(context + locals_context) do
            body = parse_instructions
            [body, context.typedefs]
          end
        self.context = context.with(typedefs: updated_typedefs)
      end

      Function.new(exported_names:, import:, type_index:, locals:, body:)
    end

    def parse_typeuse
      if can_read_list?(starting_with: 'type')
        index = read_list(starting_with: 'type') { parse_index(context.types) }
      end
      parameter_names, parameters = unzip_pairs(parse_parameters)
      results = parse_results

      if index.nil?
        generated_type = Type.new(parameters:, results:)
        index = context.typedefs.find_index(generated_type)

        if index.nil?
          index = context.typedefs.length
          self.context = context + Context.new(typedefs: [generated_type])
        end
      elsif [parameters, results].all?(&:empty?)
        context.typedefs.slice(index) => { parameters: }
        parameter_names = parameters.map { nil }
      end

      raise unless Context.new(locals: parameter_names).well_formed?
      [index, parameter_names]
    end

    INDEX_REGEXP = %r{\A(\d+|\$.+)\z}

    def parse_index(index_space)
      read => INDEX_REGEXP => index
      if index.start_with?('$')
        index_space.index(index) || raise
      else
        index.to_i(10)
      end
    end

    def parse_memory
      read => 'memory'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      exported_names = []
      while can_read_list?(starting_with: 'export')
        exported_names << read_list(starting_with: 'export') { read }
      end

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

    def parse_data
      read => 'data'
      offset = read_list { parse_instruction }
      string = repeatedly { parse_string }.join

      MemoryData.new(offset:, string:)
    end

    def parse_memory_sizes
      case repeatedly { parse_integer(bits: 32) }
      in [minimum_size]
        [minimum_size, nil]
      in [minimum_size, maximum_size]
        [minimum_size, maximum_size]
      end
    end

    def parse_table
      read => 'table'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end

      exported_names = []
      while can_read_list?(starting_with: 'export')
        exported_names << read_list(starting_with: 'export') { read }
      end

      repeatedly(until: -> { !%r{\A\d+\z}.match(_1) }) do
        parse_integer(bits: 32)
      end

      read => 'funcref'
      elements = parse_elements

      Table.new(name:, elements:)
    end

    def parse_elements
      if can_read_list?(starting_with: 'elem')
        read_list(starting_with: 'elem') do
          repeatedly { parse_index(context.functions) }
        end
      else
        []
      end
    end

    def parse_global
      read => 'global'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      exported_names = []
      while can_read_list?(starting_with: 'export')
        exported_names << read_list(starting_with: 'export') { read }
      end

      if can_read_list?(starting_with: 'import')
        import_module_name, import_name =
          read_list(starting_with: 'import') do
            [read, read]
          end
        import = [import_module_name, import_name]
        parse_globaltype
      else
        parse_globaltype
        value = parse_instructions
      end

      Global.new(import:, value:)
    end

    def parse_globaltype
      if can_read_list?(starting_with: 'mut')
        read_list(starting_with: 'mut') { read }
      else
        read
      end
    end

    def parse_export
      read => 'export'
      read => name
      kind, index =
        read_list do
          case read
          in 'func'
            [:func, parse_index(context.functions)]
          in 'global'
            [:global, parse_index(context.globals)]
          in 'table'
            [:table, read] # TODO parse_index(context.tables)
          in 'memory'
            [:memory, read] # TODO parse_index(context.memories)
          end
        end

      Export.new(name:, kind:, index:)
    end

    def parse_import
      # TODO
      repeatedly { read }
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

    def with_context(context)
      previous_context, self.context = self.context, context

      yield.tap do
        self.context = previous_context
      end
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
      read_list do
        case peek
        in 'block' | 'loop' | 'if'
          parse_folded_structured_instruction
        else
          parse_folded_plain_instruction
        end
      end
    end

    def parse_folded_structured_instruction
      read_labelled => [opcode, label]
      type = parse_blocktype

      with_context(Context.new(labels: [label]) + context) do
        case opcode
        in 'block'
          body = parse_instructions
          [Block.new(type:, body:)]
        in 'loop'
          body = parse_instructions
          [Loop.new(type:, body:)]
        in 'if'
          condition = []
          until can_read_list?(starting_with: 'then')
            condition.concat(parse_folded_instruction)
          end
          consequent =
            read_list(starting_with: 'then') do
              parse_instructions
            end
          alternative =
            if can_read_list?(starting_with: 'else')
              read_list(starting_with: 'else') do
                parse_instructions
              end
            else
              []
            end
          [*condition, If.new(type:, consequent:, alternative:)]
        end
      end
    end

    def parse_folded_plain_instruction
      parse_instructions => [first, *rest]
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
      in 'load' | 'load8_s' | 'load8_u' | 'load16_s' | 'load16_u' | 'load32_s' | 'load32_u' | 'store' | 'store8' | 'store16' | 'store32'
        offset =
          if peek in %r{\Aoffset=\d+\z}
            read => %r{\Aoffset=\d+\z} => offset
            offset.split('=') => [_, offset]
            offset.to_i(10)
          else
            0
          end
        align =
          if peek in %r{\Aalign=\d+\z}
            read => %r{\Aalign=\d+\z} => align
            align.split('=') => [_, align]
            align.to_i(10)
          else
            0
          end

        case operation
        in 'load' | 'load8_s' | 'load8_u' | 'load16_s' | 'load16_u' | 'load32_s' | 'load32_u'
          storage_size =
            operation.slice(%r{\d+}).then do |storage_size|
              if storage_size.nil?
                bits
              else
                storage_size.to_i(10)
              end
            end
          sign_extension_mode = operation.end_with?('_s') ? :signed : :unsigned

          Load.new(type:, bits:, storage_size:, sign_extension_mode:, offset:)
        in 'store' | 'store8' | 'store16' | 'store32'
          storage_size =
            operation.slice(%r{\d+}).then do |storage_size|
              if storage_size.nil?
                bits
              else
                storage_size.to_i(10)
              end
            end

          Store.new(type:, bits:, storage_size:, offset:)
        end
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
      read_labelled => [opcode, label]
      type = parse_blocktype

      read_list(from: read_until('end')) do
        with_context(Context.new(labels: [label]) + context) do
          case opcode
          in 'block'
            body = parse_instructions
            Block.new(type:, body:)
          in 'loop'
            body = parse_instructions
            Loop.new(type:, body:)
          in 'if'
            consequent = parse_consequent
            read_labelled('else', label:) if peek in 'else'
            alternative = parse_alternative

            If.new(type:, consequent:, alternative:)
          end
        end
      end.tap do
        read_labelled('end', label:)
      end
    end

    def parse_blocktype
      type_index, parameter_names, updated_typedefs =
        with_context(context) do
          parse_typeuse => [type_index, parameter_names]
          [type_index, parameter_names, context.typedefs]
        end
      raise unless parameter_names.all?(&:nil?)

      type = updated_typedefs.slice(type_index)
      if (
        type.parameters.none? &&
        (type.results.none? || type.results.one?) &&
        context.typedefs.find_index(type).nil?
      )
        type.results
      else
        self.context = context.with(typedefs: updated_typedefs)
        type_index
      end
    end

    def parse_consequent
      read_list(from: read_until('else')) do
        parse_instructions
      end
    end

    def parse_alternative
      parse_instructions
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

    def parse_normal_instruction
      case read
      in 'return' | 'nop' | 'drop' | 'unreachable' | 'memory.grow' | 'memory.size' => opcode
        {
          'return' => Return,
          'nop' => Nop,
          'drop' => Drop,
          'unreachable' => Unreachable,
          'memory.grow' => MemoryGrow,
          'memory.size' => MemorySize
        }.fetch(opcode).new
      in 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'br' | 'br_if' | 'call' => opcode
        index_space =
          case opcode
          in 'local.get' | 'local.set' | 'local.tee'
            context.locals
          in 'global.get' | 'global.set'
            context.globals
          in 'br' | 'br_if'
            context.labels
          in 'call'
            context.functions
          end
        index = parse_index(index_space)

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
            parse_index(context.labels)
          end
        indexes => [*target_indexes, default_index]

        BrTable.new(target_indexes:, default_index:)
      in 'call_indirect'
        table_index =
          if peek in INDEX_REGEXP
            parse_index(nil) # TODO context.tables
          else
            0
          end
        type_index =
          if can_read_list?(starting_with: 'type')
            read_list(starting_with: 'type') do
              parse_index(context.types)
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
      in 'ref.null'
        read
        RefNull.new
      in 'ref.extern'
        read
        RefExtern.new
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
      format = Float::Format.for(bits:)
      Float.parse(read).encode(format:)
    end

    def parse_string
      read => string
      encoding = string.encoding
      string.
        delete_prefix('"').delete_suffix('"').
        force_encoding(Encoding::ASCII_8BIT).
        gsub(%r{\\\h{2}}) do |digits|
          digits.delete_prefix('\\').to_i(16).chr(Encoding::ASCII_8BIT)
        end.
        force_encoding(encoding)
    end

    def unzip_pairs(pairs)
      pairs.transpose.then do |unzipped|
        if unzipped.empty?
          [[], []]
        else
          unzipped
        end
      end
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
end
