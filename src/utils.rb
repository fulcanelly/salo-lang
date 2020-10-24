class Scope
    attr_accessor :vars, :super
    
    def initialize(sscope = nil)
        @super = sscope
        @vars = {}
    end

    def find(name)
        @vars[name] or begin @super.find(name) if @super end
    end

    def get(name)
        find(name) or begin @vars[name] = Reference.new(nil) end
    end
end

class Reference 
    def initialize(val)
        @val = val
    end

    def show
        @val
    end

    def set(newval)
        @val = newval
    end
end

class Processor 
    
    attr_accessor :nodes, :scope

    def initialize(nodes, scope = nil)
        @nodes = nodes
        @scope = Scope.new scope
    end

    def run()
        res = nil
        nodes.each do res = _1.run(scope) end
        return res
    end
end


class Function

    attr_accessor :proc

    def args_check
    end
    def initialize(code, scope)
        @proc = Processor.new(args, code, scope)
    end

    def call
        @proc.run()
    end
end

class Runner 
    attr_accessor :globals, :file


    def self::start_path=(path)
        @start_path ||= path
    end

    def self::start_path
        @start_path
    end

    def initialize(file)
        @file = file
        @globals = Scope.new 
        Runner::start_path = File.dirname(file)
        builtin.each do |name, body|
            @globals.get(name).set(body)
        end
    end

    def run 
        code = SimpleLangParse.parse file.read
        file.close

        code.run(@globals)
        @globals
    end

    def import(runner)
    end

    def set(name, value)
    end

    def builtin 
        {
            add: -> *args {
                args.reduce(:+)
            },
            rand_bool: -> {
                if rand > 0.5 then true else false end
            },
            print: proc { 
                begin
                    _1.salo_pp 
                rescue NoMethodError => e
                    pp _1       
                end
            },
            stacktrace: proc { 
                pp FunCall::stacktrace
            }
        }
    end

end


class String 
    def salo_pp
        puts self
    end
end