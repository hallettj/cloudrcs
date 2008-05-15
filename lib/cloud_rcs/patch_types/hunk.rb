module CloudRCS

  # Hunk is one type of primitive patch. It represents a deletion or
  # an insertion, or a combination of both, in a text file.
  #
  # A Hunk is constructed using the path of a file, the first line
  # modifications to the file, and a set of diffs, each of which
  # represents a line added to or deleted from the file.

  class Hunk < PrimitivePatch
    serialize :contents, Array

    validates_presence_of :path, :contents, :line
    validates_numericality_of :line, :only_integer => true, :greater_than_or_equal_to => 1

    def validate
      # Make sure diffs only contain the actions '+' and '-'
      if contents.respond_to? :each
        contents.each do |d|
          unless ['+','-'].include? d.action
            errors.add(:contents, "contains an unknown action.")
          end
        end
      end
    end

    #   def after_initialize
    #     verify_path_prefix
    #     starting_line ||= contents.first.position
    #   end
    
    def to_s
      "hunk #{self.class.escape_path(path)} #{line}\n" + contents.collect do |d|
        "#{d.action}#{d.element}"
      end.join("\n")
    end

    # The inverse of a Hunk simply swaps adds and deletes.
    def inverse
      new_removals = added_lines.collect do |d|
        Diff::LCS::Change.new('-', d.position, d.element)
      end
      new_adds = removed_lines.collect do |d|
        Diff::LCS::Change.new('+', d.position, d.element)
      end
      Hunk.new(:path => path, :line => line, :contents => (new_removals + new_adds))
    end

    # Given another patch, generates two new patches that have the
    # same effect as the original two, but with the order of the
    # analagous patches reversed. The message receiver is the first
    # patch, and the argument is the second; so after commuting the
    # analog of this patch will be second.
    def commute(patch)
      if patch.is_a? Hunk

        # self is applied first and precedes patch in the file
        if self.line + self.lengthnew < patch.line
          patch1 = Hunk.new(:path => patch.path,
                            :line => (patch.line - self.lengthnew + self.lengthold),
                            :contents => patch.contents)
          patch2 = Hunk.new(:path => self.path, :line => self.line, :contents => self.contents)
          
        # self is applied first, but is preceded by patch in the file          
        elsif patch.line + patch.lengthold < self.line
          patch1 = Hunk.new(:path => patch.path, :line => patch.line, :contents => patch.contents)
          patch2 = Hunk.new(:path => self.path, 
                            :line => (self.line + patch.lengthnew - patch.lengthold),
                            :contents => self.contents)
          
        # patch precedes self in file, but bumps up against it
        elsif patch.line + patch.lengthnew == self.line and
            self.lengthold != 0 and patch.lengthold != 0 and 
            self.lengthnew != 0 and patch.lengthnew != 0
          patch1 = Hunk.new(:path => patch.path, :line => patch.line, :contents => patch.contents)
          patch2 = Hunk.new(:path => self.path, 
                            :line => (self.line - patch.lengthnew + patch.lengthold), 
                            :contents => self.contents)
          
        # self precedes patch in file, but bumps up against it
        elsif self.line + self.lengthold == patch.line and
            self.lengthold != 0 and patch.lengthold != 0 and 
            self.lengthnew != 0 and patch.lengthnew != 0
          patch1 = Hunk.new(:path => patch.path, :line => patch.line, :contents => patch.contents)
          patch2 = Hunk.new(:path => self.path, 
                            :line => (self.line + patch.lengthnew - patch.lengthold), 
                            :contents => self.contents)
          
        # Patches overlap. This is a conflict scenario
        else
          raise CommuteException.new(true, "Conflict: hunk patches overlap.")
        end
        
      elsif patch.is_a? Rmfile and patch.path == self.path
        raise CommuteException.new(true, "Conflict: cannot modify a file after it is removed.")

      elsif patch.is_a? Move and self.path == patch.original_path
        patch1 = patch.clone
        patch2 = self.clone
        patch2.path = patch.new_path
        
      # Commutation is trivial
      else
        patch1, patch2 = patch, self
      end
      
      return patch1, patch2
    end

    def apply_to(file)
      return file unless file.path == path

      # Passing a negative number as the second argument of split
      # preserves trailing newline characters at the end of the file
      # when the lines are re-joined.
      lines = file.contents.split("\n",-1)

      # First, remove lines
      removed_lines.each do |d|
        if lines[line-1] == d.element.sub(/(\s+)\$\s*$/) { $1 }
          lines.delete_at(line-1)
        else
          raise ApplyException.new(true), "Line in hunk marked for removal does not match contents of existing line in file<br/>#{line-1} -'#{lines[line-1]}'<br/>#{d.position} -'#{d.element}'"
        end
      end

      # Next, add lines
      added_lines.each_with_index do |d,i|
        lines.insert(line - 1 + i, d.element.sub(/(\s+)\$\s*$/) { $1 })
      end

      file.contents = lines.join("\n")
      return file
    end

    # Returns the number of lines added by the hunk patch
    def lengthnew
      added_lines.length
    end

    # Returns the number of lines removed by the hunk patch
    def lengthold
      removed_lines.length
    end

    def removed_lines
      contents.find_all { |d| d.action == '-' }   # .sort { |a,b| a.position <=> b.position }
    end

    def added_lines
      contents.find_all { |d| d.action == '+' }   # .sort { |a,b| a.position <=> b.position }
    end

    class << self

      # Given a list of files, determine whether this patch type
      # describes the changes between the files and generate patches
      # accordingly.
      #
      # In this case we use the Diff::LCS algorithm to generate Change
      # objects representing each changed line between two files. The
      # changesets are automatically nested into a two dimensional
      # Array, where each row represents a changed portion of the file
      # that is separated from the other rows by an unchanged portion
      # of the file. So we split that dimension of the Array into
      # separate Hunk patches and return the resulting list.
      def generate(orig_file, changed_file)
        return if orig_file.nil? and changed_file.nil?

        # If the original or the changed file is nil, the hunk should
        # contain the entirety of the other file. This is so that a
        # record is kept of a file that is deleted; and so that the
        # contents of a file is added to it after it is created.
        orig_lines = orig_file ? orig_file.contents.split("\n",-1) : []
        changed_lines = changed_file ? changed_file.contents.split("\n",-1) : []

        # Insert end-of-line tokens to preserve white space at the end
        # of lines. This is part of the darcs patch format.
        orig_lines.each { |l| l += "$" if l =~ /\s+$/ }
        changed_lines.each { |l| l += "$" if l =~ /\s+$/ }

        file_path = orig_file ? orig_file.path : changed_file.path

        diffs = Diff::LCS.diff(orig_lines, changed_lines)
        hunks = []
        offset = 0
        diffs.each do |d|
          
          # Diff::LCS assumes that removed lines from all hunks will be
          # removed from file before new lines are added. Unfortunately,
          # in this implementation we remove and add lines from each
          # hunk in order. So the position values for removed lines will
          # be off in all but the first hunk. So we need to adjust those
          # position values before we create the hunk patch.
          unless hunks.empty?
            offset += hunks.last.lengthnew - hunks.last.lengthold
          end
          d.collect! do |l|
            if l.action == '-'
              Diff::LCS::Change.new(l.action, l.position + offset, l.element)
            else
              l
            end
          end        

          # The darcs patch format counts lines starting from 1; whereas
          # Diff::LCS counts lines starting from 0. So we add 1 to the
          # position of the first changed line to get the
          # darcs-compatible starting line number for the Hunk patch.
          line = d.first.position + 1
          
          hunks << Hunk.new(:path => file_path, :line => line, :contents => d)
        end
        return hunks
      end

      # Parse hunk info from a file and convert into a Hunk object.
      def parse(contents)
        unless contents =~ /^hunk\s+(\S+)\s+(\d+)\s+(.*)$/m
          raise ParseException.new(true), "Failed to parse hunk patch: \"#{contents}\""
        end
        file_path = unescape_path($1)
        starting_line = $2.to_i
        contents = $3

        last_action = nil
        line_offset = 0

        diffs = []
        add_line_offset = 0
        del_line_offset = 0
        contents.split("\n").each do |line|
          # These regular expressions ensure that each line ends with a
          # non-whitespace character, or is empty. A dollar sign is
          # added during patch generation to the end of lines that end
          # in whitespace; so parsing this way will not cut off
          # whitespace that is supposed to be added to any patched file.
          #
          # If the line is empty, $1 will be nil. So it is important to
          # pass $1.to_s instead of just $1 to change nil to "".
          if line =~ /^\+(.*[\S\$])?\s*$/
            diffs << Diff::LCS::Change.new('+', starting_line + add_line_offset, $1.to_s)
            add_line_offset += 1
          elsif line =~ /^-(.*[\S\$])?\s*$/
            diffs << Diff::LCS::Change.new('-', starting_line + del_line_offset, $1.to_s)
            del_line_offset += 1
          else
            raise "Failed to parse a line in hunk: \"#{line}\""
          end
        end

        return Hunk.new(:path => file_path, :line => starting_line, :contents => diffs)
      end

    end
    
  end

  PATCH_TYPES << Hunk

end
