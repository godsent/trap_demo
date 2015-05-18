module Trap::Concerns::Stateable
  def add_state(id)
    actor.add_state id
  end
end