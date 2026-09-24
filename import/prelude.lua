package.path = SCRIPT_DIR .. "/?.lua;" .. package.path

local step_seconds = 0.016
local yaw_rate = 0
local pitch_rate = 0

function timestep(seconds)
  if seconds then
    step_seconds = seconds
  end
  return step_seconds
end

function turn_rate(yaw_deg, pitch_deg)
  yaw_rate = math.rad(yaw_deg or 0)
  pitch_rate = math.rad(pitch_deg or 0)
end

function wait(seconds)
  local n = math.floor(seconds / step_seconds + 0.5)
  frames(n, step_seconds, yaw_rate * step_seconds, pitch_rate * step_seconds)
end

function turn(yaw_deg, pitch_deg, seconds)
  local saved_yaw = yaw_rate
  local saved_pitch = pitch_rate
  yaw_rate = math.rad(yaw_deg) / seconds
  pitch_rate = math.rad(pitch_deg) / seconds
  wait(seconds)
  yaw_rate = saved_yaw
  pitch_rate = saved_pitch
end

function press(seconds, ...)
  hold(...)
  wait(seconds)
  release(...)
end
