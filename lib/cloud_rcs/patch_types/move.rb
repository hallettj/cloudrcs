module CloudRCS

  # A primitive patch type that represents that a file has been moved
  # or renamed.
  class Move < PrimitivePatch
    validates_presence_of :path, :original_path

    def after_initialize
      verify_path_prefix
      verify_original_path_prefix
    end

    def to_s
      "move #{self.class.escape_path(original_path)} #{self.class.escape_path(path)}"
    end

    # The inverse patch moves the file back to its original location.
    def inverse
      Move.new(:original_path => path, :path => original_path)
    end

    def commute(patch)
      if patch.is_a? Move
        if patch.original_path == self.new_path
          raise CommuteException(true, "Conflict: cannot commute move patches that affect the same file.")
        elsif patch.new_path == self.original_path
          raise CommuteException(true, "Conflict: commuting these move patches would result in two files with the same name.")
          
        elsif patch.new_path == self.new_path
          raise CommuteException(true, "Conflict: cannot commute move patches that affect the same files.")

        else
          patch1 = Move.new(:path => patch.path, :original_path => patch.original_path)
          patch2 = Move.new(:path => self.path, :original_path => self.original_path)
        end

      elsif patch.is_a? Addfile and patch.path == self.original_path
        raise CommuteException(true, "Conflict: move and addfile are order-dependent in this case.")

      elsif patch.is_a? Rmfile and patch.path == self.new_path
        raise CommuteException(true, "Conflict: move and rmfile are order-dependent in this case.")

      # If the other patch is something like a Hunk or a Binary, and
      # it operates on the file path that this patch moves a file to,
      # then the commuted version of that patch should have a file
      # path that matches the original_path of this patch.
      elsif patch.path == self.new_path
        patch1 = patch.clone
        patch1.path = self.original_path
        patch2 = self.clone

      else
        patch1 = patch.clone
        patch2 = self.clone
      end

      return patch1, patch2
    end

    def apply_to(file)
      if file.path == original_path
        file.path = new_path
      end
      return file
    end

    class << self

      def generate(orig_file, changed_file)
        return if orig_file.nil? or changed_file.nil?
        if orig_file.path != changed_file.path
          return Move.new(:original_path => orig_file.path, :path => changed_file.path)
        end
      end

      def parse(contents)
        unless contents =~ /^move\s+(\S+)\s+(\S+)\s*$/
          raise "Failed to parse move patch: \"#{contents}\""
        end
        Move.new(:original_path => unescape_path($1), :path => unescape_path($2))
      end

    end

  end

  PATCH_TYPES << Move

end
