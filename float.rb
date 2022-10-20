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
        self => { numerator:, denominator: }

        # initialise the exponent to account for normalised significand format
        exponent = format.fraction_bits

        numerator, denominator, exponent =
          scale_quotient(numerator, denominator, exponent, format.significands, format.exponents)

        # round the significand if necessary
        significand, remainder = numerator.divmod(denominator)
        if remainder > denominator / 2 || (remainder == denominator / 2 && significand.odd?)
          significand += 1
          numerator, denominator, exponent =
            scale_quotient(significand, 1, exponent, format.significands, format.exponents)
          significand = numerator / denominator
        end

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

      def scale_quotient(numerator, denominator, exponent, quotients, exponents)
        # scale the quotient up/down until it’s in range
        # and adjust the exponent to account for scaling
        loop do
          quotient = numerator / denominator

          if quotient < quotients.min && exponents.include?(exponent - 1)
            numerator <<= 1
            exponent -= 1
          elsif quotient > quotients.max && exponents.include?(exponent + 1)
            denominator <<= 1
            exponent += 1
          else
            break
          end
        end

        [numerator, denominator, exponent]
      end
    end
  end
end
