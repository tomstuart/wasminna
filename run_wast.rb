require 'wasminna/ast_parser'
require 'wasminna/interpreter'
require 'wasminna/s_expression_parser'

s_expression = SExpressionParser.new.parse(ARGF.read)
script = ASTParser.new.parse_script(s_expression)
Interpreter.new.evaluate_script(script)
puts
