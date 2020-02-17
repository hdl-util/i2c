`timescale 1 ps / 1 ps

module clock_tb();

initial begin
  #1us $finish;
end

localparam INPUT_CLK_RATE = 500000;
localparam TARGET_SCL_RATE = 100000;
localparam SLOWEST_MASTER_RATE = 10000;

logic scl_in = 1'bz; // Initially, no other master present

logic inoutmode = 1'b0;
wire scl;
assign scl = inoutmode ? scl_in : 1'bz;

logic clk_in = 1'b0;
always #2 clk_in = ~clk_in;
logic bus_clear;

localparam COUNTER_END = INPUT_CLK_RATE / TARGET_SCL_RATE;
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_RISE = COUNTER_END / 2;
localparam WAIT_END = 2 * INPUT_CLK_RATE / SLOWEST_MASTER_RATE;

clock #(.COUNTER_END(COUNTER_END), .COUNTER_RISE(COUNTER_RISE), .MULTI_MASTER(1), .WAIT_END(WAIT_END)) clock(.scl(scl), .clk_in(clk_in), .bus_clear(bus_clear));

always @(posedge clk_in)
begin
  if (clock.counter < COUNTER_RISE)
    assert (scl === 1'b0) else $fatal(1, "High when counter hasn't risen: %b", scl);
  else if (!inoutmode)
  begin
    assert (scl === 1'bz) else $fatal(1, "Low when counter has risen: %b", scl);
  end
end

initial
begin
  #100ns;
  $display("Testing bus clear");
  wait (scl == 1'b0 && clk_in == 1'b0);
  scl_in <= 1'b0;
  inoutmode <= 1'b1;
  #10ns;
  assert (clock.bus_clear) else $fatal(1, "Bus clear not asserted when SCL line stuck");
  scl_in <= 1'bz;
  inoutmode <= 1'b1;
  wait (clk_in == 1'b0);
  wait (clk_in == 1'b1);
  wait (clk_in == 1'b0);
  assert (!clock.bus_clear) else $fatal(1, "Bus clear asserted after SCL line released");

end

endmodule
