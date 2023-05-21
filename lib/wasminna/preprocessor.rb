require 'wasminna/helpers'

module Wasminna
  class Preprocessor
    include Helpers::ReadFromSExpression

    def initialize
      self.fresh_id = 0
    end

    def process_script(s_expression)
      [].tap do |result|
        until s_expression.empty?
          inline_module = []
          while s_expression in [['type' | 'import' | 'func' | 'table' | 'memory' | 'global' | 'export' | 'start' | 'elem' | 'data', *], *]
            inline_module.push(s_expression.shift)
          end

          command =
            if inline_module.empty?
              s_expression.shift
            else
              ['module', *inline_module]
            end
          result.push(process_command(command))
        end
      end
    end

    private

    ID_REGEXP = %r{\A\$}

    attr_accessor :fresh_id, :s_expression

    def process_command(command)
      case command.first
      in 'module'
        process_module(command)
      in 'assert_trap'
        process_assert_trap(command)
      else
        command
      end
    end

    def process_module(mod)
      case mod
      in ['module', ID_REGEXP => id, *fields]
        read_list(from: fields) do
          ['module', id, *repeatedly { process_field(read) }.flatten(1)]
        end
      in ['module', *fields]
        read_list(from: fields) do
          ['module', *repeatedly { process_field(read) }.flatten(1)]
        end
      end
    end

    def process_field(field)
      if field in [*]
        case field
        in ['func' | 'table' | 'memory' | 'global', ID_REGEXP, ['import', _, _], *] | ['func' | 'table' | 'memory' | 'global', ['import', _, _], *]
          read_list(from: field) do
            expand_inline_import
          end
        in ['func' | 'table' | 'memory' | 'global', ID_REGEXP, ['export', _], *] | ['func' | 'table' | 'memory' | 'global', ['export', _], *]
          read_list(from: field) do
            expand_inline_export
          end
        else
          [
            read_list(from: field) do
              case peek
              in 'func'
                process_function
              in 'type'
                process_type
              in 'import'
                process_import
              else
                repeatedly { read }
              end
            end
          ]
        end
      else
        [field]
      end
    end

    def expand_inline_import
      read => 'func' | 'table' | 'memory' | 'global' => kind
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      read => ['import', module_name, name]
      description = repeatedly { read }

      [
        ['import', module_name, name, [kind, *id, *description]]
      ]
    end

    def expand_inline_export
      read => 'func' | 'table' | 'memory' | 'global' => kind
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      else
        id = "$__fresh_#{fresh_id}" # TODO find a better way
        self.fresh_id += 1
      end
      read => ['export', name]
      field = [kind, id, *repeatedly { read }]
      processed_field = read_list(from: [field]) { process_field(read) }

      [
        ['export', name, [kind, id]],
        *processed_field
      ]
    end

    def process_function
      read => 'func'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      typeuse = process_typeuse
      locals = process_locals
      body = process_instructions

      ['func', *id, *typeuse, *locals, *body]
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

    def process_type
      read => 'type'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      functype = read_list { process_functype }

      ['type', *id, functype]
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

      ['import', module_name, name, descriptor]
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

    def process_assert_trap(assertion)
      case assertion
      in ['assert_trap', ['module', *] => mod, failure]
        ['assert_trap', process_module(mod), failure]
      else
        assertion
      end
    end
  end
end
