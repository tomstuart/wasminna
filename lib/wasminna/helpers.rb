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
  end
end
