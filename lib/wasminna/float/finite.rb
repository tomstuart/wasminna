require 'wasminna/float/infinite'
require 'wasminna/float/zero'
require 'wasminna/helpers'
require 'wasminna/sign'

module Wasminna
  module Float
    Finite = Data.define(:rational) do
      include Helpers::Mask
      using Sign::Conversion

      def to_f
        rational.to_f
      end

      def sign
        rational.sign
      end

      def with_sign(sign)
        with(rational: rational.abs * sign)
      end

      def encode(format:)
        significand, exponent = approximate_within(format:)

        if significand.zero?
          return Zero.new(sign:).encode(format:)
        elsif significand < format.significands.min
          exponent = format.exponents.min
        elsif significand > format.significands.max
          return Infinite.new(sign:).encode(format:)
        end

        format.pack \
          sign:,
          exponent:,
          fraction: mask(significand, bits: format.fraction_bits)
      end

      private

      def approximate_within(format:)
        approximation = Approximation.new(rational: rational.abs, exponent: format.fraction_bits)
        approximation.fit_within \
          quotients: format.significands,
          exponents: (format.exponents.min + 1)..(format.exponents.max - 1)

        [approximation.quotient, approximation.exponent]
      end
    end

    Approximation = Struct.new(:rational, :exponent) do
      def fit_within(quotients:, exponents:)
        scale_within(quotients:, exponents:)
        round_within(quotients:, exponents:)
      end

      def quotient
        rational.numerator / rational.denominator
      end

      private

      def scale_within(quotients:, exponents:)
        loop do
          quotient = rational.numerator / rational.denominator

          if quotient < quotients.min && exponents.include?(exponent - 1)
            self.rational *= 2
            self.exponent -= 1
          elsif quotient > quotients.max && exponents.include?(exponent + 1)
            self.rational /= 2
            self.exponent += 1
          else
            break
          end
        end
      end

      def round_within(quotients:, exponents:)
        quotient, remainder = rational.numerator.divmod(rational.denominator)
        return if remainder.zero?

        if (
          remainder > rational.denominator / 2 ||
          (remainder == rational.denominator / 2 && quotient.odd?)
        )
          self.rational = Rational(quotient + 1)
          scale_within(quotients:, exponents:)
        end
      end
    end
  end
end
