action = "simulation"
sim_tool = "modelsim"
sim_top = "fast_core_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c fast_core_tb"

modules = {
  "local" : [ "../../test/" ],
}
