require 'sign'

module Wasminna
  module Float
    module MaskHelper
      def mask(value, bits:)
        size = 1 << bits
        value & (size - 1)
      end
    end

    module MatchPattern
      refine MatchData do
        def deconstruct_keys(keys)
          named_captures.transform_keys(&:to_sym).then do |captures|
            if keys
              captures.slice(*keys)
            else
              captures
            end
          end
        end
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
        encoded |= mask(sign, bits: 1)
        encoded <<= exponent_bits
        encoded |= mask(biased_exponent, bits: exponent_bits)
        encoded <<= fraction_bits
        encoded |= mask(fraction, bits: fraction_bits)

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
      Finite.new(rational: Rational(integer))
    end

    using Sign::Conversion

    def from_float(float)
      float = Float(float)
      negated = float.sign.negative?

      if float.zero?
        Zero.new(negated:)
      elsif float.infinite?
        Infinite.new(negated:)
      elsif float.nan?
        Nan.new(payload: 0, negated:)
      else
        Finite.new(rational: Rational(float))
      end
    end

    def decode(encoded, format:)
      format.unpack(encoded) => { negated:, exponent:, fraction: }

      case exponent
      when format.exponents.max
        return fraction.zero? ?
          Infinite.new(negated:) :
          Nan.new(payload: fraction, negated:)
      when format.exponents.min
        return Zero.new(negated:) if fraction.zero?
        significand = fraction
        exponent -= format.fraction_bits - 1
      else
        significand = fraction | (1 << format.fraction_bits)
        exponent -= format.fraction_bits
      end

      rational = Rational(significand)
      rational = -rational if negated

      scale = 2 ** exponent.abs
      rational =
        if exponent.negative?
          rational / scale
        else
          rational * scale
        end

      Finite.new(rational:)
    end

    NAN_REGEXP =
      %r{
        \A
        (?<sign> [+-])? nan
        (:0x (?<payload> \h (_? \h)*))?
        \z
      }x
    INFINITE_REGEXP =
      %r{
        \A
        (?<sign> [+-])? inf
        \z
      }x
    HEXFLOAT_REGEXP =
      %r{
        \A
        (?<sign> [+-])? 0x (?<whole> \h (_? \h)*)
        (\. (?<fractional> \h (_? \h)*)?)?
        ([Pp] (?<exponent_sign> [+-])? (?<exponent> \d (_? \d)*))?
        \z
      }x
    FLOAT_REGEXP =
      %r{
        \A
        (?<sign> [+-])? (?<whole> \d (_? \d)*)
        (\. (?<fractional> \d (_? \d)*)?)?
        ([Ee] (?<exponent_sign> [+-])? (?<exponent> \d (_? \d)*))?
        \z
      }x

    using MatchPattern

    def parse(string)
      if finite_regexp_match(string) in [
        { sign:, whole:, fractional:, exponent_sign:, exponent: },
        { radix:, base:, exponent_radix: }
      ]
        whole, fractional, exponent =
          [whole, fractional, exponent].map { _1&.tr('_', '') }
        negated = sign == '-'
        rational = parse_rational(whole, fractional, radix)
        return Zero.new(negated:) if rational.zero?

        rational = -rational if negated
        scale = base ** (exponent&.to_i(exponent_radix) || 0)
        rational =
          if exponent_sign == '-'
            rational / scale
          else
            rational * scale
          end

        Finite.new(rational:)
      elsif NAN_REGEXP.match(string) in { sign:, payload: }
        Nan.new(payload: payload&.tr('_', '')&.to_i(16) || 0, negated: sign == '-')
      elsif INFINITE_REGEXP.match(string) in { sign: }
        Infinite.new(negated: sign == '-')
      else
        raise "can’t parse float: #{string.inspect}"
      end
    end

    def parse_rational(whole, fractional, radix)
      fractional_digits = fractional&.length || 0
      whole, fractional = [whole, fractional].map { _1&.to_i(radix) || 0 }
      denominator = radix ** fractional_digits
      numerator = (whole * denominator) + fractional

      Rational(numerator, denominator)
    end

    def finite_regexp_match(string)
      if match = FLOAT_REGEXP.match(string)
        [match, { radix: 10, base: 10, exponent_radix: 10 }]
      elsif match = HEXFLOAT_REGEXP.match(string)
        [match, { radix: 16, base: 2, exponent_radix: 10 }]
      end
    end

    Infinite = Struct.new(:negated, keyword_init: true) do
      def to_f
        if negated
          -::Float::INFINITY
        else
          ::Float::INFINITY
        end
      end

      def encode(format:)
        format.pack \
          negated:,
          exponent: format.exponents.max,
          fraction: 0
      end
    end

    Nan = Struct.new(:payload, :negated, keyword_init: true) do
      include MaskHelper

      def to_f
        ::Float::NAN
      end

      def encode(format:)
        fraction = mask(payload, bits: format.fraction_bits)
        fraction |= 1 << (format.fraction_bits - 1) if fraction.zero?

        format.pack \
          negated:,
          exponent: format.exponents.max,
          fraction:
      end
    end

    Zero = Struct.new(:negated, keyword_init: true) do
      def to_f
        if negated
          -0.0
        else
          0.0
        end
      end

      def encode(format:)
        format.pack \
          negated:,
          exponent: format.exponents.min,
          fraction: 0
      end
    end

    Finite = Struct.new(:rational, keyword_init: true) do
      include MaskHelper

      def to_f
        rational.to_f
      end

      def encode(format:)
        significand, exponent = approximate_within(format:)
        negated = rational.negative?

        if significand.zero?
          return Zero.new(negated:).encode(format:)
        elsif significand < format.significands.min
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
        approximation = Approximation.new(numerator: rational.numerator.abs, denominator: rational.denominator.abs, exponent: format.fraction_bits)
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
