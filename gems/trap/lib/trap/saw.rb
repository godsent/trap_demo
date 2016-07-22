class Trap::Saw < Trap::Fireboll
  include Trap::Defaults::Saw

  def init_variables
    super
    @damage_dealed_to = {}
  end

  private

  def deal_damage
    refresh_dealed_to
    super
  end

  def refresh_dealed_to
    @damage_dealed_to.select! do |(d_x, d_y), _|
      xes.include?(d_x) && yes.include?(d_y)
    end
  end

  def chars_to_hit
    super.reject { |char| dealed_to? char }
  end

  def dealed_to?(char)
    @damage_dealed_to.any? { |_, ids| ids.include? char.actor.id }
  end

  def stop_on_damage?
    false
  end

  def apply_damage(char)
    super
    track_dealed_damage char
  end

  def track_dealed_damage(char)
    @damage_dealed_to[[char.x, char.y]] ||= []
    @damage_dealed_to[[char.x, char.y]] << char.actor.id
  end
end
