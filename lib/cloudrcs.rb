$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

gem 'activerecord', '>= 2.0'
gem 'diff-lcs', '>= 1.1'

require 'activerecord'
require 'diff/lcs'

require 'acts_as_list'
require 'cloud_rcs'
