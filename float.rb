module Wasminna
  module Float
    class Format < Struct.new(:exponent_bits, :significand_bits, keyword_init: true)
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

      def exponent_bias
        (1 << (exponent_bits - 1)) - 1
      end

      def fraction_bits
        significand_bits - 1
      end

      def significands
        1 << (significand_bits - 1) .. (1 << significand_bits) - 1
      end

      def exponents
        -exponent_bias + 1 .. exponent_bias
      end
    end

    module_function

    def from_integer(integer)
      Finite.new(numerator: integer.abs, denominator: 1, negated: integer.negative?)
    end

    def decode(encoded, bits:)
      format = Format.for(bits:)

      fraction = encoded & ((1 << format.fraction_bits) - 1)
      encoded >>= format.fraction_bits
      exponent = encoded & ((1 << format.exponent_bits) - 1)
      encoded >>= format.exponent_bits
      sign = encoded & 1
      negated = sign == 1

      if exponent == (1 << format.exponent_bits) - 1
        return fraction.zero? ?
          Infinite.new(negated:) :
          Nan.new(payload: fraction, negated:)
      end

      if exponent.zero?
        # either zero or subnormal
        significand = fraction

        if significand.nonzero?
          # subnormal
          exponent -= format.fraction_bits - 1
          exponent -= format.exponent_bias
        end
      else
        significand = fraction | (1 << format.fraction_bits)
        exponent -= format.fraction_bits
        exponent -= format.exponent_bias
      end

      numerator, denominator =
        if exponent.negative?
          [significand, 2 ** exponent.abs]
        else
          [significand * (2 ** exponent), 1]
        end

      Finite.new(numerator:, denominator:, negated:)
    end

    Infinite = Struct.new(:negated, keyword_init: true) do
      def encode(bits:)
        format = Format.for(bits:)

        sign = negated ? 1 : 0
        exponent = (1 << format.exponent_bits) - 1
        (sign << format.exponent_bits | exponent) << format.fraction_bits
      end
    end

    Nan = Struct.new(:payload, :negated, keyword_init: true) do
      def encode(bits:)
        format = Format.for(bits:)

        sign = negated ? 1 : 0
        exponent = (1 << format.exponent_bits) - 1
        fraction = payload & ((1 << format.fraction_bits) - 1)
        fraction |= 1 << (format.fraction_bits - 1) if fraction.zero?

        (sign << format.exponent_bits | exponent) << format.fraction_bits | fraction
      end
    end

    Finite = Struct.new(:numerator, :denominator, :negated, keyword_init: true) do
      def encode(bits:)
        format = Format.for(bits:)
        significand, exponent = approximate_within(format:)

        if significand < format.significands.min
          exponent -= 1
        elsif significand > format.significands.max
          significand = 0
          exponent += 1
        end

        # add bias to exponent
        exponent += format.exponent_bias

        # assemble bits into float
        sign = negated ? 1 : 0
        fraction = significand & ((1 << format.fraction_bits) - 1)
        (sign << format.exponent_bits | exponent) << format.fraction_bits | fraction
      end

      private

      def approximate_within(format:)
        approximation = Approximation.new(numerator:, denominator:, exponent: format.fraction_bits)
        approximation.fit_within \
          quotients: format.significands,
          exponents: format.exponents

        [
          approximation.numerator / approximation.denominator,
          approximation.exponent
        ]
      end
    end

    Approximation = Struct.new(:numerator, :denominator, :exponent, keyword_init: true) do
      def fit_within(quotients:, exponents:)
        scale_within(quotients:, exponents:)
        round_within(quotients:, exponents:)
      end

      def scale_within(quotients:, exponents:)
        loop do
          quotient = numerator / denominator

          if quotient < quotients.min && exponents.include?(exponent - 1)
            self.numerator <<= 1
            self.exponent -= 1
          elsif quotient > quotients.max && exponents.include?(exponent + 1)
            self.denominator <<= 1
            self.exponent += 1
          else
            break
          end
        end
      end

      def round_within(quotients:, exponents:)
        quotient, remainder = numerator.divmod(denominator)

        if remainder > denominator / 2 || (remainder == denominator / 2 && quotient.odd?)
          self.numerator = quotient + 1
          self.denominator = 1
          scale_within(quotients:, exponents:)
        end
      end
    end
  end
end
