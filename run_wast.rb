require 'wasminna/ast_parser'
require 'wasminna/interpreter'
require 'wasminna/preprocessor'
require 'wasminna/s_expression_parser'

s_expression = Wasminna::SExpressionParser.new.parse(ARGF.read)
desugared_s_expression = Wasminna::Preprocessor.new.process_script(s_expression)
script = Wasminna::ASTParser.new.parse_script(desugared_s_expression)
Wasminna::Interpreter.new.evaluate_script(script)
puts
