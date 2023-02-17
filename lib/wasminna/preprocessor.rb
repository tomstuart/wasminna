module Wasminna
  class Preprocessor
    def process_script(s_expression)
      s_expression.map do |command|
        process_command(command)
      end
    end

    private

    def process_command(command)
      case command.first
      in 'module'
        process_module(command)
      else
        command
      end
    end

    def process_module(mod)
      mod => ['module', *fields]
      fields in [String => id, *fields]

      [
        'module',
        *id,
        *fields.map do |field|
          process_field(field)
        end
      ]
    end

    def process_field(field)
      case field
      in ['func' | 'table' | 'memory' | 'global' => kind, String => id, ['import', module_name, name], *description]
        ['import', module_name, name, [kind, id, *description]]
      in ['func' | 'table' | 'memory' | 'global' => kind, ['import', module_name, name], *description]
        ['import', module_name, name, [kind, *description]]
      else
        field
      end
    end
  end
end
