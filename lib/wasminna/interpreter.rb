require 'wasminna/ast'
require 'wasminna/float'
require 'wasminna/float/format'
require 'wasminna/float/nan'
require 'wasminna/helpers'
require 'wasminna/memory'
require 'wasminna/sign'

module Wasminna
  class Interpreter
    include AST
    include Helpers::Mask

    attr_accessor :current_module, :modules, :exports, :stack, :tags

    Function = Struct.new(:definition, :module)
    Global = Struct.new(:value)
    Table = Data.define(:elements, :maximum_size)
    Module = Data.define(:name, :functions, :tables, :memories, :globals, :types, :exports, :datas, :elements)

    def evaluate_script(script)
      self.current_module = nil
      self.modules = []
      self.exports = {
        'spectest' => {
          'global_i32' => Global.new(value: 666),
          'global_i64' => Global.new(value: 666),
          'global_f32' => Global.new(value: 666),
          'global_f64' => Global.new(value: 666),
          'table' => Table.new(elements: Array.new(10), maximum_size: 10),
          'memory' => Memory.from_limits(minimum_size: 1, maximum_size: 2),
          'print' => Function.new(definition: -> stack { }),
          'print_i32' => Function.new(definition: -> stack { stack.pop(1) }),
          'print_i64' => Function.new(definition: -> stack { stack.pop(1) }),
          'print_f32' => Function.new(definition: -> stack { stack.pop(1) }),
          'print_f64' => Function.new(definition: -> stack { stack.pop(1) }),
          'print_i32_f32' => Function.new(definition: -> stack { stack.pop(2) }),
          'print_f64_f64' => Function.new(definition: -> stack { stack.pop(2) })
        }
      }
      self.stack = []
      self.tags = []

      script.each do |command|
        begin
          case command
          in AST::Module => mod
            instantiate_module(mod)
          in Invoke(module_name:, name:, arguments:)
            mod = find_module(module_name)
            function = mod.exports.fetch(name)

            evaluate_expression(arguments, locals: [])
            self.current_module = mod
            invoke_function(function)
            print "\e[32m.\e[0m"
          in AssertReturn(action:, expecteds:)
            case action
            in Invoke(module_name:, name:, arguments:)
              if name == '4294967249' # TODO remove once binary format is supported
                print "\e[33m.\e[0m"
                next
              end
              mod = find_module(module_name)
              function = mod.exports.fetch(name)
              type = mod.types.slice(function.definition.type_index) || raise

              evaluate_expression(arguments, locals: [])
              self.current_module = mod
              invoke_function(function)
              actual_values = stack.pop(type.results.length)
              raise unless stack.empty?
            in Get(module_name:, name:)
              global = find_module(module_name).exports.fetch(name)
              actual_values = [global.value]
            end

            raise unless expecteds.length == actual_values.length
            expecteds.zip(actual_values).each do |expected, actual_value|
              case expected
              in NanExpectation(nan:, bits:)
                expected_value = nan
                format = Float::Format.for(bits:)
                float = Float.decode(actual_value, format:).to_f
                success = float.nan? # TODO check whether canonical or arithmetic
              else
                evaluate_expression(expected, locals: [])
                stack.pop(1) => [expected_value]
                raise unless stack.empty?
                success = actual_value == expected_value
              end

              unless success
                puts
                puts "\e[31mFAILED\e[0m: \e[33m#{pretty_print(command)}\e[0m"
                puts "expected #{expected_value.inspect}, got #{actual_value.inspect}"
                exit 1
              end
            end

            print "\e[32m.\e[0m"
          in AssertTrap(action: AST::Module => mod, failure:)
            begin
              instantiate_module(mod)
            rescue
              # ignore any exceptions for now
            end

            print "\e[32m.\e[0m"
          in AssertTrap
            # TODO
            print "\e[33m.\e[0m"
          in SkippedAssertion
            # TODO
            print "\e[33m.\e[0m"
          in Register(module_name:, name:)
            self.exports[module_name] = find_module(name).exports
          end
        rescue
          puts
          puts "\e[31mERROR\e[0m: \e[33m#{pretty_print(command)}\e[0m"
          raise
        end
      end
    end

    private

    using Sign::Conversion

    def pretty_print(ast)
      ast.inspect
    end

    def instantiate_module(mod)
      self.current_module = nil
      name = mod.name
      functions =
        build_functions(imports: mod.imports, functions: mod.functions)
      tables = build_tables(imports: mod.imports, tables: mod.tables)
      types = mod.types
      memories = build_memories(imports: mod.imports, memories: mod.memories)
      globals = build_globals(imports: mod.imports, globals: mod.globals)
      exports = build_exports(functions:, globals:, tables:, memories:, exports: mod.exports)
      datas = mod.datas
      elements = mod.elements

      self.modules <<
        Module.new(name:, functions:, memories:, tables:, globals:, types:, exports:, datas:, elements:)
      self.current_module = modules.last
      initialise_functions
      initialise_globals(imports: mod.imports, globals: mod.globals)
      initialise_memories(datas: mod.datas)
      initialise_tables(elements: mod.elements)

      if mod.start
        invoke_function(functions.slice(mod.start))
      end
    end

    def build_functions(imports:, functions:)
      function_imports =
        imports.select { |import| import in { kind: :func } }.
          map do |import|
            import => { module_name:, name: }
            exports.fetch(module_name).fetch(name)
          end

      function_imports + functions.map { Function.new(definition: _1) }
    end

    def build_tables(imports:, tables:)
      table_imports =
        imports.select { |import| import in { kind: :table } }.
          map do |import|
            import => { module_name:, name: }
            exports.fetch(module_name).fetch(name)
          end

      table_imports +
        tables.map do |table|
          Table.new(elements: Array.new(table.minimum_size), maximum_size: table.maximum_size)
        end
    end

    def build_memories(imports:, memories:)
      memory_imports =
        imports.select { |import| import in { kind: :memory } }.
          map do |import|
            import => { module_name:, name: }
            exports.fetch(module_name).fetch(name)
          end

      memory_imports +
        memories.map do |memory|
          Memory.from_limits \
            minimum_size: memory.minimum_size,
            maximum_size: memory.maximum_size
        end
    end

    def build_globals(imports:, globals:)
      global_imports =
        imports.select { |import| import in { kind: :global } }.
          map do |import|
            import => { module_name:, name: }
            exports.fetch(module_name).fetch(name)
          end

      global_imports + globals.map { Global.new }
    end

    def build_exports(functions:, globals:, tables:, memories:, exports:)
      {}.tap do |result|
        exports.each do |export|
          case export
          in { name:, kind: :func, index: }
            result[name] = functions.slice(index)
          in { name:, kind: :global, index: }
            result[name] = globals.slice(index)
          in { name:, kind: :table, index: }
            result[name] = tables.slice(index)
          in { name:, kind: :memory, index: }
            result[name] = memories.slice(index)
          end
        end
      end
    end

    def initialise_globals(imports:, globals:)
      global_imports_count =
        imports.count { |import| import in { kind: :global } }

      globals.each.with_index do |global, index|
        evaluate_expression(global.value, locals: [])
        stack.pop(1) => [value]
        current_module.globals.slice(global_imports_count + index).value = value
      end
    end

    def initialise_memories(datas:)
      datas.each do |data|
        if data in string:, mode: DataSegment::Mode::Active(index:, offset:)
          memory_instance = current_module.memories.slice(index)
          evaluate_expression(offset, locals: [])
          stack.pop(1) => [offset]
          raise if offset + string.bytesize > memory_instance.bytes.bytesize
          string.each_byte.with_index do |value, index|
            memory_instance.store(value:, offset: offset + index, bits: Memory::BITS_PER_BYTE)
          end
        end
      end
    end

    def initialise_tables(elements:)
      elements.each do |element|
        if element in items:, mode: ElementSegment::Mode::Active(index:, offset:)
          table_instance = current_module.tables.slice(index)
          evaluate_expression(offset, locals: [])
          stack.pop(1) => [offset]
          raise if offset + items.length > table_instance.elements.length

          items.each.with_index do |item, item_index|
            evaluate_expression(item, locals: [])
            stack.pop(1) => [value]
            table_instance.elements[offset + item_index] = value
          end
        end
      end
    end

    def initialise_functions
      current_module.functions.each do |function|
        function.module ||= current_module # TODO assign module at function creation time
      end
    end

    def find_module(name)
      if name.nil?
        modules.last
      else
        modules.detect { |mod| mod.name == name }
      end
    end

    def invoke_function(function)
      definition = function.definition

      case definition
      in AST::Function
        with_tags([]) do
          type = function.module.types.slice(definition.type_index) || raise

          as_block(type:) do
            argument_values = stack.pop(type.parameters.length)
            locals = definition.locals.map { 0 }
            locals = argument_values + locals

            with_module(function.module) do
              evaluate_expression(definition.body, locals:)
            end
          end
        end
      in Proc
        definition.call(stack)
      end
    end

    def with_module(mod)
      previous_module, self.current_module = self.current_module, mod

      begin
        yield
      ensure
        self.current_module = previous_module
      end
    end

    def with_tags(tags)
      previous_tags, self.tags = self.tags, tags

      begin
        yield
      ensure
        self.tags = previous_tags
      end
    end

    def evaluate_expression(expression, locals:)
      expression.each do |instruction|
        evaluate_instruction(instruction, locals:)
      end
    end

    def evaluate_instruction(instruction, locals:)
      case instruction
      in Const(type:, bits:, number:)
        stack.push(number)
      in Load(type:, bits:, storage_size:, sign_extension_mode:, offset: static_offset)
        stack.pop(1) => [offset]
        memory = current_module.memories.slice(0)
        value =
          memory.load(offset: offset + static_offset, bits: storage_size).then do |value|
            case sign_extension_mode
            in :unsigned
              value
            in :signed
              unsigned(signed(value, bits: storage_size), bits:)
            end
          end
        stack.push(value)
      in Store(type:, bits:, storage_size:, offset: static_offset)
        stack.pop(2) => [offset, value]
        memory = current_module.memories.slice(0)
        memory.store(value:, offset: offset + static_offset, bits: storage_size)
      in UnaryOp(type: :integer) | BinaryOp(type: :integer)
        evaluate_integer_instruction(instruction)
      in UnaryOp(type: :float) | BinaryOp(type: :float)
        evaluate_float_instruction(instruction)
      in Return
        throw(tags.last)
      in LocalGet(index:)
        stack.push(locals.slice(index))
      in LocalSet | LocalTee
        instruction => { index: }
        stack.pop(1) => [value]
        locals[index] = value
        stack.push(value) if instruction in LocalTee
      in GlobalGet(index:)
        stack.push(current_module.globals.slice(index).value)
      in GlobalSet(index:)
        stack.pop(1) => [value]
        current_module.globals.slice(index).value = value
      in Br(index:)
        throw(tags.slice(index))
      in BrIf(index:)
        stack.pop(1) => [condition]
        throw(tags.slice(index)) unless condition.zero?
      in Select
        stack.pop(3) => [value_1, value_2, condition]

        if condition.zero?
          value_2
        else
          value_1
        end.tap { stack.push(_1) }
      in Nop
        # do nothing
      in Call(index:)
        function = current_module.functions.slice(index)
        invoke_function(function)
      in CallIndirect(table_index:, type_index:)
        stack.pop(1) => [index]

        table = current_module.tables.slice(table_index)
        function = table.elements.slice(index)
        invoke_function(function)
      in Drop
        stack.pop(1)
      in Block(type:, body:)
        as_block(type: expand_blocktype(type)) do
          evaluate_expression(body, locals:)
        end
      in Loop(type:, body:)
        as_loop(type: expand_blocktype(type)) do
          evaluate_expression(body, locals:)
        end
      in If(type:, consequent:, alternative:)
        stack.pop(1) => [condition]
        body = condition.zero? ? alternative : consequent
        as_block(type: expand_blocktype(type)) do
          evaluate_expression(body, locals:)
        end
      in BrTable(target_indexes:, default_index:)
        stack.pop(1) => [table_index]
        index =
          if table_index < target_indexes.length
            target_indexes.slice(table_index)
          else
            default_index
          end
        throw(tags.slice(index))
      in MemoryGrow
        stack.pop(1) => [pages]
        memory = current_module.memories.slice(0)
        previous_size = memory.size_in_pages
        if memory.grow_by(pages:)
          stack.push(previous_size)
        else
          stack.push(unsigned(-1, bits: 32))
        end
      in MemorySize
        memory = current_module.memories.slice(0)
        stack.push(memory.size_in_pages)
      in RefNull
        stack.push(nil)
      in RefExtern(value:)
        stack.push({ externref: value })
      in RefFunc(index:)
        function = current_module.functions.slice(index)
        stack.push(function)
      in TableGet(index:)
        stack.pop(1) => [offset]
        table = current_module.tables.slice(index)
        stack.push(table.elements.slice(offset))
      in TableSet(index:)
        stack.pop(2) => [offset, value]
        table = current_module.tables.slice(index)
        table.elements[offset] = value
      in MemoryFill
        stack.pop(3) => [offset, value, length]
        memory = current_module.memories.slice(0)
        length.times do |index|
          memory.store(value:, offset: offset + index, bits: Memory::BITS_PER_BYTE)
        end
      in MemoryCopy
        stack.pop(3) => [destination, source, length]
        memory = current_module.memories.slice(0)
        values =
          length.times.map do |index|
            memory.load(offset: source + index, bits: Memory::BITS_PER_BYTE)
          end
        values.each.with_index do |value, index|
          memory.store(value:, offset: destination + index, bits: Memory::BITS_PER_BYTE)
        end
      in MemoryInit(index:)
        stack.pop(3) => [destination, source, length]
        memory = current_module.memories.slice(0)
        unless length.zero?
          case current_module.datas.slice(index)
          in DataSegment(string:, mode: DataSegment::Mode::Passive)
            string.byteslice(source, length).each_byte.with_index do |value, index|
              memory.store(value:, offset: destination + index, bits: Memory::BITS_PER_BYTE)
            end
          end
        end
      in DataDrop(index:)
        current_module.datas[index] = nil
      in TableInit(table_index:, element_index:)
        stack.pop(3) => [destination, source, length]
        unless length.zero?
          table = current_module.tables.slice(table_index)
          case current_module.elements.slice(element_index)
          in ElementSegment(items:, mode: ElementSegment::Mode::Passive)
            length.times do |index|
              evaluate_expression(items.slice(source + index), locals: [])
              stack.pop(1) => [value]
              table.elements[destination + index] = value
            end
          end
        end
      in ElemDrop(index:)
        current_module.elements[index] = nil
      in TableCopy(destination_index:, source_index:)
        stack.pop(3) => [destination, source, length]
        destination_table = current_module.tables.slice(destination_index)
        source_table = current_module.tables.slice(source_index)
        destination_table.elements[destination, length] =
          source_table.elements.slice(source, length)
      in RefIsNull
        stack.pop(1) => [value]
        stack.push(value.nil? ? 1 : 0)
      in TableFill(index:)
        stack.pop(3) => [offset, value, length]
        table = current_module.tables.slice(index)
        length.times do |index|
          table.elements[offset + index] = value
        end
      in TableGrow(index:)
        stack.pop(2) => [value, delta]
        table = current_module.tables.slice(index)
        previous_size = table.elements.length
        maximum_size = table.maximum_size.nil? ? 2 ** 32 - 1 : table.maximum_size
        if previous_size + delta <= maximum_size
          table.elements.concat(Array.new(delta, value))
          stack.push(previous_size)
        else
          stack.push(unsigned(-1, bits: 32))
        end
      in TableSize(index:)
        table = current_module.tables.slice(index)
        stack.push(table.elements.length)
      end
    end

    def expand_blocktype(blocktype)
      case blocktype
      in Integer
        current_module.types.slice(blocktype) || raise
      in Array
        Type.new(parameters: [], results: blocktype)
      end
    end

    def as_block(type:, &)
      with_branch_handler(type:, arity: type.results.length, &)
    end

    def as_loop(type:, &)
      begin
        branched =
          with_branch_handler(type:, arity: type.parameters.length, &)
      end while branched
    end

    def with_branch_handler(type:, arity:)
      stack_height = stack.length - type.parameters.length
      branched = nil

      catch do |tag|
        tags.unshift(tag)

        branched = true
        yield
        branched = false
      ensure
        tags.shift
      end

      if branched
        stack.pop(arity) => values
        stack.pop(stack.length - stack_height)
        stack.push(*values)
      end

      branched
    end

    def evaluate_integer_instruction(instruction)
      case instruction
      in BinaryOp(bits:, operation:)
        stack.pop(2) => [left, right]

        case operation
        in 'add'
          left + right
        in 'sub'
          left - right
        in 'mul'
          left * right
        in 'div_s'
          with_signed(left, right, bits:) do |left, right|
            divide(left, right)
          end
        in 'div_u'
          divide(left, right)
        in 'rem_s'
          with_signed(left, right, bits:) do |left, right|
            modulo(left, right)
          end
        in 'rem_u'
          modulo(left, right)
        in 'and'
          left & right
        in 'or'
          left | right
        in 'xor'
          left ^ right
        in 'shl'
          right %= bits
          left << right
        in 'shr_s'
          right %= bits
          with_signed(left, bits:) do |left|
            left >> right
          end
        in 'shr_u'
          right %= bits
          left >> right
        in 'rotl'
          right %= bits
          (left << right) | (left >> (bits - right))
        in 'rotr'
          right %= bits
          (left << (bits - right)) | (left >> right)
        in 'eq'
          bool(left == right)
        in 'ne'
          bool(left != right)
        in 'lt_s'
          with_signed(left, right, bits:) do |left, right|
            bool(left < right)
          end
        in 'lt_u'
          bool(left < right)
        in 'le_s'
          with_signed(left, right, bits:) do |left, right|
            bool(left <= right)
          end
        in 'le_u'
          bool(left <= right)
        in 'gt_s'
          with_signed(left, right, bits:) do |left, right|
            bool(left > right)
          end
        in 'gt_u'
          bool(left > right)
        in 'ge_s'
          with_signed(left, right, bits:) do |left, right|
            bool(left >= right)
          end
        in 'ge_u'
          bool(left >= right)
        end
      in UnaryOp(bits:, operation:)
        stack.pop(1) => [value]

        case operation
        in 'clz'
          0.upto(bits).take_while { |count| value[bits - count, count].zero? }.last
        in 'ctz'
          0.upto(bits).take_while { |count| value[0, count].zero? }.last
        in 'popcnt'
          0.upto(bits - 1).count { |position| value[position].nonzero? }
        in 'extend8_s' | 'extend16_s' | 'extend32_s' | 'extend_i32_s'
          extend_bits = operation.slice(%r{\d+}).to_i(10)
          unsigned(signed(value, bits: extend_bits), bits:)
        in 'extend_i32_u'
          value
        in 'eqz'
          bool(value.zero?)
        in 'wrap_i64'
          value
        in 'reinterpret_f32' | 'reinterpret_f64'
          float_bits = operation.slice(%r{\d+}).to_i(10)
          raise unless bits == float_bits
          value
        in 'trunc_f32_s' | 'trunc_f64_s' | 'trunc_f32_u' | 'trunc_f64_u' | 'trunc_sat_f32_s' | 'trunc_sat_f64_s' | 'trunc_sat_f32_u' | 'trunc_sat_f64_u'
          float_bits = operation.slice(%r{\d+}).to_i(10)
          signed_input = operation.end_with?('_s')
          saturating = operation.include?('_sat')
          format = Float::Format.for(bits: float_bits)
          result = Float.decode(value, format:).to_f

          result =
            if saturating && result.nan?
              0
            elsif saturating && result.infinite?
              result
            else
              result.truncate
            end

          if saturating
            size = 1 << bits
            min, max =
              if signed_input
                [-(size / 2), (size / 2) - 1]
              else
                [0, size - 1]
              end
            result = result.clamp(min, max)
          end

          if signed_input
            unsigned(result, bits:)
          else
            result
          end
        end
      end.then { |value| mask(value, bits:) }.tap { stack.push(_1) }
    end

    def evaluate_float_instruction(instruction)
      format = Float::Format.for(bits: instruction.bits)

      case instruction
      in BinaryOp(bits:, operation:)
        stack.pop(2) => [left, right]

        case operation
        in 'add' | 'sub' | 'mul' | 'div' | 'min' | 'max'
          with_float(left, right, format:) do |left, right|
            case operation
            in 'add'
              left + right
            in 'sub'
              left - right
            in 'mul'
              left * right
            in 'div'
              left / right
            in 'min' | 'max'
              arguments = [left, right]
              if arguments.any?(&:nan?)
                ::Float::NAN
              elsif arguments.all?(&:zero?)
                arguments.send(:"#{operation}_by", &:sign)
              else
                arguments.send(operation)
              end
            end
          end
        in 'copysign'
          left, right =
            [left, right].map { Float.decode(_1, format:) }
          left.with_sign(right.sign).encode(format:)
        in 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge'
          left, right =
            [left, right].map { Float.decode(_1, format:).to_f }
          operation =
            {
              'eq' => '==', 'ne' => '!=',
              'lt' => '<', 'le' => '<=',
              'gt' => '>', 'ge' => '>='
            }.fetch(operation).to_sym.to_proc
          bool(operation.call(left, right))
        end
      in UnaryOp(bits:, operation:)
        stack.pop(1) => [value]

        case operation
        in 'sqrt' | 'floor' | 'ceil' | 'trunc' | 'nearest'
          with_float(value, format:) do |value|
            case operation
            in 'sqrt'
              if value.zero?
                value
              elsif value.negative?
                ::Float::NAN
              else
                Math.sqrt(value)
              end
            in 'floor' | 'ceil' | 'trunc' | 'nearest'
              if value.zero? || value.infinite? || value.nan?
                value
              else
                case operation
                in 'floor'
                  value.floor
                in 'ceil'
                  value.ceil
                in 'trunc'
                  value.truncate
                in 'nearest'
                  value.round(half: :even)
                end.then do |result|
                  if result.zero? && value.negative?
                    -0.0
                  else
                    result
                  end
                end
              end
            end
          end
        in 'abs'
          value = Float.decode(value, format:)
          value.with_sign(Sign::PLUS).encode(format:)
        in 'neg'
          value = Float.decode(value, format:)
          value.with_sign(!value.sign).encode(format:)
        in 'convert_i32_s' | 'convert_i64_s'
          integer_bits = operation.slice(%r{\d+}).to_i(10)
          integer = signed(value, bits: integer_bits)
          Float.from_integer(integer).encode(format:)
        in 'convert_i32_u' | 'convert_i64_u'
          Float.from_integer(value).encode(format:)
        in 'promote_f32'
          raise unless bits == 64
          input_format = Float::Format.for(bits: 32)
          float = Float.decode(value, format: input_format)

          case float
          in Float::Nan
            Float::Nan.new(payload: 0, sign: float.sign)
          else
            float
          end.encode(format:)
        in 'demote_f64'
          raise unless bits == 32
          input_format = Float::Format.for(bits: 64)
          float = Float.decode(value, format: input_format)

          case float
          in Float::Nan
            Float::Nan.new(payload: 0, sign: float.sign)
          else
            float
          end.encode(format:)
        in 'reinterpret_i32' | 'reinterpret_i64'
          integer_bits = operation.slice(%r{\d+}).to_i(10)
          raise unless bits == integer_bits
          value
        end
      end.tap { stack.push(_1) }
    end

    def with_signed(*unsigned_args, bits:)
      signed_args = unsigned_args.map { |arg| signed(arg, bits:) }
      signed_result = yield *signed_args
      unsigned(signed_result, bits:)
    end

    def with_float(*integer_args, format:)
      float_args = integer_args.map { |arg| Float.decode(arg, format:).to_f }
      float_result = yield *float_args
      Float.from_float(float_result).encode(format:)
    end

    def divide(dividend, divisor)
      quotient = dividend / divisor

      if quotient.negative? && (dividend % divisor).nonzero?
        quotient + 1
      else
        quotient
      end
    end

    def modulo(dividend, divisor)
      dividend - (divisor * divide(dividend, divisor))
    end

    def bool(value)
      value ? 1 : 0
    end

    def signed(unsigned, bits:)
      unsigned = mask(unsigned, bits:)
      size = 1 << bits

      if unsigned < size / 2
        unsigned
      else
        unsigned - size
      end
    end

    def unsigned(signed, bits:)
      signed = mask(signed, bits:)
      size = 1 << bits

      if signed.negative?
        signed + size
      else
        signed
      end
    end
  end
end
