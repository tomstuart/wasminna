source =
  <<~eos
    (module
      (func (export "add") (param i32 i32) (result i32)
        (i32.add (local.get 0) (local.get 1))
      )
    )
  eos
raise unless execute(source, 'add', [2, 3]) == 5
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
raise unless execute(source, 'dup', [6]) == [6, 6]
print "\e[32m.\e[0m"

puts

BEGIN {
  require 'wasminna/ast_parser'
  require 'wasminna/interpreter'
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  def execute(source, function_name, arguments)
    s_expression = Wasminna::SExpressionParser.new.parse(source)
    desugared_s_expression = Wasminna::Preprocessor.new.process_script(s_expression)
    script = Wasminna::ASTParser.new.parse_script(desugared_s_expression)
    interpreter = Wasminna::Interpreter.new
    interpreter.evaluate_script(script)
    mod = interpreter.modules.first
    function = mod.exports.fetch(function_name)
    type = mod.types.slice(function.definition.type_index)

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
}
