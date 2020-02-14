action = "simulation"
sim_tool = "modelsim"
sim_top = "clock_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c clock_tb"

modules = {
  "local" : [ "../../test/" ],
}
