class Histogram
  def initialize cc, height=200
    @char_counts = cc.dup
    @height = height
  end

  def normalized_counts
    d = 1.0*@height/@char_counts.max;
    @char_counts.map{ |c| (c*d).to_i }
  end

#  def to_html
#    r = "<table class='histogram'><tr>"
#    @char_counts.each_with_index do |c,idx|
#      r << "<td style='height:#{c}px'></td>"
#    end
#    r << "</tr></table>"
#  end

  def to_html
    r = "<div class='histogram'>"
    normalized_counts.each_with_index do |c,idx|
      if c > 0
        r << "<p title='0x%02x : %d' style='height:%dpx;top:%dpx'/>" % [idx, @char_counts[idx], c, @height-c]
      else
        c = 1
        r << "<p class='zero' title='0x%02x : %d' style='height:%dpx;top:%dpx'/>" % [idx, @char_counts[idx], c, @height-c]
      end
    end
    r << "</div>"
  end
end
