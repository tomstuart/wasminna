require 'wasminna/helpers'
require 'wasminna/sign'

module Wasminna
  module Float
    class Format < Data.define(:exponent_bits, :significand_bits)
      include Helpers::Mask

      ALL = [
        Single = new(exponent_bits: 8, significand_bits: 24),
        Double = new(exponent_bits: 11, significand_bits: 53)
      ]

      def self.for(bits:)
        ALL.detect { |format| format.bits == bits } ||
          raise("unsupported float width: #{bits}")
      end

      def bits
        exponent_bits + significand_bits
      end

      def fraction_bits
        significand_bits - 1
      end

      def significands
        1 << (significand_bits - 1) .. (1 << significand_bits) - 1
      end

      def exponents
        -exponent_bias .. exponent_bias + 1
      end

      SIGN_BIT = { Sign::PLUS => 0, Sign::MINUS => 1 }

      def pack(sign:, exponent:, fraction:)
        sign = SIGN_BIT.fetch(sign)
        exponent += exponent_bias

        encoded = 0
        encoded |= mask(sign, bits: 1)
        encoded <<= exponent_bits
        encoded |= mask(exponent, bits: exponent_bits)
        encoded <<= fraction_bits
        encoded |= mask(fraction, bits: fraction_bits)

        encoded
      end

      def unpack(encoded)
        fraction = mask(encoded, bits: fraction_bits)
        encoded >>= fraction_bits
        exponent = mask(encoded, bits: exponent_bits)
        encoded >>= exponent_bits
        sign = mask(encoded, bits: 1)

        sign = SIGN_BIT.invert.fetch(sign)
        exponent -= exponent_bias

        { sign:, exponent:, fraction: }
      end

      private

      def exponent_bias
        (1 << (exponent_bits - 1)) - 1
      end
    end
  end
end
