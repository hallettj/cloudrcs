module CloudRCS

  class Binary < PrimitivePatch

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

    class << self

      def generate(orig_file, changed_file)
        override "generate"
      end
      
      def parse(contents)
        override "parse"
      end
      
    end

    protected

    # We want to store the contents of a binary file encoded as a
    # hexidecimal number. These two methods allow for translating
    # between binary and hexidecimal.
    #
    # Code borrowed from:
    # http://4thmouse.com/index.php/2008/02/18/converting-hex-to-binary-in-4-languages/
    def hex_to_binary(hex)
      hex.to_a.pack("H*")
    end

    def binary_to_hex(bin)
      bin.unpack("H*")
    end
    
  end
  
  PATCH_TYPES << Binary

end
