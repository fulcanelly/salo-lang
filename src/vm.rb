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
            @fetch_uint_cache = []

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
            code << encode(:LEAVE)
            #@main_size = self.code.size

            chunk.constpool
            	.filter { _1.class == Function }
            	.each { |func| 
            		func.position = @code.size
            		@code.push(*func.bytecode)
            	}

            #todo 
            #spread all functions in one chunk

        end

        def get_f_pointer()
        end

        def push(entry)
            @chunk = entry.clone
            compose()
        end

        def run
        #	counter = Hash.new(0)
            while @ppointer < code.size or not self.it_top_level
                instruction = code[@ppointer]
               # counter[decode instruction] += 1
                @ppointer += 1
            	self.opcodes[instruction].call
            end
            #pp counter
        end

        def execute(byte)
        	self.opcodes[byte].call

        end


        #todo
        #make caching
        def fetch_uint()
            point = self.ppointer
            self.ppointer += 4


            if res = @fetch_uint_cache[ppointer] then 
                return res 
           else 

                range = point..(point + 3)
                bytes = self.code[range]

                @fetch_uint_cache[ppointer] = unpack_uint32(bytes) 
            end
        end

        #todo
        #Opcode = Struct.new(:run, :dec, :name, :doc)

        def add_op(name, &block)
            @forencode[name] = (@op_counter += 1)
            raise 'too much opcodes' if @op_counter > 255
            @opcodes[@op_counter] = block
        end

        #todo
        #make caching
        def get_const_by_index()
            res = @chunk.constpool[ fetch_uint() ]
            return res
        end

        class CallFrame < Struct.new(:pointer, :scope, :what)

        end

        def it_top_level
            self.call_stack.size == 0
        end

        def stop_machine
        	@ppointer = @code.size
        end

        def init_opcodes()

            add_op :LOAD_CONST do
                stack << get_const_by_index()
            end

            add_op :LOAD_NOTHING do 
                stack << Nothing.it
            end

            add_op :LOAD_TRUE do 
                stack << true
            end
            
            add_op :LOAD_FALSE do 
                stack << false
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

            add_op :NOP do 
            end
            #todo 
            add_op :FUNCALL do
                fobj = stack.pop
                args_count = fetch_uint()
                args = stack.pop args_count

                call_stack << CallFrame.new(self.ppointer, self.var_scope, fobj)
                self.ppointer = fobj.position
                self.var_scope = Scope.new(fobj.upper)
                fobj.pass_args(var_scope, args)
       
            end

            add_op :NATIVE_CALL do 
				fobj = stack.pop
                args_count = fetch_uint()
                args = stack.pop args_count
                self.stack << fobj.call(*args)
            end


            add_op :MAKE_FUNCTION do 
                funobj = get_const_by_index()
                funobj.upper = self.var_scope
                stack << funobj
            end

            add_op :JUMP_FORWARD do 
                self.ppointer += fetch_uint() 
            end

            add_op :TEST do 
                item = stack.pop
                @jump_flag = item ? true : false 
            end

            add_op :JUMP_UNLESS do 
                bool = stack.pop
                shift = fetch_uint()
                self.ppointer += shift unless bool
            end

            add_op :LEAVE do 
                frame = call_stack.pop
                if frame == nil then 
                	stop_machine 
                else 
	                self.ppointer = frame.pointer
	                self.var_scope = frame.scope
	            end
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
                :<= => 'elt',
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
               # vm.var_scope.get(:__print__).set(method :puts)

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

        attr_accessor :upper, :bytecode, :args_info, :func_info, :position

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

        def inspect 

            "- : function <<#{bytecode.join(", ")}>>"
        end

        def to_s 
            inspect
        end

    end

end #module SaloPlatform
vm = SaloPlatform::VM.inst

chunk = SaloPlatform::BytecodeChunk.new

class BytecodeBuilder 


    class Mark
        attr_accessor :id, :size, :builder

        def self::gen_id
            @count ||= 0
            @count += 1
        end

        def initialize(size, builder)
            @id = self.class.gen_id
            @size = size
            @builder = builder
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

        def replace(with)
            builder.replace_marked(self, with)
        end

    end

    def init_std 

        def_meth [ SaloPlatform::ArgInfo.new(:dont_matter) ]
        stack.last.upper = Scope.new(nil)

 		stack.last.upper.get(:__print__).set(method :puts)

        self.emit [ 
        	:LOAD_VAR, *pack_uint32(add_const :dont_matter),
        	:LOAD_VAR, *pack_uint32(add_const :__print__),
        	:NATIVE_CALL, *pack_uint32(1),
        	:LEAVE
        ]
        
        self.emit [
        	:LOAD_CONST, *pack_uint32(done_meth),
        	:STORE_VAR, *pack_uint32(add_const :print)
        ]

    end

    def it_top_level
        self.stack.size == 1
    end

    def mark(size = 4)
        Mark.new(size, self)
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
        self.init_std()
    end

    def bytecode 
        self.stack.last.bytecode
    end

    def def_meth(args)
        stack << SaloPlatform::Function::new.tap do |it|
            it.args_info = args
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
