#/usr/bin/env ruby

require "haml"
require "rdiscount"
require "psych"

# next step: make MetaDoc & View pour attribuer des meta aux vues. Les meta des
# vues se substituent à celles de la page.

# delete files properly before building.

# then: find urls in rendered bodies & layouts. use them to Tree::crawl based on
# an entry point, spreading with urls. Wait... to find all urls on a page we'd
# need to build it. Maybe trigger something at the end of Data::render.

# Page (minimal)
# @view_url
# @data_url
# @site_url
# @meta
# @raw
# @format
# body(format)
# render(view)

class MetaDoc
   
   attr_accessor :view_url,:self_url,:meta,:raw,:format
   
   def initialize self_url
      hash = (File.read self_url).match(/^(---\n(?<meta>.+)---\n)?(?<raw>.+)/m)
      if hash["meta"] then
         @meta = Psych.load(hash["meta"])
         @view_url = @meta["view"]
      end
      @site_url = ""
      @self_url = self_url
      @raw = hash["raw"]
      @format = case @self_url.split(".")[-1]
         when "md","markdown" then :markdown
         when "haml" then :haml
         else :raw
      end
   end
   
   # the body, with formatting options
   def body f=@format
      Data::format @raw,f
   end
   
   # the rendering with possibility of changing the view
   def view v=@view_url,data={}
      Data::render v,{ :page => self, :data => data }
   end
   
end

class Page
   
   attr_accessor :view_url,:data_url,:site_url,:meta,:raw,:format
   
   def initialize data_url
      hash = (File.read data_url).match(/^(---\n(?<meta>.+)---\n)?(?<raw>.+)/m)
      if hash["meta"] then
         @meta = Psych.load(hash["meta"])
         @view_url = @meta["view"]
      end
      @site_url = ""
      @data_url = data_url
      @raw = hash["raw"]
      case @data_url.split(".")[-1]
         when "md" then @format = :markdown
         else @format = :raw
      end
   end
   
   # the body, with formatting options
   def body f=@format
      Data::format @raw,f
   end
   
   # the rendering with possibility of changing the view
   def view v=@view_url,data={}
      Data::render v,{ :page => self, :data => data }
   end
   
end

class Data
   
   # the way a page body is formatted
   def self.format raw,f=:raw,options={}
      case f
         when :markdown then RDiscount.new(raw).to_html
         when :haml then
            Haml::Engine.new(raw).render(Object.new, options)
         else raw
      end
   end
   
   # the way a layout is applied to a page
   def self.render view,locals={}
      Haml::Engine.new(File.read "view/#{ view }").render(Object.new, locals)
   end
   
end

class Tree
   
   # crawls dirs to extract files based on a selector, and render them in a
   # hash.
   def self.crawl base="data",selection="*.*"
      Hash[ Dir.glob(File.join base,"*").map do |file|
         if File.directory? file
            then [file.split("/")[-1], (Tree::crawl file,selection) ]
         end
      end + [[
         :list,
         Dir.glob(File.join base,selection).sort { |a,b| a <=> b }.map do |file|
            Page.new file
         end ],
         [ :dir, base ]] ]
   end
   
   # unused, update every page with &block
   def self.update tree,&block
      Hash[ tree.to_a.map do |b|
         case b[0]
            when :list then [ :list, b[1].map {|a| block.call(a) } ]
            when :dir  then b
            else
               if File.exists? tree[:dir]
                  then [ b[0], (self.transform b[1] {|a| block.call(a) }) ]
               end
         end
      end ]
   end
   
   # output function, returns an array no one cares about
   def self.build tree,data={}
      data = if data.empty? then tree else data end
      unless File.exists? "site#{ tree[:dir].scan(/^data(.*)/).join }"
         puts "Building 'site#{ tree[:dir].scan(/^data(.*)/).join }'..."
         Dir::mkdir "site#{ tree[:dir].scan(/^data(.*)/).join }"
         puts "done."
      end
      tree.to_a.map do |b|
         case b[0]
            when :list then [ :list, b[1].map do |page|
               page.site_url = "#{ page.data_url.scan(/^data\/(.*[^\.])\.md$/).join }.html"
               puts "Building 'site/#{ page.site_url }'..."
               File.write(
                  "site/#{ page.site_url }",
                  (if page.view_url then page.view page.view_url,data else page.body end) )
               puts "done."
               end ]
            when :dir then b
            else [ b[0], (self.build b[1],data) ]      
         end
      end
   end
   
end

def main
   Tree::build Tree::crawl
end

main
