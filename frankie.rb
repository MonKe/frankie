#!/usr/bin/env ruby

require "psych"
require "haml"
require "rdiscount"

# next step: séparation dans les datas des :list en :text et :bin avec une class
# Media qui n'a qu'url comme propriété.

# aussi: checker les layouts récursifs.

class Frankie

   def self.read_conf dir="conf",files=["app"]
      if File::directory? dir
         then
            Hash[
               files.map do |file|
                  if File::exist? "#{ dir }/#{ file }.yml"
                     then
                        puts "Reading conf from '#{ dir }/#{ file }.yml' ..."
                        [ :app, Psych::load(File::read "#{ dir }/#{ file }.yml") ]
                     else raise "Conf file '#{ dir }/#{ file }.yml' not found."
                  end
               end
            ]
         else raise "Conf dir '#{ dir }' not found."
      end
   end

   def self.read_data dir=$conf[:data_dir],selection="*.*"
      puts "Reading data from '#{ dir }' ..."
      Hash[ Dir.glob(File.join dir,"*").map do |file|
         if File.directory? file
            then [file.split("/")[-1], (self.read_data file,selection) ]
         end
      end + [[
         :list,
         Dir.glob(File.join dir,selection).sort { |a,b| a <=> b }.map do |file|
            TplObject.new(self.build file.scan(/^data\/(.*)/).join)
         end ],
         [ :dir, dir ]] ]
   end

   def self.build url,dir=:data_dir,target={},end_url=""
      puts "\t'#{ $conf[dir] }/#{ url }'"
      metadoc = MetaDoc::build(url,dir).update(
         :target  =>  target,
         :end_url => end_url
      )
      if metadoc[:meta] && metadoc[:meta]["view"]
         then self.build metadoc[:meta]["view"],:view_dir,metadoc,(
            if end_url.empty? then metadoc[:url] else end_url end
         )
         else metadoc
      end
   end

   def self.render target
      puts "Rendering '#{ target[:url] }'"
      metadoc = MetaDoc::render target
      unless $render_stack.empty?
         then
            next_target = build($render_stack.pop)
            if next_target[:end_url].empty?
               then next_target.update( :end_url => next_target[:url] )
            end
            self.write(
               self.render(next_target),
               next_target[:end_url],
               next_target[:format]
            )
      end
      metadoc
   end
   
   def self.stack url
      $render_stack << url
   end
   
   def self.clean dir=$conf[:write_dir]
      Dir.glob(File.join dir,"*").map do |file|
         if File.directory? file
            then
               self.clean file
               Dir::delete file
            else File::delete file
         end
      end
   end
   
   def self.write file,url,format
      write_url = MetaDoc::write_url(url,format)
      dir = "#{ $conf[:write_dir] }/#{ write_url }".split("/")[0..-2].join "/"
      puts "Writing '#{ $conf[:write_dir] }/#{ write_url }'"
      Dir.mkdir dir unless File.directory? dir
      File.write("#{ $conf[:write_dir] }/#{ write_url }",file)
   end

end

class MetaDoc
   
   def self.build url,dir
      match = File.read("#{ $conf[dir] }/#{ url }")
         .match /^(---\n(?<meta>.+)---\n)?(?<body>.+)/m
      {
         :meta => (Psych::load(match["meta"]) if match["meta"]),
         :body => (match["body"] if match["body"]),
         :url  => url,
         :format => MetaDoc::format(url)
      }
   end
   
   def self.format url
      case url.split("/")[-1].split(".")[1..-1].join "."
         when "md","markdown" then :markdown
         when "haml" then :haml
         else :raw
      end
   end
   
   def self.write_url url,format
      case format
         when :markdown,:haml then "#{ url.split(".")[0] }.html"
         else url
      end
   end
   
   def self.render target
      case target[:format]
         when :markdown then RDiscount.new(target[:body]).to_html
         when :haml then
            Haml::Engine.new(target[:body]).render(
               Object.new,
               {
                  :target => (TplObject.new target[:target] if target[:target]),
                  :data   => $data
               }
            )
         else target[:body]
      end
   end
   
end

class TplObject
   
   attr_accessor :meta,:format
   
   def initialize target
      @hash   = target
      @meta   = target[:meta]
      @format = target[:format]
   end
   
   def body format=@format
      MetaDoc::render @hash.update( :format => format )
   end
   
   def view v=""
      unless v.empty?
         then Frankie::render(Frankie::build v,:view_dir,@hash,@hash[:url])
         else Frankie::render @hash
      end
   end
   
   def url
      Frankie::stack @hash[:url]
      MetaDoc::write_url @hash[:url],@format
   end
   
end

conf_defaults = {
   :data_dir  => "data",
   :view_dir  => "view",
   :write_dir => "site"
}

$conf = conf_defaults.update Frankie::read_conf
$data = Frankie::read_data
$render_stack = []

puts "Cleaning '#{ $conf[:write_dir] }'..."
Frankie::clean
puts "Building from url call..."
first_target = Frankie::build $conf[:app]["target_url"]
Frankie::write(Frankie::render(first_target),"index.html",first_target[:format])
puts "Done!"
