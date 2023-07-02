module Wasminna
  class Memory < Data.define(:bytes, :maximum_size)
    include Helpers::Mask
    include Helpers::SizeOf
    extend Helpers::SizeOf

    BITS_PER_BYTE = 8
    BYTES_PER_PAGE = 0x10000
    MAXIMUM_PAGES = 0x10000

    def self.from_limits(minimum_size:, maximum_size:)
      bytes = "\0" * (minimum_size * BYTES_PER_PAGE)
      maximum_size =
        if maximum_size.nil?
          MAXIMUM_PAGES
        else
          maximum_size.clamp(..MAXIMUM_PAGES)
        end
      new(bytes:, maximum_size:)
    end

    def load(offset:, bits:)
      size_of(bits, in: BITS_PER_BYTE).times
        .map { |index| bytes.getbyte(offset + index) }
        .map.with_index { |byte, index| byte << index * BITS_PER_BYTE }
        .inject(0, &:|)
    end

    def store(value:, offset:, bits:)
      size_of(bits, in: BITS_PER_BYTE).times do |index|
        byte = mask(value >> index * BITS_PER_BYTE, bits: BITS_PER_BYTE)
        bytes.setbyte(offset + index, byte)
      end
    end

    def grow_by(pages:)
      if maximum_size.nil? || size_in_pages + pages <= maximum_size
        bytes << "\0" * (pages * BYTES_PER_PAGE)
        true
      else
        false
      end
    end

    def size_in_pages
      size_of(bytes.bytesize, in: BYTES_PER_PAGE)
    end
  end
end
