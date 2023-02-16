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

      [
        'module',
        *fields.map do |field|
          process_field(field)
        end
      ]
    end

    def process_field(field)
      case field
      in ['func', *id, ['import', module_name, name], typeuse]
        ['import', module_name, name, ['func', *id, typeuse]]
      else
        field
      end
    end
  end
end
