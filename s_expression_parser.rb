class SExpressionParser
  def parse(string, &)
    return to_enum(__method__, string) unless block_given?

    self.string = string
    parse_expressions(terminated_by: %r{\z}, &)
    read %r{\z}
  end

  private

  attr_accessor :string

  def parse_expressions(terminated_by:)
    return to_enum(__method__, terminated_by:) unless block_given?

    loop do
      skip_whitespace_and_comments
      break if can_read? terminated_by
      yield parse_expression
    end
  end

  def parse_expression
    if can_read? %r{\(}
      parse_list
    elsif can_read? %r{"}
      parse_string
    else
      parse_atom
    end
  end

  def skip_whitespace_and_comments
    loop do
      if can_read? %r{[ \n]+}
        read %r{[ \n]+}
      elsif can_read? %r{;;.*$}
        read %r{;;.*$}
      else
        break
      end
    end
  end

  def parse_list
    read %r{\(}
    expressions = parse_expressions(terminated_by: %r{\)}).entries
    read %r{\)}
    expressions
  end

  def parse_string
    read %r{"}
    string = read %r{(\\"|[^"])*}
    read %r{"}
    %Q{"#{string}"}
  end

  def parse_atom
    read %r{[^() \n;]+}
  end

  def can_read?(pattern)
    !try_match(pattern).nil?
  end

  def read(pattern)
    match = try_match(pattern) || complain(pattern)
    self.string = match.post_match
    match.to_s
  end

  def try_match(pattern)
    %r{\A#{pattern}}.match(string)
  end

  def complain(pattern)
    raise "couldn’t match #{pattern} in #{string.inspect}"
  end
end
