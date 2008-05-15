module CloudRCS

  # A primitive patch type that represents a new or an undeleted file.
  class Addfile < PrimitivePatch
    validates_presence_of :path

    def after_initialize
      verify_path_prefix
    end

    def to_s
      "addfile #{self.class.escape_path(path)}"
    end

    def inverse
      Rmfile.new(:path => path)
    end

    def commute(patch)
      if patch.is_a? Addfile and patch.path == self.path
        raise CommuteException(true, "Conflict: cannot create two files with the same path.")
      elsif patch.is_a? Rmfile and patch.path == self.path
        raise CommuteException(true, "Conflict: commuting addfile with rmfile in this case would cause file to be removed before it is created.")
      elsif patch.is_a? Move and patch.original_path == self.path
        raise CommuteException(true, "Conflict: commuting addfile with move in this case would cause file to be moved before it is created.")
      else
        patch1 = patch.clone
        patch2 = self.clone
      end
      return patch1, patch2
    end

    def apply_to(file)
      return file unless file.nil?
      if patch.respond_to? :owner
        new_file = self.class.file_class.new(:owner => patch.owner,
                                             :contents => "",
                                             :content_type => "text/plain")
      else
        new_file = self.class.file_class.new(:contents => "",
                                             :content_type => "text/plain")
      end
      new_file.path = path
      return new_file
    end

    class << self

      # Addfile has a low priority so that it will appear before patches
      # that are likely to depend on it - such as Hunk patches.
      def priority
        10
      end

      def generate(orig_file, changed_file)
        if orig_file.nil? and not changed_file.nil?
          return Addfile.new(:path => changed_file.path, :contents => changed_file.content_type)
        end
      end

      def parse(contents)
        unless contents =~ /^addfile\s+(\S+)\s*$/
          raise "Failed to parse addfile patch: #{contents}"
        end
        Addfile.new(:path => unescape_path($1))
      end

    end

  end

  PATCH_TYPES << Addfile

end
