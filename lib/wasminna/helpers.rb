module Wasminna
  module Helpers
    module Mask
      private

      def mask(value, bits:)
        size = 1 << bits
        value & (size - 1)
      end
    end

    module SizeOf
      private

      def size_of(value, **kwargs)
        value.ceildiv(kwargs.fetch(:in))
      end
    end

    module ReadFromSExpression
      private

      def read_list(from: read, starting_with: nil)
        return read_list(from:, starting_with:) { repeatedly { read } } unless block_given?

        raise "not a list: #{from.inspect}" unless from in [*]
        previous_s_expression, self.s_expression = self.s_expression, from

        read => ^starting_with unless starting_with.nil?

        yield.tap do
          raise unless finished?
          self.s_expression = previous_s_expression
        end
      end

      def repeatedly
        [].tap do |results|
          loop do
            break if finished?
            results << yield
          end
        end
      end

      def can_read_list?(starting_with: nil)
        if starting_with.nil?
          peek in [*]
        else
          peek in [^starting_with, *]
        end
      end

      def finished?
        s_expression.empty?
      end

      def peek
        s_expression.first
      end

      def read
        s_expression.shift
      end
    end

    module StringValue
      private

      def string_value(string)
        encoding = string.encoding
        string.
          delete_prefix('"').delete_suffix('"').
          force_encoding(Encoding::ASCII_8BIT).
          gsub(%r{\\\h{2}}) do |digits|
            digits.delete_prefix('\\').to_i(16).chr(Encoding::ASCII_8BIT)
          end.
          force_encoding(encoding)
      end
    end

    module ReadOptionalId
      private

      def read_optional_id
        read if peek in %r{\A\$}
      end
    end

    module ReadIndex
      private

      INDEX_REGEXP =
        %r{
          \A
          (?:
            \d (?: _? \d)*
            |
            0x \h (?: _? \h)*
            |
            \$ .+
          )
          \z
        }x

      def can_read_index?
        peek in INDEX_REGEXP
      end

      def read_index
        read => INDEX_REGEXP => index
        index
      end
    end

    module ReadInstructions
      private

      def read_instructions(&)
        return read_list(from: read_instructions, &) if block_given?

        repeatedly do
          raise StopIteration if peek in 'end' | 'else'
          read_instruction
        end.flatten(1)
      end

      def read_instruction
        case peek
        in [*]
          read_folded_instruction
        in 'block' | 'loop' | 'if'
          read_structured_instruction
        else
          read_plain_instruction
        end
      end

      def read_folded_instruction
        [read_list]
      end

      def read_structured_instruction
        case peek
        in 'block' | 'loop'
          [
            read, *read_optional_id, *read_typeuse,
            *read_instructions,
            read, *read_optional_id
          ]
        in 'if'
          [
            read, *read_optional_id, *read_typeuse,
            *read_instructions,
            *([read, *read_instructions] if peek in 'else'),
            read, *read_optional_id
          ]
        end
      end

      def read_plain_instruction(&)
        return read_list(from: read_plain_instruction, &) if block_given?

        [
          keyword = read,
          *read_plain_instruction_immediates(keyword:)
        ]
      end

      def read_plain_instruction_immediates(keyword:)
        case keyword
        in 'call_indirect'
          [*read_indexes, *read_typeuse]
        in 'select'
          read_declarations(kind: 'result')
        in 'table.get' | 'table.set' | 'table.size' | 'table.grow' | 'table.fill' | 'table.copy' | 'table.init' | 'br_table'
          read_indexes
        in 'br' | 'br_if' | 'call' | 'ref.null' | 'ref.func' | 'local.get' | 'local.set' | 'local.tee' | 'global.get' | 'global.set' | 'elem.drop' | 'memory.init' | 'data.drop' | %r{\A[fi](?:32|64)\.const\z}
          [read]
        in %r{\A[fi](?:32|64)\.(?:load|store)}
          [*(read if peek in %r{\Aoffset=}), *(read if peek in %r{\Aalign=})]
        else
          []
        end
      end

      def read_typeuse
        [
          *([read_list] if can_read_list?(starting_with: 'type')),
          *read_declarations(kind: 'param'),
          *read_declarations(kind: 'result')
        ]
      end

      def read_declarations(kind:, &)
        return read_list(from: read_declarations(kind:), &) if block_given?

        repeatedly do
          raise StopIteration unless can_read_list?(starting_with: kind)
          read_list
        end
      end

      def read_indexes
        repeatedly do
          raise StopIteration unless can_read_index?
          read_index
        end
      end
    end
  end
end
