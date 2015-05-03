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
