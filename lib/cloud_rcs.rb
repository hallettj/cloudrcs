require 'cloud_rcs/patch'
require 'cloud_rcs/primitive_patch'

patch_types_dir = File.dirname(__FILE__) + '/cloud_rcs/patch_types'
Dir.entries(patch_types_dir).each do |e|
  require [patch_types_dir,e].join('/') unless e =~ /^\./
end
