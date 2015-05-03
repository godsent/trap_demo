module Trap::Concerns::HPable
  def hp
    actor.hp
  end

  def hp=(val)
    actor.hp = val
  end

  def mhp
    actor.mhp
  end
end