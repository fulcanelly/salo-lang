require_relative './utils'

include Utils

module SaloPlatform

    
    class VM

        Opcodes = [
            :LOAD_CONST,
            :LOAD_VAR,
            :LOAD_NIL,
            :LOAD_FIELD,

            :STORE_FIELD,
            :STORE_VAR,
            :FUNCALL,
            
            :RETURN_NIL,
            :LEAVE,
            :STOP_OR_RET,
            :MAKE_FUNCTION
        ]

        attr_accessor :ppointer, :stack, :opcodes, :code, :var_scope, :chunk, :forencode

        def initialize
            @ppointer = 0
            @stack = []

            @var_scope = Scope.new

            @code = nil
            @opcodes = []
            @op_counter = 0
            @call_stack = []

            @forencode = {}
        end

        attr_accessor :func_adresses, :run, :chunk, :call_stack

        def compose()
            self.code = self.chunk.bytecode
           # self.func_adresses = Hash.new
        end

        def get_f_pointer()
        end

        def push(entry)
            @chunk = entry.clone
            compose()
        end

        def run
            
            while self.ppointer < code.size
                instruction = code[self.ppointer]
               # pp call_stack.size
                #puts
              #  raise 'no such opcode ' unless instruction 

               # print decode instruction#if self.mode.verbose
                self.ppointer += 1
                execute(instruction)
            end
        end

        def execute(byte)
            self.opcodes[byte].call
        end

        def fetch_uint()
            point = self.ppointer
            range = point..(point + 3)
            bytes = self.code[range]
            self.ppointer += 4
            unpack_uint32(bytes) 
        end

        #todo
        #Opcode = Struct.new(:run, :dec, :name, :doc)

        def add_op(name, &block)
            @forencode[name] = (@op_counter += 1)
            raise 'too much opcodes' if @op_counter > 255
            @opcodes[@op_counter] = block
        end

        #todo
        #rethink name 
        def get_const_by_index()
            res = @chunk.constpool[ fetch_uint() ]
            return res
        end

        class CallFrame < Struct.new(:pointer, :bytecode, :scope, :what)

        end

        def init_opcodes()

            add_op :LOAD_CONST do
                stack << get_const_by_index()
            end

            add_op :LOAD_NOTHING do 
                stack << Nothing.it
            end

            add_op :LOAD_VAR do
                val = get_const_by_index()
                stack << @var_scope.get(val).show
            end

            add_op :STORE_VAR do 
                val = get_const_by_index()
                @var_scope.get(val).set stack.pop 
            end

            add_op :DEBUG_PRINT do 
                pp stack.pop
            end 

            #todo 
            add_op :FUNCALL do
                fobj = stack.pop
                args_count = fetch_uint()
                args = stack.pop args_count

                case fobj
                when Function
                    call_stack << CallFrame.new(self.ppointer, self.code, self.var_scope, fobj)
                    self.ppointer = 0
                    self.code = fobj.bytecode
                    self.var_scope = Scope.new(fobj.upper)
                    fobj.pass_args(var_scope, args)
                else
                    #fobj.call(*args)
                    self.stack << fobj.call(*args)
                end
            end

            add_op :MAKE_FUNCTION do 
                funobj = get_const_by_index()
                funobj.upper = self.var_scope
                stack << funobj
            end

            add_op :JUMP_TO do 
                point = fetch_uint()
                self.ppointer = point 
                @jump_flag = true 
            end

            add_op :TEST do 
                item = stack.pop
                @jump_flag = item ? true : false 
            end

            add_op :JUMP_TO_UNLESS do 
                bool = stack.pop
                point = fetch_uint()
                self.ppointer = point unless bool
            end

            add_op :LEAVE do 
                frame = call_stack.pop
                self.ppointer = frame.pointer
                self.code = frame.bytecode
                self.var_scope = frame.scope
            end

            add_op :POP do 
                self.stack.pop
            end

            add_op :DUP do 
                stack << stack.last
            end

            gen_op = proc do |op, name|
                add_op :"OPT_#{name.upcase}" do 
                    popped = stack.pop(2)
                    stack << popped.first.send(op, popped.last)
                end
            end

            ops = {
                :+ => 'plus',
                :- => 'minus',
                :/ => 'divide',
                :* => 'mult',
                :> => 'gt',
                :< => 'lt',
                :== => 'eq',
                :>= => 'egt',
                :<= => 'elt'
            }
            
            ops.each(&gen_op)

        end

        def encode(name) 
            @forencode[name]
        end

        def encode_arr(arr)
            arr.map do |op|
                case op
                when Symbol
                    encode(op)
                else
                    op
                end
            end
        end
        
        def decode(code)
            @forencode.find do |name, op|
                return name if op == code
            end
        end
        
    end

    class << VM

        def inst 
            @i ||= begin
                vm = VM.new
                vm.init_opcodes
                vm.var_scope.get(:print).set(method :puts)
                vm
            end 
        end 

    end


    class BytecodeChunk  
        attr_accessor :bytecode, :constpool

        def initialize
            @bytecode = []
            @constpool = []
        end

    end

    class ArgInfo < Struct.new(:name, :default, :type)
    end

    class FuncInfo 
        attr_accessor :name
    end

    class SyntheticPair
        "
        The purpose of this class is to use it 
        for passing named arguments or creating named tuples 
        "

        attr_accessor :first, :last
    end


    class Nothing 
        "
        Internal analogue of nil / null
        "

        def self.it
            @it = @it or Nothing.new
        end

        def inspect
            to_s
        end
        
        def to_s
            "nothing" 
        end
    end


    class Function

        def initialize
            @bytecode = []
        end

        attr_accessor :upper, :bytecode, :args_info, :func_info

        #todo
        def chek_args(args)
        end

        def pass_args(scope, args)
            self.args_info.zip(args) do |ainfo, value|
                value = value or ainfo.default 
                raise 'not enough arguments error ?' unless value
                scope.local_get(ainfo.name).set value
            end
        end

    end

