local WIDTH = 100

return function(site)
  site:paint("granite",{ across = { -WIDTH, WIDTH }, height = { 0, 1 } })
end
