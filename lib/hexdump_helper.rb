module HexdumpHelper
  def hexdump data, h = {}
    offset = h[:offset] || 0
    add    = h[:add]    || 0
    size   = h[:size]   || (data.size-offset)
    tail   = h[:tail]   || "\n"
    width  = h[:width]  || 0x10                 # row width, in bytes

    s = "%08x: " % (offset + add)
    ascii = ''
    size.times do |i|
      s << " " if i%width%8==0
      if i%width==0 && i>0
        s << "|%s|\n%08x:  " % [ascii, offset + add + i]
        ascii = ''
      end
      c = data[offset+i].ord
      s << "%02x " % c
      ascii << ((32..126).include?(c) ? c.chr : '.')
    end
    s << '   '*(width-size%width) if size%width > 0
    "%s |%-*s|%s" % [s, width, ascii, tail]
  end
end
