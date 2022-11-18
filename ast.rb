module AST
  Return = Data.define
  LocalGet = Data.define(:index)
  LocalSet = Data.define(:index)
  LocalTee = Data.define(:index)
  BrIf = Data.define(:index)
  Select = Data.define
  Nop = Data.define
  Call = Data.define(:index)
  Drop = Data.define
  Block = Data.define(:label, :results, :body)
  Loop = Data.define(:label, :results, :body)
  If = Data.define(:label, :results, :consequent, :alternative)
  Const = Data.define(:type, :bits, :number)
  Load = Data.define(:type, :bits, :offset)
  Store = Data.define(:type, :bits, :offset)
  UnaryOp = Data.define(:type, :bits, :operation)
  BinaryOp = Data.define(:type, :bits, :operation)
  Unreachable = Data.define
  BrTable = Data.define(:target_indexes, :default_index)
  Br = Data.define(:index)
  CallIndirect = Data.define(:table_index, :type_index)
  GlobalSet = Data.define(:index)
end
