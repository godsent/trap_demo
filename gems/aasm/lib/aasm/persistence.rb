module AASM
  module Persistence
    class << self

      def load_persistence(base)
        include_persistence base, :plain
      end

      private

      def include_persistence(base, type)
        base.send(:include, constantize("AASM::Persistence::#{capitalize(type)}Persistence"))
      end

      def capitalize(string_or_symbol)
        string_or_symbol.to_s.split('_').map {|segment| segment[0].upcase + segment[1..-1]}.join('')
      end

      def constantize(string)
        instance_eval(string)
      end

    end # class << self
  end
end # AASM
