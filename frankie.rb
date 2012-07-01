#!/usr/bin/env ruby

require "psych"
require "haml"
require "rdiscount"

# maybe: tenter liquid (dans une autre branche). <-- impossible à cause de
# l'appel à Frankie::stack dans les templates

# next step: real routing? hahahaha. le refactoring passera avant, puisque
# j'aurai besoin des différentes parties de l'url de base de façon propre,
# ainsi que du format, etc.

# puis: étendre les extensions de fichiers (type: .rdf.yaml) pour affiner la
# reconnaissance de formats de fichiers et de write_url.

class Frankie

   def self.read_conf dir=$conf_defaults["dirs"]["conf"],files=$conf_defaults["conf"]["files"]
      if File::directory? dir
         then
            Hash[
               files.map do |file|
                  if File::exist? "#{ dir }/#{ file }.yml"
                     then
                        puts "Reading conf from '#{ dir }/#{ file }.yml' ..."
                        [ file, Psych::load(File::read "#{ dir }/#{ file }.yml") ]
                     else raise "Conf file '#{ dir }/#{ file }.yml' not found."
                  end
               end
            ]
         else raise "Conf dir '#{ dir }' not found."
      end
   end

   def self.read_data dir=$conf["dirs"]["data"],selection="*.*"
      puts "Reading data from '#{ dir }' ..."
      docs, medias = [], []
      Hash[ Dir.glob(File.join dir,"*").map do |file|
         if File.directory? file
            then [file.split("/")[-1], (self.read_data file,selection) ]
            else
               if MetaDoc.valid? file
                  then
                     metadoc = MetaDoc::build(
                        file.scan(/^data\/(.*)/).join("/"),"data"
                     ).update( :target  => {}, :end_url => "" )
                     docs << TplObject.new( metadoc )
                     [ File.basename( file ), TplObject.new( metadoc ) ]
                  else
                     puts '\t' + file
                     medias << TplBin.new( file )
                     [ File.basename( file ), TplBin.new( file )]
               end
         end
      end +
      [[:docs, docs], [:medias, medias], [:all, docs + medias ], [ :dir, dir ]]]
   end

   def self.build url,dir="data",target={},end_url=""
      metadoc = MetaDoc::build(url,dir).update(
         :target  =>  target,
         :end_url => end_url
      )
      if metadoc[:meta] && metadoc[:meta]["view"]
         then
            self.build metadoc[:meta]["view"],"view",metadoc,(
            if end_url.empty? then metadoc[:url] else end_url end
         )
         else metadoc
      end
   end

   def self.render target
      puts "Rendering '#{ target[:url] }'"
      metadoc = MetaDoc::render target
      unless $render_stack[:waiting].empty?
         then
            unstacked = $render_stack[:waiting].pop
            $render_stack[:processing] << unstacked
            next_target = build(unstacked)
            if next_target[:end_url].empty?
               then next_target.update( :end_url => next_target[:url] )
            end
            self.write_stack(
               self.render(next_target),
               next_target[:end_url],
               next_target[:format]
            )
            $render_stack[:processing] = $render_stack[:processing].delete unstacked
            $render_stack[:done] << unstacked
      end
      metadoc
   end
   
   def self.stack url
      $render_stack[:waiting] << url unless $render_stack[:done].include? url
   end
   
   def self.stacked? url
      (
         $render_stack[:waiting] + $render_stack[:processing] + $render_stack[:done]
      ).include? url
   end
   
   def self.write_stack file,url,format
      unless $write_stack.key? url
         then
            write_url = MetaDoc::write_url(url,format) 
            dir = if format == :bin
               then "#{ $conf["dirs"]["write"] }/#{ write_url }".split("/")[0..-2].join "/"
               else "#{ $conf["dirs"]["write"] }#{ write_url }".split("/")[0..-2].join "/"
            end
            unless $write_stack.key? dir or dir == $conf["dirs"]["write"]
               then
                  puts "Adding '#{ dir }' to writing stack..."
                  $write_stack[dir] = { :make => :dir }
            end
            if format == :bin
               then
                  puts "Adding '#{ $conf["dirs"]["write"] }/#{ write_url }' to writing stack..."
                  $write_stack["#{ $conf["dirs"]["write"] }/#{ write_url }"] = {
                     :make => :bin, :with => url
                  }
               else
                  puts "Adding '#{ $conf["dirs"]["write"] }#{ write_url }' to writing stack..."
                  $write_stack["#{ $conf["dirs"]["write"] }#{ write_url }"] = {
                     :make => :text, :with => file
                  }
            end
      end
   end
   
   def self.clean dir=$conf["dirs"]["write"]
      Dir.glob(File.join dir,"*").map do |file|
         if File.directory? file
            then
               self.clean file
               Dir::delete file
            else File::delete file
         end
      end
   end
   
   def self.write
      $write_stack.each do |url,file|
         case file[:make]
            when :dir  then Dir::mkdir url
            when :text then File::write url,file[:with]
            when :bin  then File::write url,File::read(file[:with])
         end
      end
   end