end #module SaloPlatform
vm = SaloPlatform::VM.inst

chunk = SaloPlatform::BytecodeChunk.new

class BytecodeBuilder 


    class Mark
        attr_accessor :id, :size

        def self::gen_id
            @count ||= 0
            @count += 1
        end

        def initialize(size)
            @id = self.class.gen_id
            @size = size
        end

        def spread 
            Array.new(self.size) do self end
        end
        
        def ==(another)
            case another
            when self.class
                another.id == self.id
            else
                false
            end
        end
    end

    def it_top_level
        self.stack.size == 1
    end

    def mark(size = 4)
        Mark.new(size)
    end
    
    def replace_marked(type, res)
        index = bytecode.index do _1 == type end
        bytecode[index...(index + type.size)] = res
        debug[index...(index + type.size)] = res
    end

    #def emit(code: [byte]) -> int
    def emit(code) 
        self.debug.push(*code)

        code = vm::encode_arr(code)
        self.bytecode.push(*code)
        return code.size
    end

    attr_accessor :vm, :stack, :constpool
    attr_accessor :debug

    def size 
        stack.last.bytecode.size
    end

    def initialize
        @debug = []
        self.stack = [ SaloPlatform::BytecodeChunk.new ]
        self.constpool = stack.last.constpool
        self.vm = SaloPlatform::VM.inst
    end

    def bytecode 
        self.stack.last.bytecode
    end

    def def_meth(args)
        stack << SaloPlatform::Function::new.tap do |it|
            it.args_info = [ ]::tap do |ainfo|
                args.each do |arg|
                    ainfo << SaloPlatform::ArgInfo.new(arg.value, nil, nil)
                end
            end
        end
    end

    def done_meth
        add_const stack.pop
    end

    def add_const(value)
        index = self.constpool.index(value)
        unless index
            constpool << value
            return constpool.size - 1
        end 
        return index 
    end

    def compile(ast)
        ast.generate(self)
    end

end
