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
        ['module', id, *fields.flat_map { process_field(_1) }]
      in ['module', *fields]
        ['module', *fields.flat_map { process_field(_1) }]
      end
    end

    def process_field(field)
      case field
      in ['func' | 'table' | 'memory' | 'global' => kind, ID_REGEXP => id, ['import', module_name, name], *description]
        [['import', module_name, name, [kind, id, *description]]]
      in ['func' | 'table' | 'memory' | 'global' => kind, ['import', module_name, name], *description]
        [['import', module_name, name, [kind, *description]]]
      in ['func' | 'table' | 'memory' | 'global' => kind, ID_REGEXP => id, ['export', name], *rest]
        [
          ['export', name, [kind, id]],
          *process_field([kind, id, *rest])
        ]
      in ['func' | 'table' | 'memory' | 'global' => kind, ['export', name], *rest]
        id = "$__fresh_#{fresh_id}" # TODO find a better way
        self.fresh_id += 1

        [
          ['export', name, [kind, id]],
          *process_field([kind, id, *rest])
        ]
      in ['func', *]
        read_list(from: field) do
          [process_function]
        end
      in ['type', *]
        [process_type(field)]
      in ['import', *]
        [process_import(field)]
      else
        [field]
      end
    end

    def process_function
      read => 'func'
      if peek in ID_REGEXP
        read => ID_REGEXP => id
      end
      typeuse = process_typeuse
      locals = process_locals(s_expression)
      body = process_instructions

      ['func', *id, *typeuse, *locals, *body]
    end

    def process_typeuse
      if can_read_list?(starting_with: 'type')
        type = [read]
      end
      parameters = process_parameters(s_expression)
      results = process_results(s_expression)

      [*type, *parameters, *results]
    end

    def process_parameters(definition)
      expand_anonymous_declarations(definition, kind: 'param')
    end

    def process_results(definition)
      expand_anonymous_declarations(definition, kind: 'result')
    end

    def process_locals(definition)
      expand_anonymous_declarations(definition, kind: 'local')
    end

    def expand_anonymous_declarations(s_expression, kind:)
      [].tap do |declarations|
        while s_expression in [[^kind, *], *]
          expanded_declarations =
            case s_expression.shift
            in [^kind, ID_REGEXP, _] => declaration
              [declaration]
            in [^kind, *types]
              types.map { |type| [kind, type] }
            end
          declarations.concat(expanded_declarations)
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

    def process_type(type)
      read_list(from: type) do
        read => 'type'

        if peek in ID_REGEXP
          read => ID_REGEXP => id
          functype = read_list { process_functype }
          ['type', id, functype]
        else
          functype = read_list { process_functype }
          ['type', functype]
        end
      end
    end

    def process_functype
      read => 'func'
      parameters = process_parameters(s_expression)
      results = process_results(s_expression)

      ['func', *parameters, *results]
    end

    def process_import(import)
      import => ['import', module_name, name, descriptor]
      ['import', module_name, name, process_import_descriptor(descriptor)]
    end

    def process_import_descriptor(descriptor)
      case descriptor
      in ['func', ID_REGEXP => id, *typeuse]
        read_list(from: typeuse) do
          ['func', id, *process_typeuse]
        end
      in ['func', *typeuse]
        read_list(from: typeuse) do
          ['func', *process_typeuse]
        end
      else
        descriptor
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
