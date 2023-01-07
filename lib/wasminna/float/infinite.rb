module Wasminna
  module Float
    Infinite = Data.define(:sign) do
      def to_f
        ::Float::INFINITY * sign
      end

      def with_sign(sign)
        with(sign:)
      end

      def encode(format:)
        format.pack \
          sign:,
          exponent: format.exponents.max,
          fraction: 0
      end
    end
  end
end
