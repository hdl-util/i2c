action = "simulation"
sim_tool = "modelsim"
sim_top = "master_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c master_tb"

modules = {
  "local" : [ "../../test/" ],
}
