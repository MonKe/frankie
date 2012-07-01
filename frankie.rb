#!/usr/bin/env ruby

require "psych"
require "haml"
require "rdiscount"

require File.dirname(File.absolute_path(__FILE__)) + "/frankie-log.rb"

class Frankie

   def self.read_conf dir=$conf_defaults["dirs"]["conf"],files=$conf_defaults["conf"]["files"]
      Log.info( "Reading conf...", :conf_load )
      if File::directory? dir
         then
            Hash[
               files.map do |file|
                  if File::exist? "#{ dir }/#{ file }.yml"
                     then
                        Log.url( "#{ dir }/#{ file }.yml", :conf_load )
                        [ file, Psych::load(File::read "#{ dir }/#{ file }.yml") ]
                     else
                        Log.error(
                           "Conf file '#{ dir }/#{ file }.yml' not found.",
                           :conf_load,
                           __LINE__
                        )
                  end
               end
            ]
         else
            Log.error(
               "Conf dir '#{ dir }' not found.",
               :conf_load,
               __LINE__
            )
      end
   end

   def self.read_data dir=$conf["dirs"]["data"],selection="*.*"
      docs, medias = [], []
      Hash[ Dir.glob(File.join dir,"*").map do |file|
         Log.url( file, :data_load )
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
      metadoc = MetaDoc::render target
      unless $render_stack[:waiting].empty?
         then
            unstacked = $render_stack[:waiting].pop
            $render_stack[:processing] << unstacked
            if Routes.queries.include? unstacked[:url] and !unstacked[:params].nil?
               then
                  next_target = build(
                     unstacked[:meta]["view"],
                     "view",
                     unstacked,
                     unstacked[:url]
                  ).update( :end_url => Routes.make_url( unstacked ))
               else
                  next_target = build(unstacked)
                  if next_target[:end_url].empty?
                     then next_target.update( :end_url => next_target[:url] )
                  end
            end
            self.write_stack(
               self.render(next_target),
               next_target[:end_url],
               next_target[:format]
            )
            $render_stack[:done] << unstacked
      end
      metadoc
   end
   
   def self.stack url
      unless $render_stack[:done].include? url
         then
            $render_stack[:waiting] << url
      end
   end
   
   def self.stacked? target
      stack = $render_stack[:waiting] + $render_stack[:processing] +
         $render_stack[:done]
      if target[:params]
         then stack.select { |p| p[:params] == target[:params] }.length > 0
         else stack.include? target
      end
   end
   
   def self.write_stack file,url,format
      unless $write_stack.key? url
         then
            write_url = MetaDoc::write_url(url,format) 
            dirs = if format == :bin
               then "#{ $conf["dirs"]["write"] }/#{ write_url }".split("/")[0..-2]
               else "#{ $conf["dirs"]["write"] }#{ write_url }".split("/")[0..-2]
            end
            (0..(dirs.length-1)).to_a.map do |i|
               dir = dirs[0..i].join("/")
               unless $write_stack.key? dir or dir == $conf["dirs"]["write"]
                  then
                     Log.url( dir, :write_stack )
                     $write_stack[dir] = { :make => :dir }
               end
            end
            if format == :bin
               then
                  Log.url( $conf["dirs"]["write"] + "/" + write_url, :write_stack )
                  $write_stack["#{ $conf["dirs"]["write"] }/#{ write_url }"] = {
                     :make => :bin, :with => url
                  }
               else
                  Log.url( $conf["dirs"]["write"] + write_url, :write_stack )
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
         Log.url( "- > " + url, :write)
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
         then
            Log.error(
               "File '#{ $conf["dirs"][dir] }/#{ url }' not found.",
               :build, __LINE__
            )
      end
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
      if !target[:target].empty? and self.last_target? target[:target]
         then
            if Routes.queries.include? target[:target][:url]
               then params = target[:target][:params]
               else params = {}
            end
      end
      case target[:format]
         when :markdown then RDiscount.new(target[:body]).to_html
         when :haml then
            Haml::Engine.new(target[:body]).render(
               Object.new,
               {
                  :target => (TplObject.new target[:target] if target[:target]),
                  :data   => $data,
                  :params => params
               }
            )
         else target[:body]
      end
   end
   
   def self.last_view?( target )
      !target[:target].empty? and (target[:meta].nil? or !target[:meta].key? "view")
   end
   
   def self.last_target( target )
      self.last_target? ? target : last_target( target[:target] )
   end
   
   def self.last_target?( target )
      target[:target].empty?
   end
   
end

class Routes
   
   def self.queries
      $conf["routes"]["match"].map { |m| m["query"] }
   end
   
   def self.make_url( target )
      r = self.select_result( target[:url] )
      self.get_params( target[:url] ).map do |param|
         if target[:params].key? param
            then
               r = self.insert_param( param, target[:params][param], r )
            else
               Log.error(
                  "Unknown parameter #{ param } for #{ target[:url] }",
                  :routes, __LINE__
               )
         end
      end
      r
   end
   
   def self.select_result( query )
      $conf["routes"]["match"].select { |m| m["query"] == query }[0]["result"]
   end
   
   def self.get_params( query )
      self.select_result( query ).scan( /:([a-zA-Z]+)/ ).flatten
   end
   
   def self.insert_param( key, value, result )
      r = result.split(":" + key)
      r[0] + r[1..-1].map { |x| value.to_s + x }.join
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
   
   def url params=nil
      hash = @hash
      if Routes.queries.include? hash[:url] and !params.nil?
      then
         hash = @hash.dup.update( :params => params )
         unless Frankie.stacked? hash
            then
               $render_stack[:waiting] << hash
         end
         "/" + Routes.make_url( hash )
      elsif $conf["routes"]["index"] == hash[:url]
         then "/"
         else
            unless Frankie.stacked?  hash[:url]
               then Frankie::stack hash[:url]
            end
            MetaDoc::write_url hash[:url],hash[:format]
      end
   end
   
end

$conf_defaults = Psych::load(
   File::read(
      File::dirname(File::absolute_path(__FILE__)).to_s + "/defaults.yml"
   )
)

# quiet mode before we start logging
$quiet_mode = true if ARGF.argv.include? "-q" or ARGF.argv.include? "--quiet"
# rejecting everything that's not 'args_ok'
ARGF.argv.map do |arg|
   args_ok = [ "-w", "--write", "-q", "--quiet" ]
   Log.error(
      "Wrong command-line argument #{ arg }", :arg_init, __LINE__
   ) unless args_ok.include? arg
   case arg
      when "-w", "--write" then
         Log.important( "Write mode: replacing existing files.", :arg_init )
         $write_mode = true
   end
end

$conf = $conf_defaults.update Frankie::read_conf
Log.info( "Reading data...", :data_load )
$data = Frankie::read_data
$render_stack = { :waiting => [], :processing => [], :done => [] }
$write_stack = {}

Log.info( "Building...", :build )
first_target = Frankie::build $conf["routes"]["index"]
$render_stack[:done] << first_target
Log.info( "Rendering...", :build )
Frankie::write_stack(
   Frankie::render(first_target),
   "index" + File.extname(first_target[:end_url]),
   first_target[:format]
)

if $write_mode
   then
      unless File::directory? $conf["dirs"]["write"]
         then
            Log.info( "Creating #{ $conf["dirs"]["write"] } dir...", :write )
            Dir::mkdir $conf["dirs"]["write"]
         else
            Log.info( "Cleaning #{ $conf["dirs"]["write"] }...", :write )
            Frankie::clean
      end
      Log.info( "Writing...", :write )
      Frankie::write
      Log.important( "Done!", :end )
   else
       Log.important(
         "Done in pretend mode. '-w' or '--write' to write the changes.",
         :end
      )
end
