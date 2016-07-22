class Messager::Queue
  TIMEOUT = 30 #frames
  include AASM

  aasm do 
    state :ready, initial: true
    state :beasy

    event :load do
      transitions to: :beasy 

      after do
        show_message
      end

      after do
        Ticker.delay TIMEOUT do 
          check
        end
      end
    end

    event :release do 
      transitions to: :ready 
    end
  end

  def initialize(target)
    @target, @messages, = target, []
  end

  %w(hp tp mp).each do |postfix|
    %w(heal damage_to).each do |prefix|
      name = "#{prefix}_#{postfix}"
      define_method name do |value, critical = false|
        message = Messager::Queue::Message.new name.to_sym 
        message.damage = prefix == 'heal' ? -value : value
        message.critical = critical
        push message
      end
    end
  end

  def cast(spell)
    message = Messager::Queue::Message.new :cast 
    message.text = spell.name
    message.icon_index = spell.icon_index
    push message
  end

  def gain_item(item, number = 1, type = 'item')
    message = Messager::Queue::Message.new :"gain_#{type}" 
    message.text = "#{sign number}#{number} #{item.name}"
    message.icon_index = item.icon_index
    push message
  end

  def gain_weapon(item, number = 1)
    gain_item item, number, 'weapon'
  end

  def gain_armor(item, number = 1)
    gain_item item, number, 'armor'
  end

  def gain_gold(amount)
    message = Messager::Queue::Message.new :gain_gold
    text = "#{sign amount}#{amount} #{Messager::Vocab::Gold}"
    message.text = text
    push message
  end

  def push(message)
    @messages << message
    check if ready?
  end

  def push_text(text)
    push text_message(text)
  end

  def check
    @messages.any? ? load : release
  end

  def show_message
    if spriteset && message = @messages.shift
      spriteset.create_message_popup @target, message
    end
  end

  private

  def text_message(text)
    Messager::Queue::Message.new(:damage_to_hp).tap { |m| m.text = text }
  end

  def spriteset
    SceneManager.scene.instance_variable_get :@spriteset
  end

  def sign(amount)
    amount >= 0 ? '+' : '-'
  end
end

require 'messager/queue/message'