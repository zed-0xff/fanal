require 'yaml'

namespace :metadata do
  desc "delete specified key from all metadata files"
  task :delete_key do
    key = ENV['key'] || raise("gimme a key")
    Dir[File.join('data','?'*32,'metadata.yml')].each do |fname|
      metadata = YAML::load_file(fname)
      if metadata.delete(key) || metadata.delete(key.to_sym)
        File.open(fname,"w"){ |f| f << metadata.to_yaml }
      end
    end
  end
end

desc "deploy to server"
task :deploy do
  system %Q|rsync -avz . zed.0xff.me:/apps/anal --exclude "data/*" --exclude ".*" --exclude "tmp/*"|
  system %Q|ssh zed.0xff.me touch /apps/anal/tmp/restart.txt|
end

namespace :gems do
  desc "install required gems"
  task :install do
    system "gem install haml sinatra"
  end
end

namespace :foremost do
  desc "install foremost"
  task :install do
    Dir.chdir "tmp"
    system "wget -c http://foremost.sourceforge.net/pkg/foremost-1.5.7.tar.gz"
    system "tar xzf foremost-1.5.7.tar.gz"
    Dir.chdir "foremost-1.5.7"
    Dir['../../misc/foremost*.patch'].each do |fname|
      system "patch -p0 < #{fname}"
    end
    system "make"
    system "sudo make install"
    system "make clean"
    system "rm -rf tmp/foremost*"
  end
end
