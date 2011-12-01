#!/usr/bin/env ruby

module HexdumpHelper
  def hexdump data, h = {}
    offset = h[:offset] || 0
    add    = h[:add]    || 0
    size   = h[:size]   || (data.size-offset)
    tail   = h[:tail]   || "\n"
    width  = h[:width]  || 0x10                 # row width, in bytes

    size = data.size-offset if size+offset > data.size

    r = ''; s = ''
    r << "%08x: " % (offset + add)
    ascii = ''
    size.times do |i|
      if i%width==0 && i>0
        r << "%s |%s|\n%08x: " % [s, ascii, offset + add + i]
        ascii = ''; s = ''
      end
      s << " " if i%width%8==0
      c = data[offset+i].ord
      s << "%02x " % c
      ascii << ((32..126).include?(c) ? c.chr : '.')
    end
    r << "%-*s |%-*s|%s" % [width*3+width/8+(width%8==0?0:1), s, width, ascii, tail]
  end
end

if $0 == __FILE__
  include HexdumpHelper
  width = (ARGV.first || 16).to_i
  (0..0x22).each do |n|
    puts hexdump("X"*n, :tail => " 0x%02x" % n, :width => width)
  end
end
