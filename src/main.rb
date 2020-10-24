def check_time(&block) 
	start_time = Time.now 
	yield 
    Time.now - start_time
end


require 'colorize'

puts "loading...".light_cyan

time = check_time {
	require_relative './parser'
	require_relative './utils'
}
puts 'took ' + time.to_s.red


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
    Runner.new(file).run
end