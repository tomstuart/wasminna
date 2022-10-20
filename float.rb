module Wasminna
  module Float
    module MaskHelper
      def mask(value, bits:)
        size = 1 << bits
        value & (size - 1)
      end
    end

    class Format < Struct.new(:exponent_bits, :significand_bits, keyword_init: true)
      include MaskHelper

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

      def pack(negated:, exponent:, fraction:)
        sign = negated ? 1 : 0
        biased_exponent = exponent + exponent_bias

        encoded = 0
        encoded |= sign
        encoded <<= exponent_bits
        encoded |= biased_exponent
        encoded <<= fraction_bits
        encoded |= fraction

        encoded
      end

      def unpack(encoded)
        fraction = mask(encoded, bits: fraction_bits)
        encoded >>= fraction_bits
        biased_exponent = mask(encoded, bits: exponent_bits)
        encoded >>= exponent_bits
        sign = mask(encoded, bits: 1)

        negated = sign == 1
        exponent = biased_exponent - exponent_bias

        { negated:, exponent:, fraction: }
      end

      private

      def exponent_bias
        (1 << (exponent_bits - 1)) - 1
      end
    end

    module_function

    def from_integer(integer)
      Finite.new(numerator: integer.abs, denominator: 1, negated: integer.negative?)
    end

    def decode(encoded, format:)
      format.unpack(encoded) => { negated:, exponent:, fraction: }

      case exponent
      when format.exponents.max
        return fraction.zero? ?
          Infinite.new(negated:) :
          Nan.new(payload: fraction, negated:)
      when format.exponents.min
        significand = fraction
        exponent -= format.fraction_bits - 1
      else
        significand = fraction | (1 << format.fraction_bits)
        exponent -= format.fraction_bits
      end

      numerator, denominator =
        if exponent.negative?
          [significand, 2 ** exponent.abs]
        else
          [significand * (2 ** exponent), 1]
        end

      Finite.new(numerator:, denominator:, negated:)
    end

    NAN_REGEXP =
      %r{
        \A
        (?<sign>
          [+-]
        )?
        nan
        (
          :0x
          (?<payload>
            \h+
          )
        )?
        \z
      }x
    INFINITE_REGEXP =
      %r{
        \A
        (?<sign>
          [+-]
        )?
        inf
        \z
      }x
    HEXFLOAT_REGEXP =
      %r{
        \A
        (?<sign>
          [+-]
        )?
        0x
        (?<p>
          \h+
        )
        (
          \.
          (?<q>
            \h*
          )
        )?
        (
          [Pp]
          (?<e>
            [+-]?
            \d+
          )
        )?
        \z
      }x
    FLOAT_REGEXP =
      %r{
        \A
        (?<sign>
          [+-]
        )?
        (?<p>
          \d+
        )
        (
          \.
          (?<q>
            \d*
          )
        )?
        (
          [Ee]
          (?<e>
            [+-]?
            \d+
          )
        )?
        \z
      }x

    def parse(string)
      string = string.tr('_', '')

      if match = NAN_REGEXP.match(string)
        Nan.new(payload: match[:payload].to_s.to_i(16), negated: match[:sign] == '-')
      elsif match = INFINITE_REGEXP.match(string)
        Infinite.new(negated: match[:sign] == '-')
      elsif match = HEXFLOAT_REGEXP.match(string)
        p, q, e = match.values_at(:p, :q, :e).map(&:to_s)

        radix = 16
        base = 2
        exponent_radix = 10

        numerator, denominator = [p, q].join.to_i(radix), radix ** q.length
        exponent = e.to_i(exponent_radix)
        scale = base ** exponent.abs
        if exponent.negative?
          denominator *= scale
        else
          numerator *= scale
        end

        Finite.new(numerator:, denominator:, negated: match[:sign] == '-')
      elsif match = FLOAT_REGEXP.match(string)
        p, q, e = match.values_at(:p, :q, :e).map(&:to_s)

        radix = 10
        base = 10
        exponent_radix = 10

        numerator, denominator = [p, q].join.to_i(radix), radix ** q.length
        exponent = e.to_i(exponent_radix)
        scale = base ** exponent.abs
        if exponent.negative?
          denominator *= scale
        else
          numerator *= scale
        end

        Finite.new(numerator:, denominator:, negated: match[:sign] == '-')
      else
        raise "can’t parse float: #{string.inspect}"
      end
    end

    Infinite = Struct.new(:negated, keyword_init: true) do
      def encode(format:)
        format.pack \
          negated:,
          exponent: format.exponents.max,
          fraction: 0
      end
    end

    Nan = Struct.new(:payload, :negated, keyword_init: true) do
      include MaskHelper

      def encode(format:)
        fraction = mask(payload, bits: format.fraction_bits)
        fraction |= 1 << (format.fraction_bits - 1) if fraction.zero?

        format.pack \
          negated:,
          exponent: format.exponents.max,
          fraction:
      end
    end

    Finite = Struct.new(:numerator, :denominator, :negated, keyword_init: true) do
      include MaskHelper

      def encode(format:)
        significand, exponent = approximate_within(format:)

        if significand < format.significands.min
          exponent = format.exponents.min
        elsif significand > format.significands.max
          return Infinite.new(negated:).encode(format:)
        end

        format.pack \
          negated:,
          exponent:,
          fraction: mask(significand, bits: format.fraction_bits)
      end

      private

      def approximate_within(format:)
        approximation = Approximation.new(numerator:, denominator:, exponent: format.fraction_bits)
        approximation.fit_within \
          quotients: format.significands,
          exponents: (format.exponents.min + 1)..(format.exponents.max - 1)

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
