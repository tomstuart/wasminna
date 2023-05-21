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
        raise "not a list: #{from.inspect}" unless from in [*]
        previous_s_expression, self.s_expression = self.s_expression, from

        read => ^starting_with unless starting_with.nil?

        yield.tap do
          raise unless finished?
          self.s_expression = previous_s_expression
        end
      end

      def repeatedly(**kwargs)
        terminator = kwargs[:until]

        [].tap do |results|
          until finished? || (!terminator.nil? && peek in ^terminator)
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
  end
end
