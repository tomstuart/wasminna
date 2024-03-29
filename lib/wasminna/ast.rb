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
    Function = Data.define(:type_index, :locals, :body)
    Memory = Data.define(:minimum_size, :maximum_size)
    Table = Data.define(:name, :minimum_size, :maximum_size)
    Global = Data.define(:value)
    Module = Data.define(:name, :functions, :memories, :tables, :globals, :types, :datas, :exports, :imports, :elements, :start)
    Invoke = Data.define(:module_name, :name, :arguments)
    AssertReturn = Data.define(:action, :expecteds)
    NanExpectation = Data.define(:nan, :bits)
    SkippedAssertion = Data.define
    Type = Data.define(:parameters, :results)
    MemorySize = Data.define
    DataSegment = Data.define(:string, :mode)
    module DataSegment::Mode
      Passive = Data.define
      Active = Data.define(:index, :offset)
    end
    RefNull = Data.define
    RefExtern = Data.define(:value)
    Get = Data.define(:module_name, :name)
    Export = Data.define(:name, :kind, :index)
    Import = Data.define(:module_name, :name, :kind, :type)
    RefFunc = Data.define(:index)
    TableInit = Data.define(:table_index, :element_index)
    Register = Data.define(:module_name, :name)
    TableGet = Data.define(:index)
    TableSet = Data.define(:index)
    ElementSegment = Data.define(:items, :mode)
    module ElementSegment::Mode
      Passive = Data.define
      Active = Data.define(:index, :offset)
      Declarative = Data.define
    end
    MemoryFill = Data.define
    MemoryCopy = Data.define
    MemoryInit = Data.define(:index)
    DataDrop = Data.define(:index)
    ElemDrop = Data.define(:index)
    TableCopy = Data.define(:destination_index, :source_index)
    RefIsNull = Data.define
    AssertTrap = Data.define(:action, :failure)
    TableFill = Data.define(:index)
    TableGrow = Data.define(:index)
    TableSize = Data.define(:index)
  end
end
