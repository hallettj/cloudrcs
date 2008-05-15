module CloudRCS

  # A primitive patch type that represents the deletion of a file.
  class Rmfile < PrimitivePatch
    validates_presence_of :path
    
    def after_initialize
      verify_path_prefix
    end
    
    def to_s
      "rmfile #{self.class.escape_path(path)}"
    end

    def inverse
      Addfile.new(:path => path)
    end

    def commute(patch)
      if patch.is_a? Rmfile and patch.path == self.path
        raise CommuteException(true, "Conflict: cannot remove the same file twice.")
      elsif patch.is_a? Addfile and patch.path == self.path
        raise CommuteException(true, "Conflict: commuting rmfile and addfile yields two files with the same name.")
      elsif patch.is_a? Move and patch.path == self.path
        raise CommuteException(true, "Conflict: commuting rmfile and move yields two files with the same name.")
      else
        patch1 = patch.clone
        patch2 = self.clone
      end
      return patch1, patch2
    end

    # A special implementation of apply! is necessary in this case.
    def apply!
      file = locate_file(path)
      file.destroy unless file.blank?
      return file
    end

    def apply_to(file)
      return file unless file and file.path == path
      return nil  # Returning nil simulates deletion.
    end

    class << self

      def priority
        90
      end

      def generate(orig_file, changed_file)
        if changed_file.nil? and not orig_file.nil?
          return Rmfile.new(:path => orig_file.path)
        end
      end

      def parse(contents)
        unless contents =~ /^rmfile\s+(\S+)\s*$/
          raise "Failed to parse rmfile patch: #{contents}"
        end
        Rmfile.new(:path => unescape_path($1))
      end

    end

  end

  PATCH_TYPES << Rmfile

end
