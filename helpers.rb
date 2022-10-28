module Helpers
  module Mask
    private

    def mask(value, bits:)
      size = 1 << bits
      value & (size - 1)
    end
  end

  module SizeOf
    private

    def size_of(value, **kwargs)
      quotient, remainder = value.divmod(kwargs.fetch(:in))
      if remainder.zero?
        quotient
      else
        quotient + 1
      end
    end
  end
end
