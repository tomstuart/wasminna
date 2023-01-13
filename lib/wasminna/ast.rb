module Wasminna
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
    Block = Data.define(:type, :body)
    Loop = Data.define(:type, :body)
    If = Data.define(:type, :consequent, :alternative)
    Const = Data.define(:type, :bits, :number)
    Load = Data.define(:type, :bits, :storage_size, :sign_extension_mode, :offset)
    Store = Data.define(:type, :bits, :storage_size, :offset)
    UnaryOp = Data.define(:type, :bits, :operation)
    BinaryOp = Data.define(:type, :bits, :operation)
    Unreachable = Data.define
    BrTable = Data.define(:target_indexes, :default_index)
    Br = Data.define(:index)
    CallIndirect = Data.define(:table_index, :type_index)
    GlobalSet = Data.define(:index)
    MemoryGrow = Data.define
    GlobalGet = Data.define(:index)
    Function = Data.define(:exported_names, :type_index, :locals, :body)
    Memory = Data.define(:string, :minimum_size, :maximum_size)
    Table = Data.define(:name, :elements)
    Global = Data.define(:value)
    Module = Data.define(:name, :functions, :memory, :tables, :globals, :types, :datas)
    Invoke = Data.define(:module_name, :name, :arguments)
    AssertReturn = Data.define(:action, :expecteds)
    NanExpectation = Data.define(:nan, :bits)
    SkippedAssertion = Data.define
    Type = Data.define(:parameters, :results)
    MemorySize = Data.define
    MemoryData = Data.define(:offset, :string)
    RefNull = Data.define
    RefExtern = Data.define
    Get = Data.define(:module_name, :name)
  end
end
