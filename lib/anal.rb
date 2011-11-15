#!/usr/bin/env ruby
require 'digest/md5'
require 'digest/sha1'

class Analyzer

  EOF_MARKERS = {
    'JPEG' => "\xff\xd9",
    'PNG'  => "IEND\xae\x42\x60\x82"
  }

  attr_accessor :options, :fname, :size_with_eof_marker

  def initialize fname, opts={}
    @options = opts
    @fname = fname
  end

  def size; File.size(fname); end
  def type; @type ||= `file -b '#@fname'`.strip; end # XXX shell injection possible
  def mimetype; @mimetype ||= `file -b --mime-type '#@fname'`.strip; end # XXX shell injection possible
  def md5;  Digest::MD5.file(fname).hexdigest; end

  def histogram
    a = Array.new(256,0)
    File.open(fname) do |f|
      f.each_byte{ |b| a[b]+=1 }
    end
    a
  end

  def data_past_eof
    if eof_marker = EOF_MARKERS[type.to_s.split(' ').first.upcase]
      data = File.binread(fname)
      if idx = data.index(eof_marker)
        idx += eof_marker.size
        @size_with_eof_marker = idx
        if idx < size
          #printf "[!] %d bytes past EOF marker:\n", size-idx
          #hexdump data, :offset => idx, :size => 16, :tail => "\n\t...\n"
          return data[idx..-1]
        end
      else
        #puts "[?] no EOF marker"
        nil
      end
    end
    nil
  end
end

if __FILE__ == $0
  require 'optparse'

  options = {}
  opa = OptionParser.new do |opts|
    opts.banner = "Usage: #{__FILE__} [options]"

    opts.on("-v", "--verbose", "Run verbosely") do |v|
      options[:verbose] = v
    end
    opts.on("-H", "--html", "HTML output") do |v|
      options[:html] = v
    end
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end
  opa.parse!

  if ARGV.empty?
    puts opa.help
    exit
  end

  TITLE_LEN = 14
  def show title, value, o={}
    svalue =
      case value
      when String
        value
      when Fixnum
        "%d (0x%x)" % [value, value]
      else
        value.inspect
      end
    printf "[%s] %-*s: %s%s\n", o[:mark]||'.', TITLE_LEN, title, svalue, o[:tail]
  end

  def hexdump data, h = {}
    offset = h[:offset] || 0
    add    = h[:add]    || 0
    size   = h[:size]   || (data.size-offset)
    tail   = h[:tail]   || "\n"

    s = "\t%08x:" % (offset + add)
    ascii = ''
    size.times do |i|
      s << " " if i%8==0
      if i%16==0 && i>0
        s << "|%s|\n\t%08x: " % [ascii, offset + add + i]
        ascii = ''
      end
      c = data[offset+i].ord
      s << "%02x " % c
      ascii << ((32..127).include?(c) ? c.chr : '.')
    end
    printf "%-*s |%-16s|%s", 0x10*3+1, s, ascii, tail
  end


  targets = ARGV
  targets.each do |fname|
    anal = Analyzer.new(fname, options)
    %w'fname size type mimetype md5 histogram'.each{ |x| show(x, anal.send(x)) }
    if d = anal.data_past_eof
      show "data past EOF", d.size, :mark => "!", :tail => ' bytes'
      hexdump d, :add => anal.size_with_eof_marker, :size => 0x40, :tail => (d.size>0x40 ? "\n\t...\n" : '')
    end
  end
end
