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

  module MatchPattern
    refine MatchData do
      def deconstruct_keys(keys)
        named_captures.transform_keys(&:to_sym).then do |captures|
          if keys
            captures.slice(*keys)
          else
            captures
          end
        end
      end
    end
  end
end
