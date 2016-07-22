class Trap::Touch < Trap::Fireboll
  include Trap::Defaults::Touch
  include Trap::Concerns::Eventable

  def deal_damage
    super { emit :catched }
  end

  def stop 
    super unless idle?
  end

  private

  def tick_job
    super { emit :evaded }
  end

  def check_collision 
    super do |trap|
      emit :catched
      trap.emit :catched
    end
  end

  def apply_damage(*); end 
  def apply_states(*); end

  def option_keys
    [:catched, :evaded]
  end
end