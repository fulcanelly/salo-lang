require 'rly'
require "rly/helpers"
require 'yaml'
require 'benchmark'

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

end

#todo
class Object

    def def_meth(name, &block)
        define_method name, *block
    end

    def ivar_get(name)
        instance_variable_get(name)
    end

    def __form__name__(name)
        ("@" + name.to_s).to_sym
    end
    def ivar_set(name, value)
        name = ("@" + name.to_s).to_sym
        instance_variable_set(name, value)
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

class CallByName < genASTNode target: nil, name: nil, args: []
    def run(scope)

        args = @args.map do _1.get_val(scope) end
     
        target.get_val(scope).send(name, *args)
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
end

class Container < genASTNode(value: nil)
    def get_val(unused_scope)
        self.value
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
        res = get_ref(scope).show
       # raise 'undeclared variable \'%s\'' % value unless res
        return res
    end
end

class IfBranch < ASTNode

    attr_accessor :cond, :block, :else_block

    def initialize(cond: , block:, else_block: nil )
        self.cond = cond
        self.block = block
        self.else_block = else_block
    end

    def last
        return self if self.else_block == nil
        return self.else_block.last
    end

    def run(scope)
        res = cond.get_val(scope)
        temp_scope = Scope.new(scope)
        to_run = if res then block else else_block or CodeNode.new end
        to_run.run(temp_scope)
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

class SimpleLangParse < Rly::Yacc

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
            target: a.value, name: op.value, args: [ b.value ]
        )
    end

  #  rule 'bexp : bexp e_op term', &call_by_name
 #   rule 'term : term t_op exp', &call_by_name
 #   rule 'bexp : term ', &assign_rhs
    rule 'term : exp', &assign_rhs

    rule 'exp : funcall | value | assign ', &assign_rhs

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
        @inst ||= SimpleLangParse.new
    end

    def self.parse(str)
        inst.parse(str, false)
    end
    #store_grammar 'grammar.txt'

end
