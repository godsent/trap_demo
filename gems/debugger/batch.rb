#gems/debugger/lib/debugger.rb
class Debugger
  VERSION = '0.0.2'
  WORDS = {
    hello: "debug console activated from %s, version: #{VERSION}",
    bye:   "good bye"
  }
  TRIGGER = Input::F5
  WIN  = {
    focus:     Win32API.new('user32', 'BringWindowToTop', 'I', 'I'),
    find:      Win32API.new('user32', 'FindWindow', 'PP', 'I'),
    get_title: Win32API.new('kernel32', 'GetConsoleTitle', 'PI', 'I'),
  }
  PROMPTS = {
    result:   "=> ",
    enter:    "> ",
    continue: "* "
  }
  SIGNALS = {
    close: 'exit',
    clear: 'clear_eval'
  }
  CLOSE_SIGNAL = 'exit'

  class << self
    def render(binding, render_constants = false)
      Renderer.render binding, render_constants
    end

    #Loads Console
    def load_console(binding = Object.__send__(:binding))
      say_hello binding
      focus Console.window #focus on debug console window
      Console.run(binding) #run with binding
    end

    #methods checks if user input is a signal
    def handle_signal(signal)
      case signal.chop     #remove new line in the end
      when SIGNALS[:close] #when user going to close the console
        close_console
      when SIGNALS[:clear] #when user going to clear eval stack
        Console.clear_eval
        :continue
      end
    end

    private

    def say_hello(binding) #greeting words
      klass, separator = binding.eval "is_a?(Class) ? [self, '.'] : [self.class, '#']"
      method_name      = binding.eval '__method__'
      puts WORDS[:hello] % "#{klass.name}#{separator}#{method_name}"
    end

    #closes console
    def close_console
      puts WORDS[:bye]        #say good bye
      focus GameWindow.window #focus the game window
      Console.close
      sleep 1                 #hack, prevent enter in the game window
      raise StopIteration     #stops loop
    end

    #we have two winows - console and game window
    #method to focuse one of them
    def focus(window)
      WIN[:focus].call window
    end
  end
end


#gems/debugger/lib/debugger/console.rb
class Debugger
  class Console
    class << self
      #runs console
      def run(binding)
        @current_instance = new binding #initialize new instance and store it
        @current_instance.run           #run new console instance
      end

      #returns console window via win32 api
      def window
        WIN[:find].call 'ConsoleWindowClass', title
      end

      #clears eval stack
      def clear_eval
        @current_instance.clear_eval
      end

      def close
        @current_instance = nil
      end

      private

      #returns title of the console window
      def title
        ("\0" * 256).tap do |buffer|
          WIN[:get_title].call(buffer, buffer.length - 1)
        end.gsub "\0", ''
      end
    end

    def initialize(binding)
      @binding = binding #store binding
      clear_eval         #clear eval stack (set it to empty string)
    end

    #sets eval stack to empty string
    def clear_eval
      @to_eval = ''
    end

    #eval loop
    def run
      loop do
        prompt #prints prompt to enter command
        gets.tap do |code| #gets - returns user's input
          evaluate code unless code.nil? || Debugger.handle_signal(code) == :continue #evaluate code
        end
      end
    end

    private

    #prints prompt
    def prompt
      if @to_eval != ''
        Debugger::PROMPTS[:continue] #when eval stack is not empty
      else
        Debugger::PROMPTS[:enter]    #when eval stack is empty
      end.tap { |string| print string }
    end

    #evals code
    def evaluate(code)
      @to_eval << code #add code to stack
      result(eval @to_eval, @binding) #evals code
    rescue SyntaxError #when sytax error happens do nothing (do not clear stack)
    rescue Exception => e #return error to the console
      puts e.message
      clear_eval
    end

    #clears eval stack and prints result
    def result(res)
      clear_eval
      puts Debugger::PROMPTS[:result] + res.to_s
    end
  end
end
#gems/debugger/lib/debugger/game_window.rb
class Debugger
  class GameWindow
    class << self
      #returns game window
      def window
        WIN[:find].call 'RGSS Player', game_title
      end

      private

      def game_title
        @game_title ||= load_data('Data/System.rvdata2').game_title
      end
    end
  end
end
#gems/debugger/lib/debugger/renderer.rb
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
#gems/debugger/lib/debugger/patch.rb
module Debugger::Patch
end

#gems/debugger/lib/debugger/patch/binding_patch.rb
class Binding
  def bug
    Debugger.load_console self
  end
end
#gems/debugger/lib/debugger/patch/scene_base_patch.rb
class Scene_Base
  alias_method :original_update_basic_for_debugger, :update_basic

  def update_basic(*args, &block)
    Debugger.load_console if Input.trigger? Debugger::TRIGGER
    original_update_basic_for_debugger *args, &block
  end
end
