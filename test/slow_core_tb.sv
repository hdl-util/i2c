module slow_core_tb();

localparam INPUT_CLK_RATE = 400000;
core_tb #(.INPUT_CLK_RATE(INPUT_CLK_RATE)) core_tb();

endmodule
