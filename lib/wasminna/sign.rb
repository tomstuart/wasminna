module Wasminna
  class Sign
    private_class_method :new
    PLUS, MINUS = 2.times.map { new }
    def PLUS.to_i = +1
    def PLUS.!@ = MINUS
    def MINUS.to_i = -1
    def MINUS.!@ = PLUS

    def self.for(name:) = name == '-' ? MINUS : PLUS
    def positive? = to_i.positive?
    def negative? = to_i.negative?
    def <=>(other) = to_i <=> other.to_i
    def coerce(other) = [other, to_i]

    module Conversion
      refine ::Float do
        def sign = angle.positive? ? MINUS : PLUS
      end

      refine ::Rational do
        def sign = negative? ? MINUS : PLUS
      end
    end
  end
end
