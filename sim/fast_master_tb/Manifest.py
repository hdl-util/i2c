action = "simulation"
sim_tool = "modelsim"
sim_top = "fast_master_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c fast_master_tb"

modules = {
  "local" : [ "../../test/" ],
}
