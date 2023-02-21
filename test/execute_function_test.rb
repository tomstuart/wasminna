source =
  <<~eos
    (module
      (func (export "add") (param i32 i32) (result i32)
        (i32.add (local.get 0) (local.get 1))
      )
    )
  eos
mod = Wasminna.load(source)
raise unless mod.add(2, 3) == 5
print "\e[32m.\e[0m"

source =
  <<~eos
    (module
      (func (export "dup") (param i32) (result i32 i32)
        local.get 0
        local.get 0
      )
    )
  eos
mod = Wasminna.load(source)
raise unless mod.dup(6) == [6, 6]
print "\e[32m.\e[0m"

puts

BEGIN {
  require 'wasminna/ast_parser'
  require 'wasminna/interpreter'
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  module Wasminna
    def self.load(source)
      s_expression = SExpressionParser.new.parse(source)
      desugared_s_expression = Preprocessor.new.process_script(s_expression)
      script = ASTParser.new.parse_script(desugared_s_expression)
      interpreter = Interpreter.new
      interpreter.evaluate_script(script)
      mod = interpreter.modules.first

      Object.new.tap do |instance|
        mod.exports.each do |key, value|
          if value.is_a?(Interpreter::Function)
            function = value
            type = mod.types.slice(function.definition.type_index)
            instance.define_singleton_method key do |*arguments|
              raise unless arguments.length == type.parameters.length
              interpreter.stack.push(*arguments)
              interpreter.send :invoke_function, function

              case type.results.length
              when 0
                nil
              when 1
                interpreter.stack.pop
              else
                interpreter.stack.pop(type.results.length)
              end
            end
          end
        end
      end
    end
  end
}
