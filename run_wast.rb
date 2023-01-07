require 'wasminna/ast_parser'
require 'wasminna/interpreter'
require 'wasminna/s_expression_parser'

s_expression = Wasminna::SExpressionParser.new.parse(ARGF.read)
script = Wasminna::ASTParser.new.parse_script(s_expression)
Wasminna::Interpreter.new.evaluate_script(script)
puts
