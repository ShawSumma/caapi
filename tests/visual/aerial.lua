return function(world)
  world:mode("fly")
  world:press(1.5, "up")
  world:look(0, 60)
  world:step()
end
