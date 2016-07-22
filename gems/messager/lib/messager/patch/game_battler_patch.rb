class Game_Battler
  include Messager::Concerns::Queueable

  def add_hp_with_popup(value)
    self.hp += value
    heal_popup value, :hp
  end

  def add_mp_with_popup(value)
    self.mp += value
    heal_popup value, :mp
  end

  def add_tp_with_popup(value)
    self.tp += value
    heal_popup value, :tp
  end

  def add_en_with_popup(value)
    self.energy += value
    heal_popup value, :energy
  end

  def heal_popup(value, key)
    message_queue.push damage_message(value, key) if on_screen?
  end

  private

  def on_screen?
    respond_to?(:screen_x) && respond_to?(:screen_y)
  end

  def damage_message(value, key, critical = false)
    type = value > 0 ? :"heal_#{key}" : :"damage_to_#{key}"
    Messager::Queue::Message.new(type).tap do |message|
      message.damage = -value
      message.critical = critical
    end
  end
end