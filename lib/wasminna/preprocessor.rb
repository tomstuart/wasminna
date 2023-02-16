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
      in ['func', *rest]
        rest in [String => id, *rest]
        case rest
        in [['import', module_name, name], typeuse]
          ['import', module_name, name, ['func', *id, typeuse]]
        else
          field
        end
      in ['table', *rest]
        rest in [String => id, *rest]
        case rest
        in [['import', module_name, name], *tabletype]
          ['import', module_name, name, ['table', *id, *tabletype]]
        else
          field
        end
      in ['memory', *rest]
        rest in [String => id, *rest]
        case rest
        in [['import', module_name, name], *memtype]
          ['import', module_name, name, ['memory', *id, *memtype]]
        else
          field
        end
      else
        field
      end
    end
  end
end
