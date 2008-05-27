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
      unless hex_contents[position...position+lengthold] == removed
        raise ApplyException.new(true), "Portion of binary patch marked for removal does not match existing contents in file. Existing contents at position #{position}: '#{hex_contents[position...position+lengthold]}' ; marked for removal: '#{removed}'"
      end

      # Then, remove stuff
      unless removed.blank?
        hex_contents[position...position+lengthold] = ""
      end

      # Finally, add stuff
      unless added.blank?
        hex_contents.insert(position, added)
      end

      file.contents = Binary.hex_to_binary(hex_contents)
      return file
    end

    def inverse
      Binary.new(:path => path,
                 :position => position,
                 :contents => [added, removed],
                 :inverted => true)
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
          raise CommuteException.new(true), "Conflict: binary patches overlap."
        end
        
      elsif patch.is_a? Rmfile and patch.path == self.path
        raise CommuteException.new(true), "Conflict: cannot modify a file after it is removed."

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
      old = removed.scan(/.{1,78}/).collect { |c| '-' + c }.join("\n")
      new = added.scan(/.{1,78}/).collect { |c| '+' + c }.join("\n")
      return [header, old, new].delete_if { |e| e.blank? }.join("\n")
    end

    def removed
      contents.first
    end

    def added
      contents.last
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
        return unless orig_file.contents.is_binary_data? or changed_file.contents.is_binary_data?

        # Convert binary data to hexadecimal for storage in a text
        # file
        orig_hex = orig_file ? binary_to_hex(orig_file.contents).scan(/.{2}/) : []
        changed_hex = changed_file ? binary_to_hex(changed_file.contents).scan(/.{2}/) : []

        file_path = orig_file ? orig_file.path : changed_file.path

        diffs = Diff::LCS.diff(orig_hex, changed_hex)
        chunks = []
        offset = 0
        diffs.each do |d|

          # We need to recalculate positions for removals - just as in
          # hunk generation.
          unless chunks.empty?
            offset += chunks.last.lengthnew - chunks.last.lengthold
          end
          d.collect! do |l|
            if l.action == '-'
              Diff::LCS::Change.new(l.action, l.position + (offset / 2), l.element)
            else
              l
            end
          end

          position = d.first.position * 2

          removed = d.find_all { |l| l.action == '-' }.collect { |l| l.element }.join
          added = d.find_all { |l| l.action == '+' }.collect { |l| l.element }.join
          
          unless removed.blank? and added.blank?
            chunks << Binary.new(:contents => [removed, added],
                                 :position => position,
                                 :path => file_path)
          end
          
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

        removed = removed.join
        added = added.join

        return Binary.new(:path => file_path, 
                          :position => starting_position, 
                          :contents => [removed, added])
      end
      
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

  end
  
  PATCH_TYPES << Binary

end
