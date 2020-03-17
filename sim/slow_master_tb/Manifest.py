action = "simulation"
sim_tool = "modelsim"
sim_top = "slow_master_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c slow_master_tb"

modules = {
  "local" : [ "../../test/" ],
}
