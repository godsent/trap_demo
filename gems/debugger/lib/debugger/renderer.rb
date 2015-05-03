class Debugger
  class Renderer
    FILE_NAME = 'debugger.txt'

    def self.render(binding, include_constants = false)
      new(binding, include_constants).render
    end

    def initialize(binding, include_constants)
      @binding, @include_constants = binding, include_constants
    end

    def render
      in_file do |file|
        keys.each do |key|
          write key, file
        end
      end
    end

    def keys
      arr = %w(local_variables instance_variables)
      @include_constants ? arr + ['self.class.constants'] : arr
    end

    def in_file
      File.open(File.join(Dir.pwd, FILE_NAME), 'a') { |file| yield file }
    end

    def write(key, file)
      @binding.eval(key).map do |element|
        "#{element} => #{@binding.eval(element.to_s)}"
      end.tap do |result|
        file.puts "#{key}:"
        file.puts result
        file.puts
      end
    end
  end
end
