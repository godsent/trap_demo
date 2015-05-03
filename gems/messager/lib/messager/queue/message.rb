class Messager::Queue::Message
  attr_accessor :icon_index, :damage, :text
  attr_writer :critical
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def critical?
    !!@critical
  end

  def damage?
    @damage.is_a? Numeric
  end

  def with_icon?
    @icon_index.is_a? Integer
  end
end