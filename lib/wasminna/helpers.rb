module Wasminna
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
        value.ceildiv(kwargs.fetch(:in))
      end
    end
  end
end
