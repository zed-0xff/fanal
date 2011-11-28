#!/usr/bin/env ruby
require 'sinatra'
require 'digest/md5'
require 'yaml'
require 'json'
require 'net/http'
require 'mime/types'
require 'zipruby'

Dir['./lib/*.rb'].each{ |x| require x }

DATA_DIR = "data"
RED_ROWS = %w'data_past_eof'
BUFSIZE  = 16384

###############################################

helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    include ActionView::Helpers::NumberHelper
    include LinksHelper
    include HexdumpHelper
    include UnzipHelper

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
      hv = case v
        when Fixnum
          "%d (0x%x)" % [v,v]
        when Hash
          if k == :data_past_eof
            "<pre>%d (0x%x) bytes:\n\n%s</pre>" % [v[:size], v[:size], h(v[:dump])]
          else
            h(v.inspect)
          end
        when Array
          if k == :histogram
            Histogram.new(v).to_html
          elsif k == :foremost
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

      case k.to_s
      when 'filename'
        r << '<td class="tools">'
        r << %Q|<a href="/#{params[:hash]}/dl" title="Download" class="dl"></a>|
        r << '</td>'
      when 'data_past_eof'
        r << '<td class="tools">'
        r << %Q|<a href="/#{params[:hash]}/dl_part?start=#{v[:start].to_i}&size=#{v[:size].to_i}" title="Download" class="dl"></a>|
        r << %Q|<a href="/#{params[:hash]}/analyze_part?start=#{v[:start].to_i}&size=#{v[:size].to_i}" title="Analyze" class="analyze"></a>|
        r << %Q|<a onclick="show_in_hexdump(#{v[:start].to_i},#{v[:size].to_i})" title="show in hexdump" class="hex"></a>|
        r << '</td>'
      when 'parent'
        raise unless hv =~ /\A[0-9a-f]{32}\Z/
        m = YAML::load_file(File.join("data",hv,"metadata.yml"))
        r.sub! hv, %Q|<a href="/#{hv}">#{m[:filename] || @metadata[:filename].split(':',2).first}</a>|
      end

      r << "</tr>"
    end
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
  tempfile =
    if @tempfile.respond_to?(:read) && @tempfile.respond_to?(:size)
      @tempfile
    else
      @params[:file] && @params[:file][:tempfile]
    end

  if !tempfile && params[:url]
    url = params[:url].to_s.strip
    halt 400, "Error: no file" if url.empty?
    tempfile = Tempfile.new('anal')

    @part_fname = File.basename(url)

    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new uri.request_uri

      http.request request do |response|
        response.read_body do |chunk|
          tempfile.write chunk
        end
      end
    end
    tempfile.rewind
  end

  begin
    md5 = @part_hash ||
      begin
        dig = Digest::MD5.new
        buf = ""
        sz = @part_size || tempfile.size
        while sz > 0
          dig.update(tempfile.read([sz,BUFSIZE].min))
          sz -= BUFSIZE
        end
        dig.hexdigest
      end

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
      File.copy_stream tempfile, fname, @part_size, @part_start
    elsif tempfile.respond_to?(:path)
      # http uploaded file
      FileUtils.cp tempfile.path, fname
    else
      # unzipping
      # can't use File.copy_stream here b/c Zip::File do not have File.read(size, block)
      File.open(fname,"wb") do |fo|
        while chunk = tempfile.read(BUFSIZE)
          fo.write(chunk)
        end
      end
    end

    File.open(File.join(dname,"metadata.yml"),"w") do |f|
      f << {
        :filename => @part_fname || @params[:file][:filename],
        :size     => @part_size  || tempfile.size,
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
  redirect "/#{params[:hash]}/"
end

get '/:hash/' do
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
    last = @foremost.sort_by{ |x| x[2] }.last
    if last[2] + last[1] < File.size(@fname)
      @foremost << [
        "BIN",
        File.size(@fname) - last[1] - last[2],
        last[1] + last[2],
        "data past eof"
      ]
    end
    @image_types = %w'JPG GIF PNG BMP ICO PCX TIF TIFF'
    haml :foremost, :layout => false
  else
    "Nothing found"
  end
end

get '/:hash/hexdump' do
  check_hash

  @offset = params[:offset].to_i; @offset = 0 if @offset < 0
  @size   = params[:size].to_i; @size = 0x20000 if @size <= 0

  File.open(@fname) do |f|
    f.seek @offset
    @data = f.read(@size)
  end

  @fsize = File.size(@fname)
  if params[:raw]
    headers 'Content-Type' => 'text/plain; charset=x-user-defined'
    halt @data
  end
  hparams = {}
  %w'width'.each do |p|
    hparams[p.to_sym] = params[p].to_i if params[p]
  end
  @dump  = hexdump(@data, hparams) + (@data.size+@offset < @fsize ? "\n..." : "")
  haml :hexdump, :layout => false
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
    "Content-Disposition" => (params[:inline] ? "inline" : "attachment") + %Q|; filename="#@part_fname"|,
    "Content-Length"      => @part_size.to_s,
    "Content-Type"        => (MIME::Types.of(@part_fname).first || "application/octet-stream").to_s

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

  @tempfile = File.open(@fname,"rb")
  @tempfile.seek @part_start

  # call POST on '/'
  call! env.merge("PATH_INFO" => "/", "REQUEST_METHOD" => "POST")
end

get '/:hash/unzip' do
  check_hash
  @files  = []
  @fields = %w'name size comp_method comp_size crc index mtime encryption_method comment'
  FStruct = Struct.new(*@fields.map(&:to_sym))
  begin
    Zip::Archive.open(@fname) do |ar|
      ar.each do |f|
        @files << (fs=FStruct.new(f.name, f.size))
        @fields.each do |field|
          fs.send "#{field}=", f.send(field)
        end
      end
    end
  rescue Zip::Error
    r = "<div style='color:red'>Zip::Archive Error: " + h($!.to_s) + "</div>"
    r << "<pre>"
    r << `unzip -lv #@fname 2>&1`
    r << "</pre>"
    halt r
  end
  haml :unzip, :layout => !request.xhr?
end

get '/:hash/unzip/:id/analyze' do
  check_hash
  Zip::Archive.open(@fname) do |ar|
    ar.fopen(params[:id].to_i) do |f|
      dig = Digest::MD5.new
      f.read{ |chunk| dig.update(chunk) }
      @part_hash = dig.hexdigest
    end
    f = ar.fopen(params[:id].to_i)
    @tempfile = f
    @part_fname = f.name
    # call POST on '/'
    call! env.merge("PATH_INFO" => "/", "REQUEST_METHOD" => "POST")
    f.close rescue nil
  end
  halt "OK"
end
