#/usr/bin/env ruby

require "haml"
require "rdiscount"
require "psych"

# next step: make it a bit cleaner? tips: a coherent and readable data object,
# many helper functions that do stupid little things, export IO as much as
# possible.

# Page (minimal)
# @view_src
# @data_src
# @raw
# body(format)
# render(view)

class Page
   
   attr_accessor :view,:raw,:src
   
   def initialize data_src
      hash = (File.read src).match(/^---\n(.+)?---\n(.+)/m)
      if hash["meta"] then
         meta = Psych.load(hash["meta"])
         @view_src = meta["view"]
      end
      @data_src = data_src
      @raw = hash["raw"]
   end
   
   def body f=:raw
      format @raw,f
   end
   
   def view v=@view_src
      render body,v
   end
   
end

def transform tree,&block
   Hash[ tree.to_a.map do |b|
      case b[0]
         when :list then [ :list, b[1].map {|a| block.call(a) } ]
         when :dir  then b
         else
            if File.exists? tree[:dir]
               then [ b[0], (transform b[1] {|a| block.call(a) }) ]
            end
      end
   end ]
end

def render format=:raw,tree
   case format
      when :markdown then transform tree do |page|
         page.update({ :rendered_body => RDiscount.new(page[:body]).to_html })
      end
   end
end

def tree base=".",selection="*"
   puts Dir.glob(File.join base,selection).map { |f| "\t" + f }
   Hash[ Dir.glob(File.join base,"*").map do |file|
      if File.directory? file
         then [file.split("/")[-1], tree(file,selection) ]
      end 
   end + [[ :list,
            Dir.glob(File.join base,selection).sort { |a,b| a <=> b }.map do |file|
               { :meta => if (File.read file).split("---").length > 1
                    then Psych.load((File.read file).split("---")[1])
                    else false
                 end,
                 :file => file,
                 :body => (File.read file).split("---")[-1] }
            end ],
          [ :dir, base ]] ]
end

def build tree
   transform tree do |file|
      puts "\t" + "site/" + tree[:dir] + file[:file].split(".")[0] + ".html"
      File.write(
         "site/#{ file[:file].scan(/^data\/(.*[^\.])\.md$/).join }.html",
         (if file[:meta] && file[:meta]["view"]
            then Haml::Engine.new(
                  File.read "view/#{ file[:meta]["view"] }"
               ).render(Object.new, { :page => file, :data => tree })
            else file[:body]
         end)
      )
      file
   end
end

def main
   puts "[frankie] retrieving data..."
   data = tree "data","*.md"
   puts data.to_s
   puts "[frankie] rendering data..."
   data = render :markdown,data
   puts data.to_s
   puts "[frankie] starting build..."
   build data
   puts "[frankie] done."
end

main
