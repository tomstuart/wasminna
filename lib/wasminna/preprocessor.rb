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
      in 'table' | 'memory' | 'global'
        process_table_memory_global_definition
      in 'type'
        process_type_definition
      in 'import'
        process_import
      else
        [repeatedly { read }]
      end
    end

    def process_function_definition
      case s_expression
      in ['func', ID_REGEXP, ['import', _, _], *] | ['func', ['import', _, _], *]
        read => 'func'
        expand_inline_import(kind: 'func')
      in ['func', ID_REGEXP, ['export', _], *] | ['func', ['export', _], *]
        read => 'func'
        expand_inline_export(kind: 'func')
      else
        read => 'func'
        if peek in ID_REGEXP
          read => ID_REGEXP => id
        end
        typeuse = process_typeuse
        locals = process_locals
        body = process_instructions

        [
          ['func', *id, *typeuse, *locals, *body]
        ]
      end
    end

    def process_table_memory_global_definition
      case s_expression
      in ['table' | 'memory' | 'global', ID_REGEXP, ['import', _, _], *] | ['table' | 'memory' | 'global', ['import', _, _], *]
        read => 'table' | 'memory' | 'global' => kind
        expand_inline_import(kind:)
      in ['table' | 'memory' | 'global', ID_REGEXP, ['export', _], *] | ['table' | 'memory' | 'global', ['export', _], *]
        read => 'table' | 'memory' | 'global' => kind
        expand_inline_export(kind:)
      else
        [repeatedly { read }]
      end
    end

    def expand_inline_import(kind:)
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      read => ['import', module_name, name]
      description = repeatedly { read }

      [
        ['import', module_name, name, [kind, *id, *description]]
      ]
    end

    def expand_inline_export(kind:)
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      else
        id = "$__fresh_#{fresh_id}" # TODO find a better way
        self.fresh_id += 1
      end
      read => ['export', name]
      expanded =
        [
          ['export', name, [kind, id]],
          [kind, id, *repeatedly { read }]
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
