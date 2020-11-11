require 'rly'
require "rly/helpers"
require 'yaml'
require 'benchmark'

require_relative './utils'


def camel_to_snake(str)
    str.scan(/[A-Z][a-z]*/).map(&:downcase).join("_")
end

class ASTNode

    def run(scope)
        raise 'abstaract method called'
    end

    def abstaract_meth_err
        raise 'abstaract method called'
    end

    def get_val(scope)
        run(scope)
    end

    def accept(visiotor)
        methname = camel_to_snake(self.class.to_s).to_sym
        visiotor.send(methname, self)
    end

    def accept_inner(visiotor)
    	self.ivars.each do |name|
    		value = self.ivar_get(name)
    		value.accept(visiotor) if value
    	end
    end

end

def genASTNode(**args)
    Class.new(ASTNode) do
        attr_accessor *args.keys

        def_meth :initialize do |**entries|
            entries.each do |name, value|
                raise ArgumentError.new unless args.include?(name)
                ivar_set(name, value)
            end
            args.each do |name, defval|
                ivar_set(name, defval) unless entries[name]
            end
        end
    end
end

class CallByName < genASTNode target: nil, name: nil, arg: nil
    
    def run(scope)
        target.get_val(scope).send(name.to_sym, *[ arg.get_val(scope) ])
    end

    def self::ops 
        @ops ||= {
            :+ => 'plus',
            :- => 'minus',
            :/ => 'divide',
            :* => 'mult',
            :> => 'gt',
            :< => 'lt',
            :== => 'eq',
            :>= => 'egt',
            :<= => 'elt',
            :-@ => 'prmns'
        }
    end

    def generate(builder, pop_result = true)
       
        target.generate(builder, false)
        arg.generate(builder, false) if arg

        opcode = [
            :"OPT_#{ self.class.ops[name.to_sym].upcase }",
        ]
        opcode << :POP if pop_result

        builder.emit(opcode)
    end

end

class CodeNode < genASTNode(code: [], type: 'non-function')

    class JumpPurposedException < Exception
        attr_accessor :value

        def initialize(value)
            @value = value
            super
        end
    end

    def generate(builder, pop_result = true)
     	ccode = code.clone
        last = ccode.pop

        ccode.each do |one|
            one.generate(builder)
        end
        
        last.generate(builder, pop_result) if last
        
    end


    def run(scope)
        result = nil
        
        func_runable = proc do |node|
            begin
                result = node.get_val(scope)
            rescue JumpPurposedException => e
                return e.value
            end
        end
        
        def_runable = proc do |node|
            result = node.get_val(scope)
        end

        runable = if type == :function then func_runable else def_runable end
        code.each &runable
        return result
    end
end


#todo
# + raise error when amount of args dont match -- done
# * REW argument names repeats
class FuncDef < genASTNode(name: nil, args: [], code: nil)

    def run(scope)
        func = proc do |*passed|
            passed_clone = passed.clone
            local_scope = Scope.new()

            #passing arguments
            args.each do |name|
                local_scope.get(name.value).set(passed.shift)
            end

            #checking is all args passed
            unless passed_clone.size == args.size
                error = 'wrong number of arguments: expeceted %p, given %p'
                full = error % [args.size, passed_clone.size]
                raise full
            end

            local_scope.super = scope
            #runing function
            code.run(local_scope)
        end
        scope.get(name.value).set(func)
    end

    def generate(builder, pop_result = true)
        prepared_args = args.map do |arg|
            SaloPlatform::ArgInfo.new(arg.value, nil, nil)
        end

        builder.def_meth(prepared_args)
        code.generate(builder, false)

        fobj_i = builder.done_meth
        name_i = builder.add_const(self.name.value) 
        
        code = [
            :MAKE_FUNCTION, *pack_uint32(fobj_i),
            :STORE_VAR, *pack_uint32(name_i)
        ]


        code.push [ 
            :LOAD_NOTHING
        ] unless pop_result

        builder.emit(code)
    end

end

class FunCall < genASTNode(what: nil, args: [])

    def obtain_fun_ref(scope)
        what.get_val(scope)
    end

    def self::stacktrace
        @s ||= []
    end

    def run(scope)
        fun = obtain_fun_ref(scope)
        res = args.map do _1.get_val(scope) end
        self.class.stacktrace << {
            'what' => what,
            'args' => res,
        }

        for_ret = fun.(*res)
        self.class.stacktrace.pop
        return for_ret
    end

    def generate(builder, pop_result = true)
        
        args.each do |arg| 
            arg.generate(builder, false)
        end

        what.generate(builder, false)

        code = [
            :FUNCALL, *pack_uint32(args.size)
        ]

        code << :POP if pop_result
        builder.emit(code)
    end
    
