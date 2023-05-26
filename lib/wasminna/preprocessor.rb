require 'wasminna/helpers'

module Wasminna
  class Preprocessor
    include Helpers::ReadFromSExpression

    def initialize
      self.fresh_id = 0
    end

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

    ID_REGEXP = %r{\A\$}

    attr_accessor :fresh_id, :s_expression

    def can_read_field?
      peek in ['type' | 'import' | 'func' | 'table' | 'memory' | 'global' | 'export' | 'start' | 'elem' | 'data', *]
    end

    def expand_inline_module
      fields =
        [].tap do |fields|
          while can_read_field?
            fields.push(read)
          end
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

    def process_module
      read => 'module'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end

      if peek in 'binary'
        read => 'binary'
        strings = repeatedly { read }
        ['module', *id, 'binary', *strings]
      else
        fields = process_fields
        ['module', *id, *fields]
      end
    end

    def process_fields
      repeatedly do
        read_list { process_field }
      end.flatten(1)
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
        process_type_definition
      in 'import'
        process_import
      in 'elem'
        process_element_segment
      else
        [repeatedly { read }]
      end
    end

    def process_function_definition
      read => 'func'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'func', id:)
      else
        typeuse = process_typeuse
        locals = process_locals
        body = process_instructions

        [
          ['func', *id, *typeuse, *locals, *body]
        ]
      end
    end

    def process_table_definition
      read => 'table'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'table', id:)
      else
        rest = repeatedly { read }

        [
          ['table', *id, *rest]
        ]
      end
    end

    def process_memory_definition
      read => 'memory'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'memory', id:)
      else
        rest = repeatedly { read }

        [
          ['memory', *id, *rest]
        ]
      end
    end

    def process_global_definition
      read => 'global'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end

      if can_read_inline_import_export?
        expand_inline_import_export(kind: 'global', id:)
      else
        rest = repeatedly { read }

        [
          ['global', *id, *rest]
        ]
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

      [
        ['import', module_name, name, [kind, *id, *description]]
      ]
    end

    def expand_inline_export(kind:, id:)
      read => ['export', name]
      description = repeatedly { read }

      if id.nil?
        id = "$__fresh_#{fresh_id}" # TODO find a better way
        self.fresh_id += 1
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

      [*type, *parameters, *results]
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
      [].tap do |declarations|
        while can_read_list?(starting_with: kind)
          declarations.concat(
            read_list(starting_with: kind) do
              if peek in ID_REGEXP
                read => ID_REGEXP => id
                read => type
                [[kind, id, type]]
              else
                repeatedly do
                  read => type
                  [kind, type]
                end
              end
            end
          )
        end
      end
    end

    def process_instructions
      repeatedly do
        if can_read_list?
          read_list do
            case peek
            in 'param' | 'result'
              read => 'param' | 'result' => kind
              repeatedly do
                read => type
                [kind, type]
              end
            else
              [process_instructions]
            end
          end
        else
          [read]
        end
      end.flatten(1)
    end

    def process_type_definition
      read => 'type'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      functype = read_list { process_functype }

      [
        ['type', *id, functype]
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

      [
        ['import', module_name, name, descriptor]
      ]
    end

    def process_import_descriptor
      case peek
      when 'func'
        read => 'func'
        if peek in ID_REGEXP
          read => ID_REGEXP => id
        end

        ['func', *id, *process_typeuse]
      else
        repeatedly { read }
      end
    end

    def process_element_segment
      read => 'elem'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      rest = repeatedly { read }

      [
        ['elem', *id, *rest]
      ]
    end

    def process_assert_trap
      read => 'assert_trap'

      if can_read_list?(starting_with: 'module')
        mod = read_list { process_module }
        read => failure

        ['assert_trap', mod, failure]
      else
        ['assert_trap', *repeatedly { read }]
      end
    end
  end
end
