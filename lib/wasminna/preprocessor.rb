module Wasminna
  class Preprocessor
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

    attr_accessor :fresh_id

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
        [process_function(field)]
      in ['type', *]
        [process_type(field)]
      in ['import', *]
        [process_import(field)]
      else
        [field]
      end
    end

    def process_function(function)
      case function
      in ['func', ID_REGEXP => id, *definition]
        typeuse = process_typeuse(definition)
        locals = process_locals(definition)
        body = process_instructions(definition)
        ['func', id, *typeuse, *locals, *body]
      in ['func', *definition]
        typeuse = process_typeuse(definition)
        locals = process_locals(definition)
        body = process_instructions(definition)
        ['func', *typeuse, *locals, *body]
      end
    end

    def process_typeuse(definition)
      if definition in [['type', *], *]
        type = [definition.shift]
      end
      parameters = process_parameters(definition)
      results = process_results(definition)

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

    def process_instructions(instructions)
      instructions.flat_map do |instruction|
        case instruction
        in ['param' | 'result' => kind, *types]
          types.map { |type| [kind, type] }
        in [*]
          [process_instructions(instruction)]
        else
          [instruction]
        end
      end
    end

    def process_type(type)
      case type
      in ['type', ID_REGEXP => id, definition]
        ['type', id, process_functype(definition)]
      in ['type', definition]
        ['type', process_functype(definition)]
      end
    end

    def process_functype(definition)
      definition.shift => 'func'
      parameters = process_parameters(definition)
      results = process_results(definition)

      ['func', *parameters, *results]
    end

    def process_import(import)
      import => ['import', module_name, name, descriptor]
      ['import', module_name, name, process_import_descriptor(descriptor)]
    end

    def process_import_descriptor(descriptor)
      case descriptor
      in ['func', ID_REGEXP => id, *typeuse]
        ['func', id, *process_typeuse(typeuse)]
      in ['func', *typeuse]
        ['func', *process_typeuse(typeuse)]
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
