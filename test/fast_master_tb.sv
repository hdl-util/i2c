module fast_master_tb();

localparam INPUT_CLK_RATE = 48000000;
master_tb #(.INPUT_CLK_RATE(INPUT_CLK_RATE)) master_tb();

endmodule