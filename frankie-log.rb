class Log
   
   def self.url( string, step )
      puts label( step ) + "\e[34m |- #{ string }\e[0m" unless $quiet_mode
   end
   
   def self.important( string, step )
      puts label( step ) + "\e[33m#{ string }\e[0m"
   end
   
   def self.info( string, step )
      puts label( step ) + string unless $quiet_mode
   end
   
   def self.error( string, step, line, file="frankie.rb" )
      $stderr.puts label( step ) + "\e[31m#{ string }\e[0m" +
      "\t[#{ File.basename file }][#{ line }]"
      Process.exit
   end
   
   private
   
   def self.block( string, size, pattern=" " )
      if string.length > size
         then "bla"
      elsif string.length < size
         then
            string + pattern * ( size - string.length )
         else string
      end
   end
   
   def self.label( step )
      "\e[34m" + block( step.to_s, 15 ) + "\e[0m"
   end
end
