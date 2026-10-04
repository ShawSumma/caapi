local world, script_path = ...
local player = world.player

package.path = script_path:gsub("[^/]*$", "") .. "?.lua;" .. package.path

function world:wait(seconds)
  self:frames(math.floor(seconds / self:timestep() + 0.5))
end

function player:press(seconds, ...)
  self:hold(...)
  world:wait(seconds)
  self:release(...)
end

function player:turn(yaw_degrees, pitch_degrees, seconds)
  local saved_yaw, saved_pitch = self:turn_rate()
  self:turn_rate(yaw_degrees / seconds, pitch_degrees / seconds)
  world:wait(seconds)
  self:turn_rate(saved_yaw, saved_pitch)
end

assert(loadfile(script_path))(world)
