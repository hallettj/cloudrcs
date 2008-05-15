module CloudRCS
  
  class CommuteException < RuntimeError
  end

  class ApplyException < RuntimeError
  end

  class ParseException < RuntimeError
  end

  class GenerateException < RuntimeError
  end

  PATCH_TYPES = []

  class Patch < ActiveRecord::Base
    PATCH_DATE_FORMAT = '%Y%m%d%H%M%S'

    has_many(:patches, 
             :class_name => "PrimitivePatch", 
             :order => "position", 
             :dependent => :destroy)
    
    acts_as_list :scope => :owner_id

    validates_presence_of :author, :name, :date
    validates_presence_of :sha1
    validates_associated  :patches

    def before_validation
      self.sha1 ||= details_hash

      # Hack to make sure that associated primitive patches get saved
      # too.
      patches.each { |p| p.patch = self }
    end

    # Generates a new patch that undoes the effects of this patch.
    def inverse
      new_patches = patches.reverse.collect do |p|
        p.inverse
      end
      Patch.new(:author => author, 
                :name => name,
                :date => date,
                :inverted => true,
                :patches => new_patches)
    end

    # Given another patch, generates two new patches that have the
    # same effect as this patch and the given patch - except that the
    # new patches are applied in reversed order. So where self is
    # assumed to be applied before patch, the new analog of self is
    # meant to be applied after the new analog of patch.
    def commute(patch)
      commuted_patches = self.patches + patch.patches

      left = left_bound = self.patches.length - 1
      right = left + 1
      right_bound = commuted_patches.length - 1

      until left_bound < 0
        until left == right_bound
          commuted_patches[left], commuted_patches[right] = 
            commuted_patches[left].commute commuted_patches[right]
          left += 1
          right = left + 1
        end
        left_bound -= 1
        right_bound -= 1

        left = left_bound
        right = left + 1
      end
      
      patch1 = Patch.new(:author => patch.author,
                         :name => patch.name,
                         :date => patch.date,
                         :comment => patch.comment,
                         :inverted => patch.inverted,
                         :patches => commuted_patches[0...patch.patches.length])
      patch2 = Patch.new(:author => author,
                         :name => name,
                         :date => date,
                         :comment => comment,
                         :inverted => inverted,
                         :patches => commuted_patches[patch.patches.length..-1])
      return patch1, patch2
    end

    # Applies this patch a file or to an Array of files. This is
    # useful for testing purposes: you can try out the patch on a copy
    # of a file from the repository, without making any changes to the
    # official version of the file.
    def apply_to(file)
      patches.each do |p|
        file = p.apply_to file
      end
      return file
    end

    # Looks up the official versions of any files the patch is
    # supposed to apply to, and applies the changes. The patch is
    # recorded in the patch history associated with the working copy.
    def apply!
      patched_files = []
      patches.each { |p| patched_files << p.apply! }
      return patched_files
    end

    # Outputs the contents of the patch for writing to a file in a
    # darcs-compatible format.
    def to_s
      "#{details} {\n" +
        patches.join("\n") +
        "\n}\n"
    end

    def gzipped_contents
      Patch.deflate(to_s)
    end

    # Returns self as the sole element in a new array.
    def to_a
      [self]
    end
    
    # These two methods help to distinguish between named patches and
    # primitive patches.
    def named_patch?; true; end
    def primitive_patch?; false; end

    # Performs SHA1 digest of author and returns first 5 characters of
    # the result.
    def author_hash
      Digest::SHA1.hexdigest(author)[0...5]
    end

    # Packs patch details into a single string and performs SHA1 digest
    # of the contents.
    def details_hash
      complete_details = '%s%s%s%s%s' % [name, author, date_string, 
                                         comment ? comment.split("\n").collect do |l| 
                                           l.rstrip 
                                         end.join('') : '',
                                         inverted ? 't' : 'f']
      return Digest::SHA1.hexdigest(complete_details)
    end

    # Returns the patch header
    def details
      if comment.blank?
        formatted_comment = ""
      else
        formatted_comment = "\n" + comment.split("\n", -1).collect do |l|
          " " + l
        end.join("\n") + "\n"
      end
      "[#{name}\n#{author}*#{inverted ? '-' : '*'}#{date_string}#{formatted_comment}]"
    end

    # Returns a darcs-compatible file name for this patch.
    def file_name
      '%s-%s-%s.gz' % [date_string, author_hash, details_hash]
    end
    def filename
      file_name
    end

    # Returns true if this is the last patch in the patch history of
    # the associated filesystem.
    def last_patch?
      following_patches.empty?
    end

    # Returns a list of patches that follow this one in the patch
    # history. 
    def following_patches
      return @following_patches if @following_patches
      @following_patches = 
        Patch.find(:all, :conditions => ["owner_id = ? AND position > ?",
                                        owner.id, position])
    end

    protected

    def date_string
      date ? date.strftime(PATCH_DATE_FORMAT) : nil
    end
    
    class << self

      # Takes two files as arguments and returns a Patch that
      # represents differents between the files. The first file is
      # assumed to be a pristine file, and the second to be a modified
      # version of the same file.
      #
      # Determination of which patch types best describe a change and
      # how patches are generated is delegated to the individual patch
      # type classes.
      #
      # After each patch type generates its patches, those patches are
      # applied to the original file to prevent later patch types from
      # performing the same change.
      def generate(orig_file, changed_file, options={})

        # Patch generating operations should not have destructive
        # effects on the given file objects.
        orig_file = orig_file.deep_clone unless orig_file.nil?
        changed_file = changed_file.deep_clone unless changed_file.nil?

        patch = Patch.new(options)
        
        PATCH_TYPES.sort { |a,b| a.priority <=> b.priority }.each do |pt|
          new_patches = pt.generate(orig_file, changed_file).to_a
          patch.patches += new_patches
          new_patches.each { |p| p.patch = patch }  # Annoying, but necessary, hack
          new_patches.each { |p| orig_file = p.apply_to(orig_file) }
        end
        
        # Don't return empty patches
        unless patch.patches.length > 0
          patch = nil
        end

        # After all patches are applied to the original file, it
        # should be identical to the changed file.
        unless changed_file == orig_file
          raise GenerateException.new(true), "Patching failed! Patched version of original file does not match changed file."
        end
        
        return patch
      end
      
      # Produces a Patch object along with associated primitive
      # patches by parsing an existing patch file. patch should be a
      # string.
      def parse(patch_file)
        # Try to inflate the file contents, in case they are
        # gzipped. If they are not actually gzipped, Zlib will raise
        # an error.
        begin
          patch_file = inflate(patch_file) 
        rescue Zlib::GzipFile::Error
        end

        unless patch_file =~ /^\s*\[([^\n]+)\n([^\*]+)\*([-\*])(\d{14})\n?(.*)/m
          raise "Failed to parse patch file."
        end
        name = $1
        author = $2

        # inverted is a flag indicating whether or not this patch is a
        # rollback. Values can be '*', for no, or '-', for yes.
        inverted = $3 == '-' ? true : false

        # date is a string of digits exactly 14 characters long. Note
        # that in the year 9999 this code should be revised to allow 15
        # digits for date.
        date = $4.to_time

        # Unparsed remainder of the patch.
        remaining = $5

        # comment is an optional long-form explanation of the patch
        # contents. It is discernable from the rest of the patch file
        # by virtue of a single space placed at the beginning of every comment line.
        remaining_lines = remaining.split("\n", -1)
        comment_lines = []
        while remaining_lines.first =~ /^ (.*)$/
          comment << remaining_lines.unshift
        end
        comment = comment_lines.join("\n")

        unless remaining =~ /^\] \{\n(.*)\n\}\s*$/m
          raise "Failed to parse patch file."
        end

        # contents is the body of the patch. it contains a series of
        # primitive patches. We will split out each primitive patch
        # definition from this string and pass the results to the
        # appropriate classes to be parsed there.
        contents = $1

        contents = contents.split "\n" unless contents.blank?
        patches = []
        until contents.blank?
          # Find the first line of the next patch
          unless contents.first =~ /^(#{patch_tokens})/
            contents.shift
            next
          end

          # Record the patch token, which tells us what type of patch
          # this is; and move the line into another variable that tracks
          # the contents of the current patch.
          patch_token = $1
          patch_contents = []
          patch_contents << contents.shift

          # Keep pulling out lines until we hit the end of the
          # patch. The end of the patch is indicated by another patch
          # token, or by the end of the file.
          until contents.blank?
            if contents.first =~ /^(#{patch_tokens})/
              break
            else
              patch_contents << contents.shift
            end
          end

          # Send the portion of the file that we just pulled out to be
          # parsed by the appropriate patch class.
          patches << parse_primitive_patch(patch_token, patch_contents.join("\n"))
        end

        return Patch.new(:author => author,
                         :name => name,
                         :date => date,
                         :comment => comment,
                         :inverted => inverted,
                         :patches => patches)
      end

      # Given two parallel lists of patches with a common ancestor,
      # patches_a, and patches_b, returns a modified version of
      # patches_b that has the same effects, but that will apply
      # cleanly to the environment yielded by patches_a.
      def merge(patches_a, patches_b)
        return patches_b if patches_a.empty? or patches_b.empty?
        inverse_of_a = patches_a.reverse.collect { |p| p.inverse }
        commuted_b, commuted_inverse_of_a = commute(inverse_of_a, patches_b)
        return commuted_b
      end

      # Given two lists of patches that apply cleanly one after the
      # other, returns modified versions that each have the same
      # effect as their original counterparts - but that apply in
      # reversed order.
      def commute(patches_a, patches_b)
        commuted_patches = patches_a + patches_b
        
        left = left_bound = patches_a.length - 1
        right = left + 1
        right_bound = commuted_patches.length - 1
        
        until left_bound < 0
          until left == right_bound
            commuted_patches[left], commuted_patches[right] = 
              commuted_patches[left].commute commuted_patches[right]
            left += 1
            right = left + 1
          end
          left_bound -= 1
          right_bound -= 1
          
          left = left_bound
          right = left + 1
        end
        
        return commuted_patches[0...patches_b.length], commuted_patches[patches_b.length..-1]
      end

      # Compress a string into Gzip format for writing to a .gz file.
      def deflate(str)
        output = String.new
        StringIO.open(output) do |str_io|
          gzip = Zlib::GzipWriter.new(str_io)
          gzip << str
          gzip.close
        end
        return output
      end
      
      # Decompress string from Gzip format.
      def inflate(str)
        StringIO.open(str, 'r') do |str_io|
          gunzip = Zlib::GzipReader.new(str_io)
          gunzip.read
        end
      end

      protected
      
      # Parse the contents of the primitive patch by locating the class
      # that matches they patch_token and invoking its parse method.
      def parse_primitive_patch(patch_token, contents)
        patch_type = PATCH_TYPES.detect { |t| t.name =~ /^(.+::)?#{patch_token.camelize}$/ }
        patch_type.parse(contents)
      end

      # Return patch tokens for all known patch types as a single string
      # formatted for a regular expression. Tokens are joined by | so
      # the regex will match any of the tokens.
      def patch_tokens
        PATCH_TYPES.collect { |pt| pt.name.split('::').last.downcase }.join('|')
      end
      
    end
    
  end

end
