class Sign
  private_class_method :new
  PLUS, MINUS = 2.times.map { new }
  def PLUS.to_i = +1
  def MINUS.to_i = -1

  def positive? = to_i.positive?
  def negative? = to_i.negative?
  def <=>(other) = to_i <=> other.to_i
end
