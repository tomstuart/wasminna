require 'float'
require 'sign'

def main
  assert_float_encoding 0x4049_0fdb, 3141592653589793r / 10 ** 15, bits: 32
  assert_float_encoding 0x5eff_ffff, 0x7fffff4000000001r, bits: 32
  assert_float_encoding 0x0000_0000, 0r, bits: 32
  assert_float_encoding 0x4f00_0000, 0x7fffffffr, bits: 32

  assert_float_encoding 0x3ff0_0000_0000_0000, 1r, bits: 64

  assert_float_decoding Wasminna::Float::Zero.new(sign: Sign::PLUS), 0x0000_0000, bits: 32
  assert_float_decoding Wasminna::Float::Finite.new(rational: 1r / 2 ** 149), 0x0000_0001, bits: 32
end

def assert_float_encoding(expected, rational, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float::Finite.new(rational:).encode(format:)
  raise "expected #{expected}, got #{actual}" unless actual == expected
end

def assert_float_decoding(expected, encoded, bits:)
  format = Wasminna::Float::Format.for(bits:)
  actual = Wasminna::Float.decode(encoded, format:)
  raise "expected #{expected}, got #{actual}" unless actual == expected
end

main