end

class GetField < genASTNode of_what: nil, name: nil
    def run(scope)
        get_ref(scope).show
    end

    def get_ref(scope)
        of_what.get_val(scope).get(name.value)
    end
end

class Assign < genASTNode(what: nil, new_val: nil)

    def obtain_ref(scope)
        what.get_ref(scope)
    end

    #@returns {Field}
    def run(scope)
        val = new_val.get_val(scope)
        obtain_ref(scope).set(val)
        return val
    end

    def generate(builder, pop_result = true)
        case what
        when IdentContatiner
            self.new_val.generate(builder, false)
            index = builder.add_const what.value

            code = unless pop_result then [ :DUP ] else [ ] end
            code.push(:STORE_VAR, *pack_uint32(index))
            builder.emit(code)
        else
            raise 'not implemented '
        end
    end

end

class Container < genASTNode(value: nil)
    def get_val(unused_scope)
        self.value
    end

    def generate(builder, pop_result = true)

        index = builder.add_const self.value
        code = [
            :LOAD_CONST, *pack_uint32(index),
        ]
        code << :POP if pop_result

        builder.emit(code)
        
    end

end

class ObjectNode < genASTNode(name: String.new, block: CodeNode.new)


    def run(scope)
        object_scope = Scope.new(scope)
        block.run(object_scope)
        scope.get(name).set(object_scope)
    end

end

class NumberContainer < Container
end

class StringContainer < Container

    def initialize(value: String.new)
        value = value[1..-2].sub('\\\'', '\'')
        super value: value
    end

end

class IdentContatiner < Container
    def get_ref(scope)
        scope.get(self.value)
    end

    def generate(builder, pop_result = true)

        index = builder.add_const self.value
        code = [
            :LOAD_VAR, *pack_uint32(index),
        ]
        code << :POP if pop_result

        builder.emit(code)
        
    end
end

class Importer < genASTNode(path: [String])
    def get_val(scope)
        fpath = [ Runner.start_path ] + path.map(&:value).map(&:to_s)
        fpath[-1] = fpath[-1] + ".salo"
        file = File.open fpath.join('/'), 'r'

        itscope = Runner.new(file).run
        scope.get(path.last.value).set(itscope)
        nil
    end
end

class Variable < IdentContatiner
    
    def get_val(scope)
        ref = scope.find(self.value)
        raise 'undeclared variable \'%s\'' % value unless ref
        return ref.show
    end

    def __generate(builder, pop_result = true)

        index = builder.add_const self.value
        builder.emit [
            :LOAD_VAR, *pack_uint32(index)
        ]  
        
    end

end

class Synthetic < ASTNode
end

class GetNothing < Synthetic
	
	def it 
		:LOAD_NOTHING
	end

	def generate(builder, pop_result = true)
		code = [ self.it ].tap do |it|
			it << :POP if pop_result 
		end
		builder.emit(code)
	end

end

class IfBranch < ASTNode

    attr_accessor :cond, :if_block, :else_block

    def initialize(cond: , block:, else_block: nil )
        self.cond = cond
        self.if_block = block
        self.else_block = else_block
    end

    def last
        return self if self.else_block == nil
        return self.else_block.last
    end

    def run(scope)
        res = cond.get_val(scope)
        temp_scope = Scope.new(scope)
        to_run = if res then if_block else else_block or CodeNode.new end
        to_run.run(temp_scope)
    end

    #todo
    #make jump relative
    def generate(builder, pop_result = true)
        
        cond.generate(builder, false)
        builder.emit [:JUMP_UNLESS, *(first = builder.mark).spread ] #jump to else_block
        start = builder.size
        
        if_block.generate(builder, pop_result)
        builder.emit [:JUMP_FORWARD, *(last = builder.mark).spread] if else_block
        
        first.replace(pack_uint32 (builder.size - start))
        start = builder.size + 1

        if else_block 
        	else_block.generate(builder, pop_result)
			last.replace(pack_uint32 (builder.size - start))
        end
    end

end

