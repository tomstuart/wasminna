require 'float'

def main
  assert_float_encoding 0x4049_0fdb, 3141592653589793r / 10 ** 15, bits: 32
  assert_float_encoding 0x5eff_ffff, 0x7fffff4000000001r, bits: 32
  assert_float_encoding 0x0000_0000, 0r, bits: 32
  assert_float_encoding 0x4f00_0000, 0x7fffffffr, bits: 32

  assert_float_encoding 0x3ff0_0000_0000_0000, 1r, bits: 64

  assert_float_decoding 0r, false, 0x0000_0000, bits: 32
  assert_float_decoding 1r / 2 ** 149, false, 0x0000_0001, bits: 32
end

def assert_float_encoding(expected, rational, negated: false, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float::Finite.new(rational:, negated:).encode(format:)
  raise "expected #{expected}, got #{actual}" unless actual == expected
end

def assert_float_decoding(expected_rational, expected_negated, encoded, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float.decode(encoded, format:)
  raise actual.inspect unless [actual.rational, actual.negated] == [expected_rational, expected_negated]
end

main
