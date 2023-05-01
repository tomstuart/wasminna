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
      [].tap do |typeuse|
        if definition in [['type', *], *]
          typeuse.push(definition.shift)
        end

        while definition in [['param', *], *]
          param = definition.shift
          case param
          in ['param', ID_REGEXP => id, type]
            typeuse.push(param)
          in ['param', *types]
            types.each do |type|
              typeuse.push(['param', type])
            end
          end
        end

        while definition in [['result', *], *]
          result = definition.shift
          case result
          in ['result', *types]
            types.each do |type|
              typeuse.push(['result', type])
            end
          end
        end
      end
    end

    def process_locals(definition)
      [].tap do |locals|
        while definition in [['local', *], *]
          local = definition.shift
          case local
          in ['local', ID_REGEXP => id, type]
            locals.push(local)
          in ['local', *types]
            types.each do |type|
              locals.push(['local', type])
            end
          end
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
      [].tap do |functype|
        definition.shift => 'func'
        functype.push('func')

        while definition in [['param', *], *]
          param = definition.shift
          case param
          in ['param', ID_REGEXP => id, type]
            functype.push(param)
          in ['param', *types]
            types.each do |type|
              functype.push(['param', type])
            end
          end
        end

        while definition in [['result', *], *]
          result = definition.shift
          case result
          in ['result', *types]
            types.each do |type|
              functype.push(['result', type])
            end
          end
        end
      end
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