end

class MetaDoc
   
   def self.valid? url
      (`file -bi "#{ url }"` =~ /charset=binary/) == nil
   end
   
   def self.build url,dir
      unless File::exist? "#{ $conf["dirs"][dir] }/#{ url }"
         then raise "File '#{ $conf["dirs"][dir] }/#{ url }' not found."
      end
      puts "\t'#{ $conf["dirs"][dir] }/#{ url }'"
      match = File.read("#{ $conf["dirs"][dir] }/#{ url }")
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
      case self.format url
         when :markdown,:haml then "/#{ url.split(".")[0] }.html"
         else if format == :bin
            then url.scan(/^data\/(.*)/).join
            else "/#{ url }"
         end
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

class TplBin
   
   attr_accessor :src_url
   
   def initialize url
      @data    = url
      @src_url = MetaDoc::write_url(@data,:bin)
   end
   
   def to_s
      self.url
   end
   
   def url
      Frankie::write_stack(File::read(@data),@data,:bin)
      "/" + @src_url
   end
   
end

class TplObject
   
   attr_accessor :src_url,:meta,:format
   
   def initialize target
      @src_url = target[:url]
      @hash    = target
      @meta    = target[:meta]
      @format  = target[:format]
   end
   
   def to_s
      body
   end
   
   def body format=@format
      MetaDoc::render @hash.update( :format => format )
   end
   
   def view v=""
      unless v.empty?
         then
            hash = @hash.update @meta.update( "view" => v ) 
            Frankie::render(Frankie::build v,"view",hash,hash[:url])
         else Frankie::render @hash
      end
   end
   
   def url
      if $conf["routes"]["index"] == @hash[:url]
         then "/"
         else
            unless Frankie::stacked?  @hash[:url]
               then
                  Frankie::stack @hash[:url]
            end
            MetaDoc::write_url @hash[:url],@format
      end
   end
   
end

$conf_defaults = Psych::load(
   File::read(
      File::dirname(File::absolute_path(__FILE__)).to_s + "/defaults.yml"
   )
)

if ARGF.argv[0] == "-w" or ARGF.argv[0] == "--write"
   then
      $write_mode = :write
elsif ARGF.argv.length > 0
   then raise "Error in command-line arguments : '#{ ARGF.argv.join(", ") }' not found."
   else $write_mode = :pretend
end

$conf = $conf_defaults.update Frankie::read_conf
$data = Frankie::read_data
$render_stack = { :waiting => [], :processing => [], :done => [] }
$write_stack = {}

puts "Building from index route..."
first_target = Frankie::build $conf["routes"]["index"]
$render_stack[:done] << first_target
Frankie::write_stack(
   Frankie::render(first_target),
   "index" + File.extname(first_target[:end_url]),
   first_target[:format]
)

case $write_mode
   when :write then
      Dir::mkdir $conf["dirs"]["write"] unless File::directory? $conf["dirs"]["write"]
      puts "Cleaning '#{ $conf["dirs"]["write"] }'..."
      Frankie::clean
      puts "Writing to '#{ $conf["dirs"]["write"] }'..."
      Frankie::write
      puts "Done!"
   when :pretend then
       puts "Done in pretend mode. '-w' or '--write' to write the changes."
end
