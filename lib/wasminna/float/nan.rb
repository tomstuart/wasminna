require 'wasminna/helpers'

module Wasminna
  module Float
    Nan = Data.define(:payload, :sign) do
      include Helpers::Mask

      def to_f
        ::Float::NAN
      end

      def with_sign(sign)
        with(sign:)
      end

      def encode(format:)
        fraction = mask(payload, bits: format.fraction_bits)
        fraction |= 1 << (format.fraction_bits - 1) if fraction.zero?

        format.pack \
          sign:,
          exponent: format.exponents.max,
          fraction:
      end
    end
  end
end
