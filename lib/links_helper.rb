module LinksHelper
#  def url_for *args
#    washash = nil
#    args.map do |x|
#      if x.is_a?(Hash)
#        washash =
#          (washash ? '&' : '?') + x.map{ |y| CGI.escape(y.to_s) }.join('=').join('&')
#      else
#        x.to_s
#      end
#    end.join('/')
#  end

  def url_for *args
    r = ''
    args.each do |arg|
      r << case arg
        when Hash
          (r['?'] ? '&' : '?') + arg.map{ |x,y|
            CGI.escape(x.to_s) + "=" + CGI.escape(y.to_s)
          }.join('&')
        else
          '/' + CGI.escape(arg.to_s)
        end
    end
    r
  end
end
