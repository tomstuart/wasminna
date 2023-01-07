require 'wasminna/float/nan'
require 'wasminna/helpers'
require 'wasminna/sign'

module Wasminna
  module Float
    module_function

    def from_integer(integer)
      Finite.new(rational: Rational(integer))
    end

    using Sign::Conversion

    def from_float(float)
      float = Float(float)
      sign = float.sign

      if float.zero?
        Zero.new(sign:)
      elsif float.infinite?
        Infinite.new(sign:)
      elsif float.nan?
        Nan.new(payload: 0, sign:)
      else
        Finite.new(rational: Rational(float))
      end
    end

    def decode(encoded, format:)
      format.unpack(encoded) => { sign:, exponent:, fraction: }

      case exponent
      when format.exponents.max
        return fraction.zero? ?
          Infinite.new(sign:) :
          Nan.new(payload: fraction, sign:)
      when format.exponents.min
        return Zero.new(sign:) if fraction.zero?
        significand = fraction
        exponent -= format.fraction_bits - 1
      else
        significand = fraction | (1 << format.fraction_bits)
        exponent -= format.fraction_bits
      end

      Finite.new(rational: Rational(significand) * (2 ** exponent) * sign)
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

    def parse(string)
      if finite_regexp_match(string) in [
        { sign:, whole:, fractional:, exponent_sign:, exponent: },
        { radix:, base:, exponent_radix: }
      ]
        whole, fractional, exponent =
          [whole, fractional, exponent].map { _1&.tr('_', '') }
        sign, exponent_sign = [sign, exponent_sign].map { Sign.for(name: _1) }
        exponent = (exponent&.to_i(exponent_radix) || 0) * exponent_sign
        rational =
          parse_rational(whole, fractional, radix) * (base ** exponent) * sign

        if rational.zero?
          Zero.new(sign:)
        else
          Finite.new(rational:)
        end
      elsif NAN_REGEXP.match(string) in { sign:, payload: }
        Nan.new(payload: payload&.tr('_', '')&.to_i(16) || 0, sign: Sign.for(name: sign))
      elsif INFINITE_REGEXP.match(string) in { sign: }
        Infinite.new(sign: Sign.for(name: sign))
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

    Finite = Data.define(:rational) do
      include Helpers::Mask

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
