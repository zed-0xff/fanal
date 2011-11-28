require 'zipruby'

module UnzipHelper

  @@comp_methods = Hash[*
  [
    "CM_DEFAULT","CM_STORE","CM_SHRINK","CM_REDUCE_1","CM_REDUCE_2", "CM_REDUCE_3", "CM_REDUCE_4",
    "CM_IMPLODE","CM_DEFLATE","CM_DEFLATE64","CM_PKWARE_IMPLODE","CM_BZIP2"
  ].map{ |name| [Zip::const_get(name), name.sub("CM_","").downcase ] }.flatten]

  def comp_method_name m
    "%d (%s)" % [m, @@comp_methods[m] || "???"]
  end
end
