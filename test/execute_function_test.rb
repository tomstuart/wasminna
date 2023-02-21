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

source =
  <<~eos
    (module
      (func (export "add") (param f32 f32) (result f32)
        (f32.add (local.get 0) (local.get 1))
      )
    )
  eos
mod = Wasminna.load(source)
raise unless mod.add(2.0, 3.0) == 5.0
print "\e[32m.\e[0m"

puts

BEGIN {
  require 'wasminna/ast_parser'
  require 'wasminna/float'
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
              arguments =
                arguments.zip(type.parameters).map do |value, type|
                  Wasminna.to_webassembly_value(value, type:)
                end
              interpreter.stack.push(*arguments)
              interpreter.send :invoke_function, function

              case type.results.length
              when 0
                nil
              when 1
                result = interpreter.stack.pop
                Wasminna.from_webassembly_value(result, type: type.results.first)
              else
                results = interpreter.stack.pop(type.results.length)
                results.zip(type.results).map do |value, type|
                  Wasminna.from_webassembly_value(value, type:)
                end
              end
            end
          end
        end
      end
    end

    def self.to_webassembly_value(value, type:)
      case type
      in 'i32'
        value
      in 'f32'
        Float.from_float(value).encode(format: Float::Format::Single)
      end
    end

    def self.from_webassembly_value(value, type:)
      case type
      in 'i32'
        value
      in 'f32'
        Float.decode(value, format: Float::Format::Single).to_f
      end
    end
  end
}
