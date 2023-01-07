require 'wasminna/float/finite'
require 'wasminna/float/infinite'
require 'wasminna/float/nan'
require 'wasminna/float/zero'
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
  end
end
