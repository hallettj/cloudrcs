module CloudRCS

  # PrimitivePatch acts as an intermediary between Patch and the
  # primitive patch types. It allows primitive patches to inherit
  # methods from Patch, and to use the same table. But it also allows
  # for defining behavior that differs from Patch but that is
  # automatically inherited by all primitive patch types.

  class PrimitivePatch < ActiveRecord::Base
    PATH_PREFIX = "./"

    # Primitive patches belong to a named patch and a file. They also
    # use the acts_as_list plugin to maintain a specific order within
    # the named patch.
    belongs_to :patch
#    belongs_to :file, :polymorphic => true
    
    #  validates_presence_of :patch_id
    #  validates_presence_of :file_id
    
    acts_as_list :column => :rank, :scope => :patch_id

    def apply!
      target_file = locate_file(original_path || path)
      old_target = target_file
      target_file = apply_to(target_file)
      if target_file.nil?
        old_target.destroy
      else
        target_file.save
      end
#      update_attribute(:file, target_file)
      return target_file
    end

    def named_patch?; false; end
    def primitive_patch?; true; end

#    def locate_file(path)
#      raise "You must override the locate_file method for PrimitivePatch."
#      self.class.file_class.locate(path)
#    end

    def apply_to(file)
      override "apply_to(file)"
    end

    def inverse
      override "inverse"
    end

    def commute(patch)
      override "commute(patch)"
    end

    def to_s
      override "to_s"
    end

    def to_a
      [self]
    end

    def new_path; path; end

    protected

    # Most primitive patches contain a file path. The darcs patch format
    # may require a different path prefix than CloudFiles do; so this
    # method makes the conversion if required.
    def verify_path_prefix
      unless path =~ /^#{PATH_PREFIX}/
          path = PATH_PREFIX + path unless path.blank?
      end
    end
    def verify_original_path_prefix
      unless original_path =~ /^#{PATH_PREFIX}/
          original_path = PATH_PREFIX + original_path unless original_path.blank?
      end
    end

    private

    def override(method)
      raise "Method '#{method}' should be overridden by each patch type."
    end

    class << self

      # Patch type priority represents the relative likelihood that a
      # patch type will cause conflicts if it is applied before other
      # patch types. Patch types with a high priority value are likely
      # to cause conflicts if they are applied early, and so should be
      # deferred until after other patch types have done their thing.
      #
      # Default priority is 50.
      def priority
        return 50
      end

      def generate(orig_file, changed_file)
        override "generate"
      end

      def parse(contents)
        override "parse"
      end

      def merge(patch_a, patch_b)
        patch_b_prime = commute(patch_a.inverse, patch_b).first
        return patch_a, patch_b_prime
      end
      
      # Returns class of :file association. Won't work with polymorphism.
#      def file_class
#        reflect_on_association(:file).class_name.constantize
#      end

      # Replace special charecters in file paths with ASCII codes
      # bounded by backslashes.
      def escape_path(path)
        # The backslash will be re-interpolated by the regular
        # expression; so four backslashes in the string definition are
        # necessary instead of two.
        special_chars = ['\\\\',' ']
        path.gsub(/#{special_chars.join('|')}/) { |match| "\\#{match[0]}\\" }
      end
      
      # Replace escaped characters with the original versions. Escaped
      # characters are of the format, /\\(\d{2,3})\\/; where the digits
      # enclosed in backslashes represent the ASCII code of the original
      # character.
      def unescape_path(path)
        path.gsub(/\\(\d{2,3})\\/) { $1.to_i.chr }
      end
      
      private
      
      def override(method)
        raise "Class method '#{method}' should be overridden by each patch type."
      end

    end

  end

end
