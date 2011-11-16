#!/usr/bin/env ruby
require 'sinatra'
require 'digest/md5'
require 'yaml'
#require 'active_support/core_ext'
#require 'action_view/helpers/number_helper'
Dir['./lib/*.rb'].each{ |x| require x }

DATA_DIR = "data"
RED_ROWS = %w'data_past_eof'

###############################################

helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    include ActionView::Helpers::NumberHelper
    include LinksHelper

    def meta_rows
      keys = @metadata.keys
      if @metadata[:parent]
        keys.delete :parent
        meta_row :parent
      else
        ''
      end +
      keys.map do |k|
        meta_row k
      end.join
    end

    def meta_row k,v=nil
      v ||= @metadata[k]
      need_pre = true
      hv = case v
        when Fixnum
          "%d (0x%x)" % [v,v]
        when Hash
          if k == :data_past_eof
            "%d (0x%x) bytes:\n\n%s" % [v[:size], v[:size], h(v[:dump])]
          else
            h(v.inspect)
          end
        when Array
          if k == :histogram
            need_pre = false
            Histogram.new(v).to_html
          elsif k == :foremost
            need_pre = false
            t = '<table class=metadata>'
            t << v.sort_by{|x| x[2]}.map do |row|
              '<tr><td>' + row.join('</td><td>') + '</td></tr>'
            end.join
            t << '</table>'
          else
            h(v.inspect)
          end
        else
          h(v.to_s)
        end

      style = RED_ROWS.include?(k.to_s)? ' class="red"' : ''
      r = "<tr><th#{style}>#{h(k)}</th><td#{style}>#{hv}</td>"
      #r << (need_pre ? "<pre>#{hv}</pre></td>" : "#{hv}</td>")

      case k.to_s
      when 'filename'
        r << '<td class="tools">'
        r << %Q|<a href="/#{params[:hash]}/dl" title="Download" class="dl"></a>|
        r << '</td>'
      when 'data_past_eof'
        r << '<td class="tools">'
        r << %Q|<a href="/#{params[:hash]}/dl_part?start=#{v[:start].to_i}&size=#{v[:size].to_i}" title="Download" class="dl"></a>|
        r << %Q|<a href="/#{params[:hash]}/analyze_part?start=#{v[:start].to_i}&size=#{v[:size].to_i}" title="Analyze" class="analyze"></a>|
        r << '</td>'
      when 'parent'
        r.sub! hv, %Q|<a href="/#{hv}">#{@metadata[:filename].split(':',2).first}</a>|
      end

      r << "</tr>"
    end
end

def hexdump data, h = {}
  offset = h[:offset] || 0
  add    = h[:add]    || 0
  size   = h[:size]   || (data.size-offset)
  tail   = h[:tail]   || "\n"

  s = "%08x: " % (offset + add)
  ascii = ''
  size.times do |i|
    s << " " if i%8==0
    if i%16==0 && i>0
      s << "|%s|\n%08x:  " % [ascii, offset + add + i]
      ascii = ''
    end
    c = data[offset+i].ord
    s << "%02x " % c
    ascii << ((32..126).include?(c) ? c.chr : '.')
  end
  s << '   '*(0x10-size%0x10)
  "%s |%-16s|%s" % [s, ascii, tail]
end

###############################################

get '/' do
  @recent = Dir[File.join(DATA_DIR,'?'*32,'metadata.yml')].
    sort_by{ |x| File.ctime(File.dirname(x)) }.
    reverse.
    map{ |x| YAML::load_file(x) }
  haml :index
end

get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end

post '/' do
  tempfile = @tempfile.is_a?(File) ? @tempfile : @params[:file][:tempfile]
  return 'no file' unless tempfile

  begin
    dig = Digest::MD5.new
    buf = ""
    sz = @part_size || tempfile.size
    while sz > 0
      dig.update(tempfile.read([sz,16384].min))
      sz -= 16384
    end
    md5 = dig.hexdigest

    dname = File.join(DATA_DIR,md5)
    fname = File.join(dname,"data")
    if File.exist?(dname) && File.directory?(dname) && File.exist?(fname)
      redirect md5
      return
    elsif File.exist?(dname)
      FileUtils.rm_rf dname
    end

    Dir.mkdir dname

    if @part_start && @part_size
      # analyzing a part of other file
      sz = @part_size
      tempfile.seek @part_start
      File.open(fname,"wb") do |f|
        while sz > 0
          f.write(tempfile.read([sz,16384].min))
          sz -= 16384
        end
      end
    else
      FileUtils.cp tempfile.path, fname
    end

    File.open(File.join(dname,"metadata.yml"),"w") do |f|
      f << {
        :filename => @part_fname || @params[:file][:filename],
        :size     => @part_size  || File.size(tempfile.path),
        :md5      => md5
      }.merge(@hash ? {:parent => @hash} : {}).to_yaml
    end

    redirect "/#{md5}/analyze"
  ensure
    tempfile.close
    tempfile.unlink if tempfile.is_a?(Tempfile)
  end
