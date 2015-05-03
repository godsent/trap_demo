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
