require 'yaml'

class Foremost
  def initialize fname,opts={}
    @fname = fname
    @cache_file = opts[:cache_file]
    @force = opts[:force]
  end

  def scan
    if @cache_file && File.exist?(@cache_file) && !@force
      YAML::load_file(@cache_file)
    else
      t0 = Time.now
      r = `foremost -W #@fname`.force_encoding('binary').scan(
        /^\d+:[ \t]+\d+\.([^ \t]*)[ \t]+(\d+)[ \t]+(\d+)[ \t]*(.*)$/
      ).map do |row|
        row[0].upcase!        # type
        row[1] = row[1].to_i  # size
        row[2] = row[2].to_i  # offset
        row.last.strip!       # comment
        row.pop if row.last == ""
        row
      end.sort_by{ |row| row[2] }
      if Time.now-t0 > 0.1 && @cache_file
        File.open(@cache_file,"w") do |f|
          f << r.to_yaml
        end
      end
      r
    end
  end

  def self.scan *args
    Foremost.new(*args).scan
  end
end
