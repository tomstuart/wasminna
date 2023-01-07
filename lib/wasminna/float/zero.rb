module Wasminna
  module Float
    Zero = Data.define(:sign) do
      def to_f
        0.0 * sign
      end

      def with_sign(sign)
        with(sign:)
      end

      def encode(format:)
        format.pack \
          sign:,
          exponent: format.exponents.min,
          fraction: 0
      end
    end
  end
end
