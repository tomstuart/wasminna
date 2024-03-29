source = <<'--'
  (module
    (func (export "add") (param i32 i32) (result i32)
      (i32.add (local.get 0) (local.get 1))
    )
  )
--
assert_execute source, :add, [2, 3], 5

source = <<'--'
  (module
    (func (export "dup") (param i32) (result i32 i32)
      local.get 0
      local.get 0
    )
  )
--
assert_execute source, :dup, 6, [6, 6]

source = <<'--'
  (module
    (func (export "add") (param f32 f32) (result f32)
      (f32.add (local.get 0) (local.get 1))
    )
  )
--
assert_execute source, :add, [2.0, 3.0], 5.0

source = <<'--'
  (module
    (func (export "add") (param i32 i32) (result i32)
      (i32.add (local.get 0) (local.get 1))
    )
  )
--
assert_execute source, :add, [-2, 3], 1

source = <<'--'
  (func $fac (export "fac") (param i64) (result i64)
    (if (result i64) (i64.eqz (local.get 0))
      (then (i64.const 1))
      (else
        (i64.mul
          (local.get 0)
          (call $fac (i64.sub (local.get 0) (i64.const 1)))
        )
      )
    )
  )

  (func $fib (export "fib") (param i64) (result i64)
    (if (result i64) (i64.le_u (local.get 0) (i64.const 1))
      (then (i64.const 1))
      (else
        (i64.add
          (call $fib (i64.sub (local.get 0) (i64.const 2)))
          (call $fib (i64.sub (local.get 0) (i64.const 1)))
        )
      )
    )
  )

  (func $even (export "even") (param i64) (result i32)
    (if (result i32) (i64.eqz (local.get 0))
      (then (i32.const 44))
      (else (call $odd (i64.sub (local.get 0) (i64.const 1))))
    )
  )
  (func $odd (export "odd") (param i64) (result i32)
    (if (result i32) (i64.eqz (local.get 0))
      (then (i32.const 99))
      (else (call $even (i64.sub (local.get 0) (i64.const 1))))
    )
  )
--
[1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880].each.with_index do
  assert_execute source, :fac, _2, _1
end
[1, 1, 2, 3, 5, 8, 13, 21, 34, 55].each.with_index do
  assert_execute source, :fib, _2, _1
end
[44, 99, 44, 99, 44, 99, 44, 99, 44, 99].each.with_index do
  assert_execute source, :even, _2, _1
end
[99, 44, 99, 44, 99, 44, 99, 44, 99, 44].each.with_index do
  assert_execute source, :odd, _2, _1
end

BEGIN {
  require 'wasminna/ast_parser'
  require 'wasminna/float'
  require 'wasminna/interpreter'
  require 'wasminna/preprocessor'
  require 'wasminna/s_expression_parser'

  def assert_execute(source, function, arguments, expected)
    mod = Wasminna.load(source)
    actual = mod.send(function, *arguments)

    if actual == expected
      print "\e[32m.\e[0m"
    else
      raise "expected #{expected}, got #{actual}"
    end
  end

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
              results =
                interpreter.stack.pop(type.results.length).
                zip(type.results).map do |value, type|
                  Wasminna.from_webassembly_value(value, type:)
                end

              case results.length
              when 0
                nil
              when 1
                results.first
              else
                results
              end
            end
          end
        end
      end
    end

    def self.to_webassembly_value(value, type:)
      case type
      in 'i32'
        Interpreter.new.send :unsigned, value, bits: 32
      in 'i64'
        Interpreter.new.send :unsigned, value, bits: 64
      in 'f32'
        Float.from_float(value).encode(format: Float::Format::Single)
      end
    end

    def self.from_webassembly_value(value, type:)
      case type
      in 'i32' | 'i64'
        value
      in 'f32'
        Float.decode(value, format: Float::Format::Single).to_f
      end
    end
  end
}

END {
  puts
}
