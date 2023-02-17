module Wasminna
  class Preprocessor
    def initialize
      self.fresh_id = 0
    end

    def process_script(s_expression)
      s_expression.map do |command|
        process_command(command)
      end
    end

    private

    attr_accessor :fresh_id

    def process_command(command)
      case command.first
      in 'module'
        process_module(command)
      else
        command
      end
    end

    def process_module(mod)
      case mod
      in ['module', String => id, *fields]
        ['module', id, *fields.flat_map { process_field(_1) }]
      in ['module', *fields]
        ['module', *fields.flat_map { process_field(_1) }]
      end
    end

    def process_field(field)
      case field
      in ['func' | 'table' | 'memory' | 'global' => kind, String => id, ['import', module_name, name], *description]
        [['import', module_name, name, [kind, id, *description]]]
      in ['func' | 'table' | 'memory' | 'global' => kind, ['import', module_name, name], *description]
        [['import', module_name, name, [kind, *description]]]
      in ['func' | 'table' | 'memory' | 'global' => kind, String => id, ['export', name], *rest]
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
      else
        [field]
      end
    end
  end
end
