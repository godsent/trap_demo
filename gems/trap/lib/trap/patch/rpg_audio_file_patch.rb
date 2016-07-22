class RPG::AudioFile
  attr_writer :from_trap_dj

  def from_trap_dj?
    !!@from_trap_dj
  end
end