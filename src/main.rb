def check_time(what = "unknown", &block) 
	start_time = Time.now 
	yield 
    time = Time.now - start_time
    puts 'took time for ' + what + ": " + time.to_s.red

end


require 'colorize'

puts "loading...".light_cyan

check_time("loading libs") {
	require_relative './parser'
	require_relative './utils'
	require_relative './vm'
}


# todo 
# * operators                     + (precedence still doesnt work)
# * strings                       + ~(weak)
# * modules
# * lambdas                 
# * default values in functions
# * comments                      + (but only one line)
# * arrays
# * syntax highlighter
# * fix newlines
# * booleans
# * salo_pp() 

open(ARGV.first, 'r') do |file| 
	parsed, analyst, builder = nil

	check_time "pasrsing" do
		parsed = SaloParser.parse(file.read) 
	end
	
	check_time "ast checks and optimizations" do
		analyst = SyntaxTreeAnalyst.new()
		parsed.accept(analyst)
	end

	check_time "compiling" do
		builder = BytecodeBuilder.new()
		builder.compile(parsed)
	end

	check_time "running" do 
		vm = SaloPlatform::VM.inst
		vm.push(builder.stack.last)
		vm.run
		#pp vm.stack
	end

end