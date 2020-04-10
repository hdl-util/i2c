module fast_core_tb();

localparam INPUT_CLK_RATE = 48000000;
core_tb #(.INPUT_CLK_RATE(INPUT_CLK_RATE)) core_tb();

endmodule
