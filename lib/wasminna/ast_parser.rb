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
        in 'assert_trap'
          parse_assert_trap
        in 'assert_malformed' | 'assert_invalid' | 'assert_exhaustion' | 'assert_unlinkable'
          parse_unsupported_assertion
        in 'register'
          parse_register
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

      { functions: [], memory: nil, tables: [], globals: [], types: [], datas: [], exports: [], imports: [], elements: [], start: nil }
    end

    Context = Data.define(:types, :functions, :tables, :mems, :globals, :elem, :data, :locals, :labels, :typedefs) do
      def initialize(types: [], functions: [], tables: [], mems: [], globals: [], elem: [], data: [], locals: [], labels: [], typedefs: [])
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
      functions, memory, tables, globals, datas, exports, imports, elements, start =
        [], nil, [], [], [], [], [], [], nil
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
            in 'elem'
              elements << parse_element
            in 'start'
              start = parse_start
            end
          end
        end

        { functions:, memory:, tables:, globals:, datas:, exports:, imports:, elements:, start:, types: context.typedefs }
      end
    end

    def build_initial_context
      repeatedly do
        read_list do
          case read
          in 'type'
            if peek in ID_REGEXP
              read => ID_REGEXP => name
            end
            type =
              read_list(starting_with: 'func') do
                _, parameters = unzip_pairs(parse_parameters(desugared: true))
                results = parse_results(desugared: true)
                Type.new(parameters:, results:)
              end
            Context.new(types: [name], typedefs: [type])
          in 'func' | 'table' | 'memory' | 'global' | 'elem' | 'data' => field_name
            if peek in ID_REGEXP
              read => ID_REGEXP => name
            end
            repeatedly { read }
            index_space_name =
              {
                'func' => :functions,
                'table' => :tables,
                'memory' => :mems,
                'global' => :globals,
                'elem' => :elem,
                'data' => :data
              }.fetch(field_name)
            Context.new(index_space_name => [name])
          in 'import'
            2.times { read }
            read_list do
              read => 'func' | 'table' | 'memory' | 'global' => kind
              index_space_name =
                {
                  'func' => :functions,
                  'table' => :tables,
                  'memory' => :mems,
                  'global' => :globals
                }.fetch(kind)
              if peek in ID_REGEXP
                read => ID_REGEXP => name
              end
              repeatedly { read }
              Context.new(index_space_name => [name])
            end
          else
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
      parse_string => name
      arguments = with_context(Context.new) { parse_instructions }

      Invoke.new(module_name:, name:, arguments:)
    end

    def parse_get
      read => 'get'
      if peek in ID_REGEXP
        read => ID_REGEXP => module_name
      end
      parse_string => name

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

    def parse_assert_trap
      read => 'assert_trap'
      action =
        if can_read_list?(starting_with: 'invoke')
          read_list { parse_invoke }
        elsif can_read_list?(starting_with: 'get')
          read_list { parse_get }
        elsif can_read_list?(starting_with: 'module')
          read_list { parse_module }
        else
          raise
        end
      failure = parse_string

      AssertTrap.new(action:, failure:)
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

    def parse_register
      read => 'register'
      module_name = parse_string
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end

      Register.new(module_name:, name:)
    end

    ID_REGEXP = %r{\A\$}

    def parse_type
      read => 'type'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end

      read_list do
        read => 'func'
        _, parameters = unzip_pairs(parse_parameters(desugared: true))
        results = parse_results(desugared: true)

        Type.new(parameters:, results:)
      end
    end

    def parse_parameters(desugared:)
      read_lists(starting_with: 'param', desugared:) { parse_parameter(desugared:) }
    end

    def parse_results(desugared:)
      read_lists(starting_with: 'result', desugared:) { parse_result(desugared:) }
    end

    def parse_locals
      read_lists(starting_with: 'local', desugared: true) { parse_local }
    end

    def read_lists(starting_with:, desugared:)
      [].tap do |results|
        while can_read_list?(starting_with:)
          results << read_list { yield }
        end
      end
    end

    def parse_parameter(desugared:)
      read => 'param'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end
      read => type

      [name, type]
    end

    def parse_result(desugared:)
      read => 'result'
      read
    end

    def parse_local
      read => 'local'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end
      read => type

      [name, type]
    end

    def parse_function
      read => 'func'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      parse_typeuse(desugared: true) => [type_index, parameter_names]
      local_names, locals = unzip_pairs(parse_locals)
      locals_context = Context.new(locals: parameter_names + local_names)
      raise unless locals_context.well_formed?
      body, updated_typedefs =
        with_context(context + locals_context) do
          body = parse_instructions
          [body, context.typedefs]
        end
      self.context = context.with(typedefs: updated_typedefs)

      Function.new(type_index:, locals:, body:)
    end

    def parse_typeuse(desugared:)
      if can_read_list?(starting_with: 'type')
        index = read_list(starting_with: 'type') { parse_index(context.types) }
      end
      parameter_names, parameters = unzip_pairs(parse_parameters(desugared:))
      results = parse_results(desugared:)

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

    INDEX_REGEXP =
      %r{
        \A
        (
          \d (_? \d)*
          |
          0x \h (_? \h)*
          |
          \$ .+
        )
        \z
      }x

    def parse_index(index_space)
      read => INDEX_REGEXP => index
      if index.start_with?('$')
        index_space.index(index) || raise
      elsif index.start_with?('0x')
        index.to_i(16)
      else
        index.to_i(10)
      end
    end

    def parse_memory
      read => 'memory'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      if can_read_list?(starting_with: 'data')
        string = read_list { parse_memory_data }
      else
        parse_limits => [minimum_size, maximum_size]
      end

      Memory.new(string:, minimum_size:, maximum_size:)
    end

    def parse_memory_data
      read => 'data'
      repeatedly { parse_string }.join
    end

    def parse_data
      read => 'data'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      if can_read_list?
        if can_read_list?(starting_with: 'memory')
          read_list(starting_with: 'memory') do
            parse_index(context.mems)
          end
        end
        offset =
          read_list do
            case peek
            in 'offset'
              read => 'offset'
              parse_instructions
            else
              [parse_instruction]
            end
          end
      end
      string = repeatedly { parse_string }.join

      MemoryData.new(offset:, string:)
    end

    UNSIGNED_INTEGER_REGEXP =
      %r{
        \A
        (
          \d (_? \d)*
          |
          0x \h (_? \h)*
        )
        \z
      }x

    def parse_table
      read => 'table'
      if peek in ID_REGEXP
        read => ID_REGEXP => name
      end

      if peek in UNSIGNED_INTEGER_REGEXP
        minimum_size, maximum_size, reftype = parse_tabletype
      else
        read => 'funcref' | 'externref' => reftype
        elements = parse_table_element
      end

      Table.new(name:, minimum_size:, maximum_size:, elements:)
    end

    def parse_tabletype
      minimum_size, maximum_size = parse_limits
      read => 'funcref' | 'externref' => reftype

      [minimum_size, maximum_size, reftype]
    end

    def parse_limits
      raise unless peek in UNSIGNED_INTEGER_REGEXP
      minimum_size = parse_integer(bits: 32)
      maximum_size = parse_integer(bits: 32) if peek in UNSIGNED_INTEGER_REGEXP

      [minimum_size, maximum_size]
    end

    def parse_table_element
      read_list(starting_with: 'elem') do
        if can_read_list?
          repeatedly do
            read_list do
              case peek
              in 'item'
                read => 'item'
                parse_instructions
              else
                [parse_instruction]
              end
            end
          end
        else
          repeatedly { [RefFunc.new(index: parse_index(context.functions))] }
        end
      end
    end

    def parse_global
      read => 'global'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end

      parse_globaltype
      value = parse_instructions

      Global.new(value:)
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
      parse_string => name
      kind, index =
        read_list do
          case read
          in 'func'
            [:func, parse_index(context.functions)]
          in 'global'
            [:global, parse_index(context.globals)]
          in 'table'
            [:table, parse_index(context.tables)]
          in 'memory'
            [:memory, parse_index(context.mems)]
          end
        end

      Export.new(name:, kind:, index:)
    end

    def parse_import
      read => 'import'
      parse_string => module_name
      parse_string => name
      kind, type =
        read_list do
          read => 'func' | 'table' | 'memory' | 'global' => kind
          if peek in ID_REGEXP
            read => ID_REGEXP
          end

          case kind
          in 'func'
            parse_typeuse(desugared: true) => [type_index, _]
            [:func, type_index]
          in 'global'
            [:global, parse_globaltype]
          in 'memory'
            [:memory, parse_limits]
          in 'table'
            [:table, parse_tabletype]
          end
        end

      Import.new(module_name:, name:, kind:, type:)
    end

    def parse_element
      read => 'elem'
      if peek in ID_REGEXP
        read => ID_REGEXP
      end
      if peek in 'declare'
        read => 'declare'
      end
      index =
        if can_read_list?(starting_with: 'table')
          read_list(starting_with: 'table') do
            parse_index(context.tables)
          end
        end
      offset =
        if !index.nil? || can_read_list?
          read_list do
            case peek
            in 'offset'
              read => 'offset'
              parse_instructions
            else
              [parse_instruction]
            end
          end
        end
      reftype =
        if peek in 'funcref' | 'externref' | 'func'
          read
        elsif index.nil?
          'func'
        else
          raise
        end
      items =
        case reftype
        in 'funcref' | 'externref'
          repeatedly do
            read_list do
              case peek
              in 'item'
                read => 'item'
                parse_instructions
              else
                [parse_instruction]
              end
            end
          end
        in 'func'
          repeatedly { [RefFunc.new(index: parse_index(context.functions))] }
        end
      index ||= 0 unless offset.nil?

      Element.new(index:, offset:, items:)
    end

    def parse_start
      read => 'start'
      parse_index(context.functions)
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
      raise "not a list: #{from.inspect}" unless from in [*]
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
          if peek in %r{\Aoffset=(?:\d+|0x\h+)\z}
            read => %r{\Aoffset=(?:\d+|0x\h+)\z} => offset
            offset.split('=') => [_, offset]
            if offset.start_with?('0x')
              offset.to_i(16)
            else
              offset.to_i(10)
            end
          else
            0
          end
        align =
          if peek in %r{\Aalign=(?:\d+|0x\h+)\z}
            read => %r{\Aalign=(?:\d+|0x\h+)\z} => align
            align.split('=') => [_, align]
            if align.start_with?('0x')
              align.to_i(16)
            else
              align.to_i(10)
            end
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
          parse_typeuse(desugared: true) => [type_index, parameter_names]
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
      in 'return' | 'nop' | 'drop' | 'unreachable' | 'memory.grow' | 'memory.size' | 'memory.fill' | 'memory.copy' => opcode
        {
          'return' => Return,
          'nop' => Nop,
          'drop' => Drop,
          'unreachable' => Unreachable,
          'memory.grow' => MemoryGrow,
          'memory.size' => MemorySize,
          'memory.fill' => MemoryFill,
          'memory.copy' => MemoryCopy
        }.fetch(opcode).new
      in 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'br' | 'br_if' | 'call' | 'memory.init' | 'data.drop' | 'elem.drop' => opcode
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
          in 'memory.init' | 'data.drop'
            context.data
          in 'elem.drop'
            context.elem
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
          'call' => Call,
          'memory.init' => MemoryInit,
          'data.drop' => DataDrop,
          'elem.drop' => ElemDrop
        }.fetch(opcode).new(index:)
      in 'table.get' | 'table.set' | 'table.fill' | 'table.grow' | 'table.size' => opcode
        index =
          if peek in INDEX_REGEXP
            parse_index(context.tables)
          else
            0
          end

        {
          'table.get' => TableGet,
          'table.set' => TableSet,
          'table.fill' => TableFill,
          'table.grow' => TableGrow,
          'table.size' => TableSize
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
            parse_index(context.tables)
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
        while can_read_list?(starting_with: 'result')
          read_list(starting_with: 'result') do
            repeatedly { read }
          end
        end

        Select.new
      in 'ref.null'
        read
        RefNull.new
      in 'ref.extern'
        value = parse_integer(bits: 32)
        RefExtern.new(value:)
      in 'ref.func'
        index = parse_index(context.functions)
        RefFunc.new(index:)
      in 'table.init'
        read => INDEX_REGEXP => index
        if peek in INDEX_REGEXP
          table_index =
            if index.start_with?('$')
              context.tables.index(index) || raise
            elsif index.start_with?('0x')
              index.to_i(16)
            else
              index.to_i(10)
            end
          element_index = parse_index(context.elem)
        else
          table_index = 0
          element_index =
            if index.start_with?('$')
              context.elem.index(index) || raise
            elsif index.start_with?('0x')
              index.to_i(16)
            else
              index.to_i(10)
            end
        end

        TableInit.new(table_index:, element_index:)
      in 'table.copy'
        destination_index, source_index =
          if peek in INDEX_REGEXP
            [parse_index(context.tables), parse_index(context.tables)]
          else
            [0, 0]
          end

        TableCopy.new(destination_index:, source_index:)
      in 'ref.is_null'
        RefIsNull.new
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
