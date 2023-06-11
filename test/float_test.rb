assert_encode 3141592653589793r / 10 ** 15, 0x4049_0fdb, bits: 32
assert_encode 0x7fffff4000000001r, 0x5eff_ffff, bits: 32
assert_encode 0r, 0x0000_0000, bits: 32
assert_encode 0x7fffffffr, 0x4f00_0000, bits: 32

assert_encode 1r, 0x3ff0_0000_0000_0000, bits: 64
assert_encode 6723256985364377r, 0x4337_e2c4_4058_a799, bits: 64

assert_decode 0x0000_0000, Wasminna::Float::Zero.new(sign: Wasminna::Sign::PLUS), bits: 32
assert_decode 0x0000_0001, Wasminna::Float::Finite.new(rational: 1r / 2 ** 149), bits: 32

BEGIN {
  require 'wasminna/float'
  require 'wasminna/float/finite'
  require 'wasminna/float/format'
  require 'wasminna/float/zero'
  require 'wasminna/sign'

  def assert_encode(input, expected, bits:)
    format = Wasminna::Float::Format.for(bits:)
    actual = Wasminna::Float::Finite.new(rational: input).encode(format:)
    if actual == expected
      print "\e[32m.\e[0m"
    else
      raise "expected #{expected}, got #{actual}"
    end
  end

  def assert_decode(input, expected, bits:)
    format = Wasminna::Float::Format.for(bits:)
    actual = Wasminna::Float.decode(input, format:)
    if actual == expected
      print "\e[32m.\e[0m"
    else
      raise "expected #{expected}, got #{actual}"
    end
  end
}

END {
  puts
}
