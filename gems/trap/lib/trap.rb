#Traps library
#Author: Iren_Rin
#Terms of use: none
#Requirements: AASM, Ticker. Messager is supported
#Version 0.0.1
#How to install
#- install AASM
#- install Ticker
#- install Messager (not required, but supported)
#- install the script as gem with Sides script loader OR add batch.rb to a project scripts
#How to use
#- read through Trap::Defaults, change if needed
####Thorns
#Thors is collection of events. Trap::Thorns will switch local switches
#of each of these events from A to D by timing.
#When character stands on a event from the collection
#and it switches to A local switch, the character will
#be damaged.
#You can create thorns with following
#trap = Trap::Thorns.build 'thorns1' do #.build method must be called with unique selector
#  map 1             #map id, required
#  events 1, 2, 3, 4 #also events can be setted with array or range
#  damage 20         #damage
#end
#trap.run
#Then you can receive the trap object with the unique selector
#Trap['thorns1'].stop
#Trap['thorns1'].run
####Fireboll
#Fireboll is missile that fly by route and deal damage if touches character.
#Then fieboll expodes with animation.
#Fireboll need 3 by 4 sprite with following scheme
#down  | down  | down
#left  | left  | left
#right | right | right
#up    | up    | up
#Frames of one direaction whill be switching during fly, so you can animate the missile
#You can create fireboll with following
#fireboll = Trap::Fireboll.build 'fireboll1' do
#  map 1
#  speed 10 #speed of the missile, smaller number will lead to faster missile
#  damage 200
#  route do
#    start 1, 1 #x, y
#    down  1, 10
#    right 10, 10
#    up    10, 1
#  end
#  sprite do
#    missile 'fireboll' #missile character
#    animation 11 #expoloding animation
#  end
#end
#fireboll.run
#Now you can get the fireboll via Trap[] with selector
####Machinegun
#Machinegun is Trap::Fireboll automated launcher.
#Create it with following code
#trap = Trap::Machinegun.build 'machinegun1' do
#  #accepts all the settings a firebolls accepts pluse interval
#  interval 200 #interval between launches in frames
#  map 1
#  speed 10 #speed of the missile, smaller number will lead to faster missile
#  damage 200
#  route do
#    start 1, 1 #x, y
#    down  1, 10
#    right 10, 10
#    up    10, 1
#  end
#  sprite do
#    missile 'fireboll' #missile character
#    animation 11 #expoloding animation
#  end
#end
#trap.run
#Trap['machinegun1'].stop
#Trap['machinegun1'].run

module Trap
  VERSION = '0.2'

  module Defaults
    module Thorns
      def default_options
        {
          damage: '0.25 * b.mhp', #damage of thorn's hit
          speed: 30,   #whole cycle in frames
          hazard_timeout: 21, #after switching to A how many frames the thor will be cutting?
          se: { 'A' => 'Sword4'}, #se playing on each local switch
          timing: { #on which frame of the cycle will be enabled every local switch
            0 => 'A', 2 => 'B', 4 => 'C', 19 => 'D', 21 => 'OFF'
          }
        }
      end
    end

    module Field
      def default_options
        {
          damage: '0.33 * b.mhp', #damage of thorn's hit
          speed: 120,   #whole cycle in frames
          hazard_timeout: 21, #after switching to A how many frames the thor will be cutting?
          se: { 'A' => 'Sword4'}, #se playing on each local switch
          timing: { #on which frame of the cycle will be enabled every local switch
            0 => 'A', 2 => 'B', 19 => 'C', 21 => 'OFF'
          },
          safe_spots: {
            safe_events: []
          }
        }
      end
    end

    module Fireboll
      def default_options
        {
          speed: 16,  #speed of missile (smaller number for faster missile fly)
          damage: '0.5 * b.mhp', #damage of a missile
          bgs: 'fire'
        }
      end
    end

    module Saw
      def default_options
        {
          speed: 16,  #speed of missile (smaller number for faster missile fly)
          damage: '0.5 * b.mhp', #damage of a missile
          sprite: {
            missile: 'saw',
            animation: nil,
            z: 99,
            speed: 0.64
          }
        }
      end
    end

    module Touch
      def default_options
        {
          speed: 16,
          sprite: {
            missile: 'blue_sphaere',
            animation: 131
          }
        }
      end
    end

    module Machinegun
      def default_options
        { interval: 200 } #interval in frames between every missile launch
      end
    end

    module Touchgun
      def default_options
        { interval: 200 } #interval in frames between every missile launch
      end
    end

    module Cells
      def default_options
        {
          hazard_delay: 20,  #interval in frames between cell damage dealing
          damage: '0.5 * b.mhp'
         }
      end
    end

    module FirebollSprite
      def default_options
        {
          speed: 0.08, #speed of updating missile sprite
          missile: 'fireboll', #path to missile sprite
          animation: 111 #die animation id
        }
      end
    end
  end

  class << self
    def [](id)
      id.is_a?(Regexp) ? matched(id) : traps[id]
    end

    def []=(id, trap)
      traps[id] = trap
    end

    def main(id)
      self[id].select(&:main?)
    end

    def all
      traps.values
    end

    def matched(pattern)
      traps.each_with_object([]) do |(key, trap), result|
        result << trap if key.to_s =~ pattern
      end
    end

    def delete(id)
      traps.delete id
    end

    def to_save
      Hash[traps.map { |k, v| [k, v.to_save] }]
    end

    def reset(hash)
      @traps = hash if hash.is_a? Hash
    end

    def flush
      @traps = nil
    end

    def for_map(map_id)
      all_for_map(map_id).select(&:main?)
    end

    def all_for_map(map_id)
      all.select { |t| t.map_id == map_id }
    end

    private

    def traps
      @traps ||= {}
    end
  end
end

require 'trap/options'
require 'trap/route'
require 'trap/patch'
require 'trap/dj'
require 'trap/base'
require 'trap/thorns_base'
require 'trap/thorns'
require 'trap/field'
require 'trap/machinegun'
require 'trap/fireboll'
require 'trap/touch'
require 'trap/saw'
require 'trap/touchgun'
require 'trap/cells'
require 'trap/block'