end

def check_hash
  @hash = params[:hash]
  halt 400, "Error: invalid hash" unless @hash =~ /\A[0-9a-f]{32}\Z/
  @dname = File.join(DATA_DIR, @hash)
  halt 404, "Error: Not Found" unless Dir.exist?(@dname)
  @fname = File.join(@dname,"data")
end

get '/:hash' do
  check_hash

  @metadata = YAML::load_file(File.join(@dname,"metadata.yml")) || {}
  @title = @metadata[:filename]
  haml :file
end

get '/:hash/analyze' do
  check_hash

  anal = Analyzer.new(@fname)
  @metadata = YAML::load_file(File.join(@dname,"metadata.yml")) || {}
  @metadata[:type] = anal.type
  @metadata[:mimetype] = anal.mimetype
  @metadata[:histogram] = anal.histogram
  if d = anal.data_past_eof
#    @metadata[:data_past_eof] = "#{d.size} (0x#{d.size.to_s(16)}) bytes:\n\n" +
#      hexdump(d, :add => anal.size_with_eof_marker, :size => 0x40, :tail => (d.size>0x40 ? "\n...\n" : ''))
    @metadata[:data_past_eof] = {
      :size  => d.size,
      :start => anal.size_with_eof_marker,
      :dump  => hexdump(d, :add => anal.size_with_eof_marker, :size => 0x40, :tail => (d.size>0x40 ? "\n...\n" : ''))
    }
  end

  File.open(File.join(@dname,"metadata.yml"),"w"){ |f| f<<@metadata.to_yaml }

  redirect @hash
end

get '/:hash/dl' do
  check_hash
  @metadata = YAML::load_file(File.join(@dname,"metadata.yml")) || {}
  send_file @fname, :filename => @metadata[:filename]
end

get '/:hash/strings' do
  check_hash
  if params[:sort].to_i > 0
    "<pre>" + h(`strings #@fname | sed 's/^[ \t]*//;s/[ \t]*$//' | sort -u`) + "</pre>"
  else
    "<pre>" + h(`strings #@fname`) + "</pre>"
  end
end

get '/:hash/foremost' do
  check_hash

  if (@foremost = Foremost.scan(@fname, :cache_file => File.join(@dname,"foremost.yml"))).any?
    haml :foremost, :layout => false
  else
    "Nothing found"
  end
end

get '/:hash/hexdump' do
  check_hash
  data = File.read(@fname,100_000)
  "<pre>" + h(hexdump(data)) + (data.size==100_000 ? "\n..." : "") + "</pre>"
end

def check_part
  halt 400, "Error: no start" unless params[:start]
  check_hash
  filesize   = File.size(@fname)
  part_start = params[:start].to_i
  max_part_size  = filesize-part_start
  part_size = (params[:size] || max_part_size).to_i
  part_size = max_part_size if part_size > max_part_size || part_size < 0
  halt 400, "Error: start must be within 0..#{filesize}" unless (0..filesize).include?(part_start)
  @part_size,@part_start = part_size,part_start

  @metadata = YAML::load_file(File.join(@dname,"metadata.yml")) || {}
  @part_fname = "#{@metadata[:filename]}:#@part_start:#@part_size"
  @part_fname << '.' << params[:ext] if params[:ext].to_s =~ /\A[a-z0-9]{1,4}\Z/
end

get '/:hash/dl_part' do
  check_part
  headers \
    "Content-Disposition" => %Q|attachment; filename="#@part_fname"|,
    "Content-Length"      => @part_size.to_s

  stream do |out|
    File.open(@fname,"rb") do |f|
      f.seek @part_start
      while @part_size > 0
        out << f.read(@part_size > 4096 ? 4096 : @part_size)
        @part_size -= 4096
      end
    end
  end
end

get '/:hash/analyze_part' do
  check_part

  dig = Digest::MD5.new

  @tempfile = File.open(@fname,"rb")
  @tempfile.seek @part_start

  # call POST on '/'
  call! env.merge("PATH_INFO" => "/", "REQUEST_METHOD" => "POST")
end
