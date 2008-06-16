Gem::Specification.new do |s|
  s.name = %q{cloudrcs}
  s.version = "0.0.1"

  s.specification_version = 2 if s.respond_to? :specification_version=

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jesse Hallett"]
  s.date = %q{2008-06-16}
  s.description = %q{A Ruby clone of darcs that uses ActiveRecord for storing patches.}
  s.email = ["hallettj@gmail.com"]
  s.extra_rdoc_files = ["History.txt", "License.txt", "Manifest.txt", "PostInstall.txt", "README.txt", "website/index.txt"]
  s.files = ["History.txt", "License.txt", "Manifest.txt", "PostInstall.txt", "README.txt", "Rakefile", "config/hoe.rb", "config/requirements.rb", "lib/active_record/acts/list.rb", "lib/acts_as_list.rb", "lib/cloud_rcs.rb", "lib/cloudrcs.rb", "lib/cloud_rcs/patch.rb", "lib/cloud_rcs/primitive_patch.rb", "lib/cloud_rcs/patch_types/addfile.rb", "lib/cloud_rcs/patch_types/binary.rb", "lib/cloud_rcs/patch_types/hunk.rb", "lib/cloud_rcs/patch_types/move.rb", "lib/cloud_rcs/patch_types/rmfile.rb", "lib/cloudrcs/version.rb", "script/console", "script/destroy", "script/generate", "script/txt2html", "setup.rb", "tasks/deployment.rake", "tasks/environment.rake", "tasks/website.rake", "test/test_cloudrcs.rb", "test/test_helper.rb", "website/index.html", "website/index.txt", "website/javascripts/rounded_corners_lite.inc.js", "website/stylesheets/screen.css", "website/template.html.erb"]
  s.has_rdoc = true
  s.homepage = %q{http://cloudrcs.rubyforge.org}
  s.post_install_message = %q{
For more information on cloudrcs, see http://github.com/hallettj/cloudrcs/tree/master
}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{cloudrcs}
  s.rubygems_version = %q{1.1.1}
  s.summary = %q{A Ruby clone of darcs that uses ActiveRecord for storing patches.}
  s.test_files = ["test/test_helper.rb", "test/test_cloudrcs.rb"]
  s.add_dependency("activerecord", [">= 2.1.0"])
  s.add_dependency("diff-lcs", [">= 1.1.0"])
end
