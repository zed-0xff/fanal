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