class Returner < ASTNode

    attr_accessor :value

    def run(scope)
        val = if value then value.get_val(scope) else nil end
        raise CodeNode::JumpPurposedException.new(val)
    end

    def initialize(value = nil)
        self.value = value
    end

    def generate(builder, pop_result = true)
        code = []

        if value
            value.generate(builder, false)
        else
            code << :LOAD_NOTHING
        end

        code << :LEAVE

        builder.emit(code)
    end

end

module Rly
    class Yacc
        def self.assign_rhs(idx = 1)
            proc do _1.value = _2.value end
        end

        def self.middle_setter()
            proc do |res, _, t, _| res.value = t.value end
        end
    end
end


class Visiotor 
end

class ASTCompiler < Visiotor
end

class SyntaxTreeAnalyst < Visiotor

    def code_node(node)
        res = if node.type == :function then 
            if node.code.size == 0 then 
                Returner.new
            end

            unless node.code.last.is_a? Returner then 
                Returner.new(node.code.pop) 
            end
        else
      		if node.code.size == 0 then 
                GetNothing.new
            end
        end

        node.code << res if res
        	
        node.code.each do 
            _1.accept(self)
        end

    end

	def if_branch(node)
		node.accept_inner(self)
	end

    def func_def(node)
    	args = node.args.map(&:value)
    	if args.uniq.size != args.size then 
    		raise 'arguments cant have same name' 
    	end
        node.code.accept(self)
    end

    def method_missing(name, *rest)
        nil
    end
end

class GetTrue < GetNothing
	def it 
		:LOAD_TRUE
	end
end

class GetFalse < GetNothing
	def it 
		:LOAD_FALSE
	end
end

class SaloParser < Rly::Yacc

    #don't seems to work
   # precedence :left,  '+', '-'
    #precedence :left,  '*', '/'
    #precedence :right, :UMINUS, :NOT
   # rule 'code : OPT_NLINE code OPT_NLINE', &middle_setter
    rule 'code : proto_code' do |res, code| res.value = CodeNode.new(code: code.value) end
    rule 'proto_code : ' do |res| res.value = [] end
    rule 'proto_code : stmt | stmt proto_code', &collect_to_a
    
 #  rule 'proto_code : stmt | stmt OPT_NLINE proto_code', &collect_to_a
