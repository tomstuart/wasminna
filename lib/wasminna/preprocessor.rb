require 'wasminna/helpers'
require 'wasminna/memory'

module Wasminna
  class Preprocessor
    include Helpers::ReadFromSExpression
    include Helpers::ReadIndex
    include Helpers::ReadOptionalId
    include Helpers::SizeOf
    include Helpers::StringValue

    def process_script(s_expression)
      read_list(from: s_expression) do
        repeatedly do
          if can_read_field?
            expand_inline_module
          else
            read_list { process_command }
          end
        end
      end
    end

    private

    attr_accessor :s_expression

    def can_read_field?
      peek in ['type' | 'import' | 'func' | 'table' | 'memory' | 'global' | 'export' | 'start' | 'elem' | 'data', *]
    end

    def expand_inline_module
      fields =
        repeatedly do
          raise StopIteration unless can_read_field?
          read
        end
      expanded = ['module', *fields]

      read_list(from: expanded) { process_command }
    end

    def process_command
      case peek
      in 'module'
        process_module
      in 'assert_trap'
        process_assert_trap
      else
        repeatedly { read }
      end
    end

    DUMMY_TYPE_DEFINITIONS = []

    def process_module
      read => 'module'
      read_optional_id => id

      if peek in 'binary'
        read => 'binary'
        strings = repeatedly { read }
        ['module', *id, 'binary', *strings]
      else
        fields = process_fields.call(DUMMY_TYPE_DEFINITIONS)
        ['module', *id, *fields]
      end
    end

    def process_fields
      repeatedly do
        read_list { process_field }
      end.then do |fields|
        after_all_fields do |type_definitions|
          fields.flat_map { |field| field.call(type_definitions) }
        end
      end
    end

    def process_field
      case peek
      in 'func'
        process_function_definition
      in 'table'
        process_table_definition
      in 'memory'
        process_memory_definition
      in 'global'
        process_global_definition
      in 'type'
        process_type_definition.first
      in 'import'
        process_import
      in 'elem'
        process_element_segment
      in 'data'
        process_data_segment
      in 'export' | 'start'
        process_unabbreviated_field
      end
    end

    def process_function_definition
      read => 'func'
      read_optional_id => id

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'func', id:)
      else
        typeuse = process_typeuse
        locals = process_locals
        body = process_instructions

        after_all_fields do |type_definitions|
          [
            ['func', *id, *typeuse.call(type_definitions), *locals, *body.call(type_definitions)]
          ]
        end
      end
    end

    def process_table_definition
      read => 'table'
      read_optional_id => id

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'table', id:)
      elsif can_read_inline_element_segment?
        expand_inline_element_segment(id:)
      else
        rest = repeatedly { read }

        after_all_fields do
          [
            ['table', *id, *rest]
          ]
        end
      end
    end

    def can_read_inline_element_segment?
      peek in 'funcref' | 'externref'
    end

    def expand_inline_element_segment(id:)
      read => 'funcref' | 'externref' => reftype
      item_type, items =
        read_list(starting_with: 'elem') do
          item_type =
            if can_read_list?
              reftype
            else
              'func'
            end
          items = repeatedly { read }
          [item_type, items]
        end

      if id.nil?
        id = fresh_id
      end
      limit = items.length.to_s
      expanded =
        [
          ['table', id, limit, limit, reftype],
          ['elem', ['table', id], %w[i32.const 0], item_type, *items]
        ]

      read_list(from: expanded) { process_fields }
    end

    def process_memory_definition
      read => 'memory'
      read_optional_id => id

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'memory', id:)
      elsif can_read_inline_data_segment?
        expand_inline_data_segment(id:)
      else
        rest = repeatedly { read }

        after_all_fields do
          [
            ['memory', *id, *rest]
          ]
        end
      end
    end

    def can_read_inline_data_segment?
      can_read_list?(starting_with: 'data')
    end

    def expand_inline_data_segment(id:)
      strings = read_list(starting_with: 'data') { repeatedly { read } }

      if id.nil?
        id = fresh_id
      end
      bytes = strings.sum { string_value(_1).bytesize }
      limit = size_of(bytes, in: Memory::BYTES_PER_PAGE).to_s
      expanded =
        [
          ['memory', id, limit, limit],
          ['data', ['memory', id], %w[i32.const 0], *strings]
        ]

      read_list(from: expanded) { process_fields }
    end

    def process_global_definition
      read => 'global'
      read_optional_id => id

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'global', id:)
      else
        read => type
        instructions = process_instructions

        after_all_fields do |type_definitions|
          [
            ['global', *id, type, *instructions.call(type_definitions)]
          ]
        end
      end
    end

    def can_read_inline_import_export?
      peek in ['import', _, _] | ['export', _]
    end

    def expand_inline_import_export(**)
      case peek
      in ['import', _, _]
        expand_inline_import(**)
      in ['export', _]
        expand_inline_export(**)
      end
    end

    def expand_inline_import(kind:, id:)
      read => ['import', module_name, name]
      description = repeatedly { read }

      expanded =
        [
          ['import', module_name, name, [kind, *id, *description]]
        ]

      read_list(from: expanded) { process_fields }
    end

    def expand_inline_export(kind:, id:)
      read => ['export', name]
      description = repeatedly { read }

      if id.nil?
        id = fresh_id
      end
      expanded =
        [
          ['export', name, [kind, id]],
          [kind, id, *description]
        ]

      read_list(from: expanded) { process_fields }
    end

    def process_typeuse
      if can_read_list?(starting_with: 'type')
        type = [read]
      end
      parameters = process_parameters
      results = process_results

      after_all_fields do
        [*type, *parameters, *results]
      end
    end

    def process_parameters
      expand_anonymous_declarations(kind: 'param')
    end

    def process_results
      expand_anonymous_declarations(kind: 'result')
    end

    def process_locals
      expand_anonymous_declarations(kind: 'local')
    end

    def expand_anonymous_declarations(kind:)
      repeatedly do
        raise StopIteration unless can_read_list?(starting_with: kind)
        read_list(starting_with: kind) do
          read_optional_id => id
          if id.nil?
            repeatedly do
              read => type
              [kind, type]
            end
          else
            read => type
            [[kind, id, type]]
          end
        end
      end.flatten(1)
    end

    def process_instructions
      repeatedly do
        case peek
        in 'block' | 'loop' | 'if'
          read => 'block' | 'loop' | 'if' => kind
          read_optional_id => id
          blocktype = process_blocktype

          after_all_fields do |type_definitions|
            [kind, *id, *blocktype.call(type_definitions)]
          end
        in 'call_indirect'
          read => 'call_indirect'
          if can_read_index?
            read_index => index
          end
          typeuse = process_typeuse

          after_all_fields do |type_definitions|
            ['call_indirect', *index, *typeuse.call(type_definitions)]
          end
        in 'select'
          read => 'select'
          results = process_results

          after_all_fields do
            ['select', *results]
          end
        in [*]
          read_list { process_instructions }.then do |result|
            after_all_fields do |type_definitions|
              [result.call(type_definitions)]
            end
          end
        else
          read.then do |result|
            after_all_fields do
              [result]
            end
          end
        end
      end.then do |results|
        after_all_fields do |type_definitions|
          results.flat_map { |result| result.call(type_definitions) }
        end
      end
    end

    def process_blocktype
      type =
        if can_read_list?(starting_with: 'type')
          [read]
        end
      parameters = process_parameters
      results = process_results
      blocktype = [*type, *parameters, *results]

      case blocktype
      in [] | [['result', _]]
        after_all_fields do
          blocktype
        end
      else
        read_list(from: blocktype) { process_typeuse }
      end
    end

    def process_instruction
      process_instructions # TODO only process one instruction
    end

    def process_type_definition
      read => 'type'
      read_optional_id => id
      functype = read_list { process_functype }

      [
        after_all_fields do
          [
            ['type', *id, functype]
          ]
        end,
        DUMMY_TYPE_DEFINITIONS
      ]
    end

    def process_functype
      read => 'func'
      parameters = process_parameters
      results = process_results

      ['func', *parameters, *results]
    end

    def process_import
      read => 'import'
      read => module_name
      read => name
      descriptor = read_list { process_import_descriptor }

      after_all_fields do |type_definitions|
        [
          ['import', module_name, name, descriptor.call(type_definitions)]
        ]
      end
    end

    def process_import_descriptor
      case peek
      when 'func'
        read => 'func'
        read_optional_id => id
        typeuse = process_typeuse

        after_all_fields do |type_definitions|
          ['func', *id, *typeuse.call(type_definitions)]
        end
      else
        repeatedly { read }.then do |result|
          after_all_fields do
            result
          end
        end
      end
    end

    def process_element_segment
      read => 'elem'
      read_optional_id => id

      if can_read_list?
        process_active_element_segment(id:)
      elsif peek in 'declare'
        process_declarative_element_segment(id:)
      else
        process_passive_element_segment(id:)
      end
    end

    def process_active_element_segment(id:)
      table_use =
        if can_read_list?(starting_with: 'table')
          read
        end
      offset = read_list { process_offset }
      element_list = process_element_list(func_optional: table_use.nil?)

      if table_use.nil?
        table_use = %w[table 0]
      end

      after_all_fields do |type_definitions|
        [
          ['elem', *id, table_use, offset.call(type_definitions), *element_list.call(type_definitions)]
        ]
      end
    end

    def process_declarative_element_segment(id:)
      read => 'declare'
      element_list = process_element_list(func_optional: false)

      after_all_fields do |type_definitions|
        [
          ['elem', *id, 'declare', *element_list.call(type_definitions)]
        ]
      end
    end

    def process_passive_element_segment(id:)
      element_list = process_element_list(func_optional: false)

      after_all_fields do |type_definitions|
        [
          ['elem', *id, *element_list.call(type_definitions)]
        ]
      end
    end

    def process_offset
      instructions =
        if peek in 'offset'
          read => 'offset'
          process_instructions
        else
          process_instruction
        end

      after_all_fields do |type_definitions|
        ['offset', *instructions.call(type_definitions)]
      end
    end

    def process_element_list(func_optional:)
      if peek in 'funcref' | 'externref'
        read => 'funcref' | 'externref' => reftype
        items = process_element_expressions

        after_all_fields do |type_definitions|
          [reftype, *items.call(type_definitions)]
        end
      else
        if !func_optional || (peek in 'func')
          read => 'func'
        end
        items =
          read_list(from: process_function_indexes) do
            process_element_expressions
          end

        after_all_fields do |type_definitions|
          ['funcref', *items.call(type_definitions)]
        end
      end
    end

    def process_element_expressions
      repeatedly do
        read_list { process_element_expression }
      end.then do |results|
        after_all_fields do |type_definitions|
          results.map { |result| result.call(type_definitions) }
        end
      end
    end

    def process_element_expression
      instructions =
        if peek in 'item'
          read => 'item'
          process_instructions
        else
          process_instruction
        end

      after_all_fields do |type_definitions|
        ['item', *instructions.call(type_definitions)]
      end
    end

    def process_function_indexes
      indexes = repeatedly { read }

      indexes.map { |index| ['ref.func', index] }
    end

    def process_data_segment
      read => 'data'
      read_optional_id => id

      if can_read_list?
        process_active_data_segment(id:)
      else
        process_passive_data_segment(id:)
      end
    end

    def process_active_data_segment(id:)
      memory_use =
        if can_read_list?(starting_with: 'memory')
          read
        else
          %w[memory 0]
        end
      offset = read_list { process_offset }
      strings = repeatedly { read }

      after_all_fields do |type_definitions|
        [
          ['data', *id, memory_use, offset.call(type_definitions), *strings]
        ]
      end
    end

    def process_passive_data_segment(id:)
      rest = repeatedly { read }

      after_all_fields do
        [
          ['data', *id, *rest]
        ]
      end
    end

    def process_unabbreviated_field
      read => 'export' | 'start' => kind
      rest = repeatedly { read }

      after_all_fields do
        [
          [kind, *rest]
        ]
      end
    end

    def process_assert_trap
      read => 'assert_trap'

      if can_read_list?(starting_with: 'module')
        mod = read_list { process_module }
        read => failure

        ['assert_trap', mod, failure]
      else
        rest = repeatedly { read }

        ['assert_trap', *rest]
      end
    end

    def fresh_id
      # TODO find a better way
      @fresh_id_index ||= 0
      "$__fresh_#{@fresh_id_index}".tap do
        @fresh_id_index += 1
      end
    end

    def after_all_fields
      -> type_definitions { yield type_definitions }
    end
  end
end
