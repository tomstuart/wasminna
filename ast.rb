module AST
  Return = Struct.new(nil)
  LocalGet = Struct.new(:index, keyword_init: true)
  LocalSet = Struct.new(:index, keyword_init: true)
  LocalTee = Struct.new(:index, keyword_init: true)
  BrIf = Struct.new(:index, keyword_init: true)
end
