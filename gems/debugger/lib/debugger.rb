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

require 'debugger/console'
require 'debugger/game_window'
require 'debugger/renderer'

require 'debugger/patch'
