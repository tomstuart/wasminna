require 'float'

def main
  assert_float_encoding 0x4049_0fdb, 3141592653589793, 10 ** 15, bits: 32
  assert_float_encoding 0x5eff_ffff, 0x7fffff4000000001, 1, bits: 32
  assert_float_encoding 0x0000_0000, 0, 2 ** 149, bits: 32
  assert_float_encoding 0x4f00_0000, 0x7fffffff, 1, bits: 32

  assert_float_encoding 0x3ff0_0000_0000_0000, 1, 1, bits: 64

  assert_float_decoding 0, 2 ** 149, false, 0x0000_0000, bits: 32
  assert_float_decoding 1, 2 ** 149, false, 0x0000_0001, bits: 32
end

def assert_float_encoding(expected, numerator, denominator, negated: false, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float::Finite.new(numerator:, denominator:, negated:).encode(format:)
  raise "expected #{expected}, got #{actual}" unless actual == expected
end

def assert_float_decoding(expected_numerator, expected_denominator, expected_negated, encoded, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float.decode(encoded, format:)
  raise actual.inspect unless [actual.numerator, actual.denominator, actual.negated] == [expected_numerator, expected_denominator, expected_negated]
end

main
