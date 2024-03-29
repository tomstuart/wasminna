require 'wasminna/ast'
require 'wasminna/float'
require 'wasminna/float/format'
require 'wasminna/helpers'

module Wasminna
  class ASTParser
    include AST
    include Helpers::Mask
    include Helpers::ReadFromSExpression
    include Helpers::ReadIndex
    include Helpers::ReadInstructions
    include Helpers::ReadOptionalId
    include Helpers::StringValue

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
      read_optional_id => name
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
      functions, memories, tables, globals, types, datas, exports, imports, elements =
        9.times.map { [] }
      start = nil

      { functions:, memories:, tables:, globals:, types:, datas:, exports:, imports:, elements:, start: }
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
      functions, memories, tables, globals, datas, exports, imports, elements =
        8.times.map { [] }
      start = nil
      context =
        read_list(from: Marshal.load(Marshal.dump(s_expression))) do
          build_initial_context
        end

      repeatedly do
        read_list do
          case peek
          in 'func'
            functions << parse_function_definition(context:)
          in 'memory'
            memories << parse_memory_definition
          in 'table'
            tables << parse_table_definition
          in 'global'
            globals << parse_global_definition(context:)
          in 'type'
            parse_type_definition
          in 'data'
            datas << parse_data_segment(context:)
          in 'export'
            exports << parse_export(context:)
          in 'import'
            imports << parse_import(context:)
          in 'elem'
            elements << parse_element_segment(context:)
          in 'start'
            start = parse_start_function(context:)
          end
        end
      end

      { functions:, memories:, tables:, globals:, datas:, exports:, imports:, elements:, start:, types: context.typedefs }
    end

    def build_initial_context
      repeatedly do
        read_list do
          case read
          in 'type'
            read_optional_id => name
            type =
              read_list(starting_with: 'func') do
                _, parameters = parse_parameters
                results = parse_results
                Type.new(parameters:, results:)
              end
            Context.new(types: [name], typedefs: [type])
          in 'func' | 'table' | 'memory' | 'global' | 'elem' | 'data' => field_name
            read_optional_id => name
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
              read_optional_id => name
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
      read_optional_id => module_name
      parse_string => name
      arguments =
        repeatedly do
          read_list { parse_instruction(context: Context.new) }
        end

      Invoke.new(module_name:, name:, arguments:)
    end

    def parse_get
      read => 'get'
      read_optional_id => module_name
      parse_string => name

      Get.new(module_name:, name:)
    end

    def parse_assert_return
      read => 'assert_return'
      action =
        read_list do
          case peek
          in 'invoke'
            parse_invoke
          in 'get'
            parse_get
          end
        end
      expecteds = parse_expecteds

      AssertReturn.new(action:, expecteds:)
    end

    def parse_assert_trap
      read => 'assert_trap'
      action =
        read_list do
          case peek
          in 'invoke'
            parse_invoke
          in 'get'
            parse_get
          in 'module'
            parse_module
          end
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
            parse_instruction(context: Context.new)
          end
        end
      end
    end

    def parse_float_expectation
      read => 'f32.const' | 'f64.const' => keyword
      bits = keyword.slice(%r{\d+}).to_i(10)

      if peek in 'nan:canonical' | 'nan:arithmetic'
        read => 'nan:canonical' | 'nan:arithmetic' => nan
        NanExpectation.new(nan:, bits:)
      else
        number = parse_float(bits:)
        Const.new(type: :float, bits:, number:)
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
      read_optional_id => name

      Register.new(module_name:, name:)
    end

    def parse_type_definition
      read => 'type'
      read_optional_id => name

      read_list do
        read => 'func'
        _, parameters = parse_parameters
        results = parse_results

        Type.new(parameters:, results:)
      end
    end

    def parse_parameters
      parse_declarations(kind: 'param')
    end

    def parse_results
      parse_declarations(kind: 'result').last
    end

    def parse_locals
      parse_declarations(kind: 'local')
    end

    def parse_declarations(kind:)
      repeatedly do
        raise StopIteration unless can_read_list?(starting_with: kind)
        read_list { parse_declaration(kind:) }
      end.transpose.then do |names = [], types = []|
        [names, types]
      end
    end

    def parse_declaration(kind:)
      read => ^kind
      read_optional_id => name
      read => type

      [name, type]
    end

    def parse_function_definition(context:)
      read => 'func'
      read_optional_id

      parse_typeuse(context:) => [type_index, parameter_names]
      local_names, locals = parse_locals
      locals_context = Context.new(locals: parameter_names + local_names)
      raise unless locals_context.well_formed?
      body = parse_instructions(context: context + locals_context)

      Function.new(type_index:, locals:, body:)
    end

    def parse_typeuse(context:)
      index = read_list(starting_with: 'type') { parse_index(context.types) }
      parameter_names, parameters = parse_parameters
      results = parse_results

      if [parameters, results].all?(&:empty?)
        context.typedefs.slice(index) => { parameters: }
        parameter_names = parameters.map { nil }
      end

      raise unless Context.new(locals: parameter_names).well_formed?
      [index, parameter_names]
    end

    def parse_index(index_space)
      read_index => index
      if index.start_with?('$')
        index_space.index(index) || raise
      elsif index.start_with?('0x')
        index.to_i(16)
      else
        index.to_i(10)
      end
    end

    def parse_memory_definition
      read => 'memory'
      read_optional_id
      parse_limits => [minimum_size, maximum_size]

      AST::Memory.new(minimum_size:, maximum_size:)
    end

    def parse_data_segment(context:)
      read => 'data'
      read_optional_id

      mode =
        if can_read_list?(starting_with: 'memory')
          index =
            read_list(starting_with: 'memory') do
              parse_index(context.mems)
            end
          offset =
            read_list(starting_with: 'offset') do
              parse_instructions(context:)
            end
          DataSegment::Mode::Active.new(index:, offset:)
        else
          DataSegment::Mode::Passive.new
        end
      string = repeatedly { parse_string }.join

      DataSegment.new(string:, mode:)
    end

    UNSIGNED_INTEGER_REGEXP =
      %r{
        \A
        (?:
          \d (?: _? \d)*
          |
          0x \h (?: _? \h)*
        )
        \z
      }x

    def parse_table_definition
      read => 'table'
      read_optional_id => name
      minimum_size, maximum_size, reftype = parse_tabletype

      Table.new(name:, minimum_size:, maximum_size:)
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

    def parse_global_definition(context:)
      read => 'global'
      read_optional_id

      parse_globaltype
      value = parse_instructions(context:)

      Global.new(value:)
    end

    def parse_globaltype
      if can_read_list?(starting_with: 'mut')
        read_list(starting_with: 'mut') { read }
      else
        read
      end
    end

    def parse_export(context:)
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

    def parse_import(context:)
      read => 'import'
      parse_string => module_name
      parse_string => name
      kind, type =
        read_list do
          read => 'func' | 'table' | 'memory' | 'global' => kind
          read_optional_id

          case kind
          in 'func'
            parse_typeuse(context:) => [type_index, _]
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

    def parse_element_segment(context:)
      read => 'elem'
      read_optional_id
      mode =
        if can_read_list?(starting_with: 'table')
          index =
            read_list(starting_with: 'table') do
              parse_index(context.tables)
            end
          offset =
            read_list(starting_with: 'offset') do
              parse_instructions(context:)
            end
          ElementSegment::Mode::Active.new(index:, offset:)
        elsif peek in 'declare'
          read => 'declare'
          ElementSegment::Mode::Declarative.new
        else
          ElementSegment::Mode::Passive.new
        end
      read => 'funcref' | 'externref' => reftype
      items =
        repeatedly do
          read_list(starting_with: 'item') do
            parse_instructions(context:)
          end
        end

      ElementSegment.new(items:, mode:)
    end

    def parse_start_function(context:)
      read => 'start'
      parse_index(context.functions)
    end

    NUMERIC_OPCODE_REGEXP =
      %r{
        \A
        (?<type>[fi]) (?<bits>32|64) \. (?<operation>.+)
        \z
      }x

    def parse_instructions(context:)
      repeatedly do
        parse_instruction(context:)
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

    def parse_numeric_instruction
      read => keyword

      keyword.match(NUMERIC_OPCODE_REGEXP) =>
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

    def parse_structured_instruction(context:)
      read => keyword
      read_optional_id => label
      type = parse_blocktype(context:)
      context = Context.new(labels: [label]) + context

      case keyword
      in 'block'
        body = read_instructions { parse_instructions(context:) }
        Block.new(type:, body:)
      in 'loop'
        body = read_instructions { parse_instructions(context:) }
        Loop.new(type:, body:)
      in 'if'
        consequent = read_instructions { parse_instructions(context:) }
        read => 'else'
        read_optional_id => nil | ^label
        alternative = read_instructions { parse_instructions(context:) }

        If.new(type:, consequent:, alternative:)
      end.tap do
        read => 'end'
        read_optional_id => nil | ^label
      end
    end

    def parse_blocktype(context:)
      if can_read_list?(starting_with: 'type')
        parse_typeuse(context:) => [type_index, parameter_names]
        raise unless parameter_names.all?(&:nil?)
        type_index
      else
        parse_results => [] | [_] => results
        results
      end
    end

    def parse_normal_instruction(context:)
      case read
      in 'return' | 'nop' | 'drop' | 'unreachable' | 'memory.grow' | 'memory.size' | 'memory.fill' | 'memory.copy' => keyword
        {
          'return' => Return,
          'nop' => Nop,
          'drop' => Drop,
          'unreachable' => Unreachable,
          'memory.grow' => MemoryGrow,
          'memory.size' => MemorySize,
          'memory.fill' => MemoryFill,
          'memory.copy' => MemoryCopy
        }.fetch(keyword).new
      in 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'br' | 'br_if' | 'call' | 'memory.init' | 'data.drop' | 'elem.drop' => keyword
        index_space =
          case keyword
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
        }.fetch(keyword).new(index:)
      in 'table.get' | 'table.set' | 'table.fill' | 'table.grow' | 'table.size' => keyword
        index = parse_index(context.tables)

        {
          'table.get' => TableGet,
          'table.set' => TableSet,
          'table.fill' => TableFill,
          'table.grow' => TableGrow,
          'table.size' => TableSize
        }.fetch(keyword).new(index:)
      in 'br_table'
        indexes =
          repeatedly do
            raise StopIteration unless can_read_index?
            parse_index(context.labels)
          end
        indexes => [*target_indexes, default_index]

        BrTable.new(target_indexes:, default_index:)
      in 'call_indirect'
        table_index = parse_index(context.tables)
        parse_typeuse(context:) => [type_index, parameter_names]
        raise unless parameter_names.all?(&:nil?)

        CallIndirect.new(table_index:, type_index:)
      in 'select'
        parse_results
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
        table_index = parse_index(context.tables)
        element_index = parse_index(context.elem)

        TableInit.new(table_index:, element_index:)
      in 'table.copy'
        destination_index = parse_index(context.tables)
        source_index = parse_index(context.tables)

        TableCopy.new(destination_index:, source_index:)
      in 'ref.is_null'
        RefIsNull.new
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
      format = Float::Format.for(bits:)
      Float.parse(read).encode(format:)
    end

    def parse_string
      string_value(read)
    end
  end
end
