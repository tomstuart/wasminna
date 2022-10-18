module Wasminna
  module Float
    module_function

    def encode(numerator, denominator, negated:, bits:)
      exponent_bits, significand_bits =
        case bits
        in 32
          [8, 24]
        in 64
          [11, 53]
        end
      exponent_bias = (1 << (exponent_bits - 1)) - 1
      fraction_bits = significand_bits - 1

      # calculate the range of valid significands
      min_significand = 1 << (significand_bits - 1)
      max_significand = (1 << significand_bits) - 1

      if numerator.zero?
        exponent = 0
        significand = 0
      else
        # initialise the exponent to account for normalised significand format
        exponent = fraction_bits

        numerator, denominator, exponent =
          scale_significand(numerator, denominator, min_significand, max_significand, exponent)

        # round the significand if necessary
        significand, remainder = numerator.divmod(denominator)
        if remainder > denominator / 2 || (remainder == denominator / 2 && significand.odd?)
          significand += 1
          numerator, denominator, exponent =
            scale_significand(significand, 1, min_significand, max_significand, exponent)
          significand = numerator / denominator
        end

        # add bias to exponent
        exponent += exponent_bias
      end

      # assemble bits into float
      sign = negated ? 1 : 0
      fraction = significand & ((1 << fraction_bits) - 1)
      (sign << exponent_bits | exponent) << fraction_bits | fraction
    end

    def scale_significand(numerator, denominator, min_significand, max_significand, exponent)
      # scale the significand up/down until it’s in range
      # and adjust the exponent to account for scaling
      loop do
        significand = numerator / denominator

        if significand < min_significand
          numerator <<= 1
          exponent -= 1
        elsif significand > max_significand
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