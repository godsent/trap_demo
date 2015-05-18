class Trap::Options
  def self.build(&block)
    new.tap { |b| b.instance_eval(&block) }
  end

  def initialize
    @options = {}
  end

  def to_h
    @options 
  end

  def method_missing(key, value)
    @options[key] = value 
  end

  def events(*evs)
    evs = evs.first.is_a?(Range) ? evs.map(&:to_a) : evs
    @options[:events] = evs.flatten
  end

  def route(value = nil, &block)
    @options[:route] = block_given? ? Trap::Route.draw(&block) : value
  end

  def sprite(value = nil, &block)
    @options[:sprite] = if block_given?
      init_and_eval block
    else
      value
    end
  end

  def states(*ids)
    @options[:states] = ids.flatten
  end

  def [](key)
    @options[key]
  end

  def init_and_eval(block)
    Trap::Options.new.tap { |o| o.instance_eval(&block) }
  end
end