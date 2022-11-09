module AST
  Return = Struct.new(nil)
  LocalGet = Struct.new(:index, keyword_init: true)
  LocalSet = Struct.new(:index, keyword_init: true)
  LocalTee = Struct.new(:index, keyword_init: true)
  BrIf = Struct.new(:index, keyword_init: true)
  Select = Struct.new(nil)
  Nop = Struct.new(nil)
  Call = Struct.new(:index, keyword_init: true)
  Drop = Struct.new(nil)
  Block = Struct.new(:label, :body, keyword_init: true)
  Loop = Struct.new(:label, :body, keyword_init: true)
  If = Struct.new(:label, :consequent, :alternative, keyword_init: true)
end