#    rule 'proto_code : OPT_NLINE proto_code' do |res, _, code| res.value = code.value end

    rule 'exp_list : exp | exp exp_tail', &collect_to_a

    rule 'exp_tail : "," exp exp_tail' do |res, _, exp, tail|
        res.value = [ exp.value ] + tail.value
    end

    #rule 'lambda'
    rule 'object : OBJECT IDENT cblock' do |res, _, name, block|
        res.value = ObjectNode.new(name: name.value.value, block: block.value)
    end
    rule 'exp_tail : "," exp' do |res, _, last|
        res.value = [ last.value ]
    end

    rule 'stmt : exp | funcdef | object | if_cond | return | import', &assign_rhs

    rule 'doted_list : IDENT "." doted_list
        | IDENT ', &collect_to_a

    rule 'import : IMPORT doted_list' do |res, _, path|
        res.value = Importer.new path: path.value
    end

    rule 'exp : exp e_op exp 
        | exp t_op exp
        | exp cmpr_op exp' do |res, a, op, b|
        res.value = CallByName.new(
            target: a.value, name: op.value, arg: b.value
        )
    end

  #  rule 'bexp : bexp e_op term', &call_by_name
 #   rule 'term : term t_op exp', &call_by_name
 #   rule 'bexp : term ', &assign_rhs
    rule 'term : exp', &assign_rhs

    rule 'exp : funcall | value | assign | TRUE | NOTHING | FALSE', &assign_rhs

    rule 'var: IDENT' do |res, name|
        res.value = Variable.new(value: name.value.value)
    end


    rule 'value : var | get_field | NUMBER | STRING ', &assign_rhs
    rule 'prefix_op : "-" | "+"', &assign_rhs
    rule 'e_op : "+" | "-"', &assign_rhs
    rule 't_op : "*" | "/"', &assign_rhs
    rule 'get_field : exp "." IDENT' do |res, exp,  _, name|
        res.value = GetField.new(
            of_what: exp.value, name: name.value)
    end

    rule 'assign : IDENT "=" exp
        | get_field "=" exp' do |res, ident, _, exp|
        res.value = Assign.new(
            what: ident.value, new_val: exp.value)
    end

    rule 'id_list : ' do _1.value = [] end
    rule 'id_list : IDENT | IDENT "," id_list', &collect_to_a

    rule 'exp : "(" exp ")"', &middle_setter

    rule "exp : prefix_op exp" do |res, op, exp|
        res.value = CallByName.new(target: exp.value, name: (op.value + "@").to_sym)
    end

    rule 'funcdef : DEF IDENT "(" id_list ")" "{" code "}"' do |*p|
        p[7].value.type = :function
        p[0].value = FuncDef.new(
            name: p[2].value, args: p[4].value, code: p[7].value
        )
    end

    rule 'funcdef : DEF IDENT "{" code "}"' do |res, _, name, _, code, _| 
        code.value.type = :function
        res.value = FuncDef.new(
            name: name.value, code: code.value
        )
    end

    rule 'cblock : "{" code "}" ', &middle_setter

    rule 'if_block : IF exp cblock' do |res, _, exp, code|
        res.value = IfBranch.new(cond: exp.value, block: code.value)
    end

    rule 'if_block : IF exp THEN cblock' do |res, _, exp, _, code|
        res.value = IfBranch.new(cond: exp.value, block: code.value)
    end

    rule 'if_cond : if_block', &assign_rhs
    rule 'if_cond : if_block ELSE cblock' do |res, if_block, _, else_block|
        if_block.value.else_block = else_block.value
        res.value = if_block.value
    end

    rule 'if_cond : if_block elsif_block' do |res, if_block, elsif_block|
        if_block.value.else_block = elsif_block.value
        res.value = if_block.value
    end

    rule 'elsif_block : ELSIF exp "{" code "}" ' do
        _1.value = IfBranch.new(
            cond: _3.value, block: _5.value)
    end

    rule 'elsif_block : ELSIF exp "{" code "}" elsif_block' do
        _1.value = IfBranch.new(
            cond: _3.value, block: _5.value, else_block: _7.value)
    end

    rule 'if_cond : if_block elsif_block ELSE cblock' do |res, if_block, elsif_block, _, code|
        if_block.value.else_block = elsif_block.value
        elsif_block.value.last.else_block = code
        res.value = if_block.value
    end

    rule 'funcall : exp "(" exp_list ")"' do |res, exp, _, exp_list, _|
        res.value = FunCall.new(what: exp.value, args: exp_list.value)
    end

    rule 'funcall : exp "(" ")"' do |res, exp|
        res.value = FunCall.new(what:  exp.value)
    end

    rule 'return : RETURN exp' do |res, _ , exp|
        res.value = Returner.new exp.value
    end

    rule 'return : RETURN ' do |res|
        res.value = Returner.new
    end

    rule 'cmpr_op : IS_EQL | IS_EL | IS_EG | IS_NEQL | IS_G | IS_L', &assign_rhs
    lexer do

        literals '=+-.*/({})!,><'
        ignore " \n\t"

        token :OBJECT , 'object'
       # token :OPT_NLINE, /\n+/
        token :IS_EQL, '=='
        token :IS_NEQL,'!='
        token :IS_EG, '>='
        token :IS_EL, '<='
        token :IS_G, '>'
        token :IS_L, '<'
        token :LAMB, '=>'
        token :IF, 'if'
        token :ELSE, 'else'
        token :DEF, 'def'
        token :THEN, 'then'
        token :RETURN, 'return'
        token :ELSIF, 'elsif'
        token :IMPORT, 'import'

        token :NOTHING, 'nothing' do |t|
    		t.value = GetNothing.new
    		t
    	end

        token :TRUE, 'true' do |t|
        	t.value = GetTrue.new
        	t
        end 
        
        token :FALSE, 'false' do |t| 
        	t.value = GetFalse
        	t
        end
        
        token :COMMENT, /#.*/ do
            nil 
        end
        token :IDENT, /[a-zA-Z_][a-zA-Z0-9_]*/ do |t|
            t.value = IdentContatiner.new(value: t.value.to_sym)
            t
        end
        
        token :STRING, /\'.*\'/ do |t|
            t.value = StringContainer.new(value: t.value)
            t
        end

        token :NUMBER, /\d+/ do |t|
            t.value = NumberContainer.new(value: t.value.to_i)
            t
        end

        on_error do |t|
            puts "Illegal character #{t.value}"
            t.lexer.pos += 1
            nil
        end
    end

    def self.on_error(&block)
        super(block)
    end

    on_error do
        pp "Syntax error on", _1
        
    end

    def self.inst
        @inst ||= SaloParser.new
    end

    def self.parse(str)
        inst.parse(str, false)
    end
    #store_grammar 'grammar.txt'

end
