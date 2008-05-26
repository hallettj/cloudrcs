module CloudRCS

  class Binary < PrimitivePatch
    serialize :contents, Array

    validates_presence_of :path, :contents, :position
    validates_numericality_of :position, :only_integer => true, :greater_than_or_equal_to => 0

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

    def apply_to(file)
      return file unless file.path == path

      hex_contents = Binary.binary_to_hex(file.contents)

      # Check that the patch matches the file contents
      unless hex_contents[position...position+lengthold] ==
          removed.collect { |r| r.element }.join
        raise ApplyException.new(true, "Portion of binary patch marked for removal does not match existing contents in file.")
      end

      # Then, remove stuff
      hex_contents[position...position+lengthold] = ""

      # Finally, add stuff
      added.each_with_index do |d,i|
        hex_contents.insert(position + i, d.element)
      end

      file.contents = Binary.hex_to_binary(hex_contents)
      return file
    end

    def inverse
      new_removals = added.collect do |d|
        Diff::LCS::Change.new('-', d.position, d.element)
      end
      new_adds = removed.collect do |d|
        Diff::LCS::Change.new('+', d.position, d.element)
      end
      Hunk.new(:path => path, :position => position, :contents => (new_removals + new_adds))
    end

    def commute(patch)
      if patch.is_a? Binary and patch.path == self.path

        # self is applied first and precedes patch in the file
        if self.position + self.lengthnew < patch.position
          patch1 = Binary.new(:path => patch.path,
                            :position => (patch.position - self.lengthnew + self.lengthold),
                            :contents => patch.contents)
          patch2 = Binary.new(:path => self.path, 
                              :position => self.position, 
                              :contents => self.contents)
          
        # self is applied first, but is preceded by patch in the file          
        elsif patch.position + patch.lengthold < self.position
          patch1 = Binary.new(:path => patch.path, 
                              :position => patch.position, 
                              :contents => patch.contents)
          patch2 = Binary.new(:path => self.path, 
                            :position => (self.position + patch.lengthnew - patch.lengthold),
                            :contents => self.contents)
          
        # patch precedes self in file, but bumps up against it
        elsif patch.position + patch.lengthnew == self.position and
            self.lengthold != 0 and patch.lengthold != 0 and 
            self.lengthnew != 0 and patch.lengthnew != 0
          patch1 = Binary.new(:path => patch.path, 
                              :position => patch.position, 
                              :contents => patch.contents)
          patch2 = Binary.new(:path => self.path, 
                              :position => (self.position - patch.lengthnew + patch.lengthold), 
                              :contents => self.contents)
          
        # self precedes patch in file, but bumps up against it
        elsif self.position + self.lengthold == patch.position and
            self.lengthold != 0 and patch.lengthold != 0 and 
            self.lengthnew != 0 and patch.lengthnew != 0
          patch1 = Binary.new(:path => patch.path,
                              :position => patch.position,
                              :contents => patch.contents)
          patch2 = Binary.new(:path => self.path, 
                              :position => (self.position + patch.lengthnew - patch.lengthold), 
                              :contents => self.contents)
          
        # Patches overlap. This is a conflict scenario
        else
          raise CommuteException.new(true, "Conflict: binary patches overlap.")
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

    def to_s
      header = "binary #{self.class.escape_path(path)} #{position}"
      old = removed.collect { |d| d.element }.join.scan(/.{1,78}/).collect do |c|
        '-' + c
      end.join("\n")
      new = added.collect { |d| d.element }.join.scan(/.{1,78}/).collect do |c|
        '+' + c
      end.join("\n")
      return [header, old, new].join("\n")
    end

    def removed
      contents.find_all { |d| d.action == '-' }
    end

    def added
      contents.find_all { |d| d.action == '+' }
    end

    def lengthold
      removed.length
    end
    
    def lengthnew
      added.length
    end

    class << self

      # Use a low priority so that the binary patch generating method
      # will be called before the hunk patch generating method
      def priority
        20
      end

      def generate(orig_file, changed_file)
        unless orig_file.contents.is_binary_data? or 
            changed_file.contents.is_binary_data?
          return
        end

        # Convert binary data to hexadecimal for storage in a text
        # file
        orig_hex = orig_file ? binary_to_hex(orig_file.contents) : ""
        changed_hex = changed_file ? binary_to_hex(changed_file.contents) : ""

        file_path = orig_file ? orig_file.path : changed_file.path

        diffs = Diff::LCS(orig_hex, changed_hex)
        chunks = []
        diffs.each do |d|
          
          chunks << Binary.new(:contents => d,
                               :position => d.first.position,
                               :path => file_path)
          
        end
        
        return chunks
      end
      
      def parse(contents)
        unless contents =~ /^binary\s+(\S+)\s+(\d+)\s+(.*)$/m
          raise ParseException.new(true), "Failed to parse binary patch: \"#{contents}\""
        end
        file_path = unescape_path($1)
        starting_position = $2.to_i
        contents = $3

        removed, added = [], []
        removed_offset = 0
        added_offset = 0
        contents.split("\n").each do |line|
          if line =~ /^-([\S]*)\s*$/
            removed << $1
            removed_offset += 1
          elsif line =~ /^\+([\S]*)\s*$/
            added << $1
            added_offset += 1
          else
            raise "Failed to parse a line in binary patch: \"#{line}\""
          end
        end

        removed = removed.join.scan(/.{1}/).collect do |r|
          Diff::LCS::Change.new('-', starting_position + removed_offset, r)
        end
        added = added.join.scan(/.{1}/).collect do |r|
          Diff::LCS::Change.new('+', starting_position + added_offset, r)
        end

        return Binary.new(:path => file_path, 
                          :position => starting_position, 
                          :contents => (removed + added))
      end
    end

    protected

    # We want to store the contents of a binary file encoded as a
    # hexidecimal value. These two methods allow for translating
    # between binary and hexidecimal.
    #
    # Code borrowed from:
    # http://4thmouse.com/index.php/2008/02/18/converting-hex-to-binary-in-4-languages/
    def hex_to_binary(hex)
      hex.to_a.pack("H*")
    end

    def binary_to_hex(bin)
      bin.unpack("H*").first
    end
    
  end
  
  PATCH_TYPES << Binary

end
