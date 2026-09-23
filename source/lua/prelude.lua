-- Loaded before every script. Conveniences over the engine primitives;
-- see CLAUDE.md for the full script API.

-- Modules next to the running script can be required by name.
package.path = SCRIPT_DIR .. "/?.lua;" .. package.path

local step_seconds = 0.016
local yaw_rate, pitch_rate = 0, 0

-- timestep() -> seconds; timestep(seconds) sets the frame length wait uses.
function timestep(seconds)
  if seconds then
    step_seconds = seconds
  end
  return step_seconds
end

-- Continuous look rotation applied by wait, in degrees per second.
function turn_rate(yaw_deg, pitch_deg)
  yaw_rate = math.rad(yaw_deg or 0)
  pitch_rate = math.rad(pitch_deg or 0)
end

-- Runs whole frames covering `seconds`, rounded to the nearest frame.
function wait(seconds)
  local n = math.floor(seconds / step_seconds + 0.5)
  frames(n, step_seconds, yaw_rate * step_seconds, pitch_rate * step_seconds)
end

-- Turns by yaw/pitch degrees spread evenly over `seconds`.
function turn(yaw_deg, pitch_deg, seconds)
  local y, p = yaw_rate, pitch_rate
  yaw_rate = math.rad(yaw_deg) / seconds
  pitch_rate = math.rad(pitch_deg) / seconds
  wait(seconds)
  yaw_rate, pitch_rate = y, p
end

-- Holds keys for `seconds`, then releases them.
function press(seconds, ...)
  hold(...)
  wait(seconds)
  release(...)
end
