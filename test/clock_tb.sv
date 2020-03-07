module clock_tb();



localparam INPUT_CLK_RATE = $unsigned(500000);
localparam TARGET_SCL_RATE = $unsigned(100000);
localparam SLOWEST_MASTER_RATE = $unsigned(10000);

logic scl_in = 1'bz; // Initially, no other master present

logic inoutmode = 1'b0;
wire scl;
assign scl = inoutmode ? scl_in : 1'bz;

logic clk_in = 1'b0;
always #2 clk_in = ~clk_in;
logic bus_clear;

localparam COUNTER_WIDTH = $clog2(INPUT_CLK_RATE / TARGET_SCL_RATE);
localparam COUNTER_END = COUNTER_WIDTH'(INPUT_CLK_RATE / TARGET_SCL_RATE - 1);
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_HIGH = COUNTER_WIDTH'(COUNTER_END / 2);
localparam WAIT_WIDTH = $clog2(2 * INPUT_CLK_RATE / SLOWEST_MASTER_RATE);
localparam WAIT_END = WAIT_WIDTH'(2 * INPUT_CLK_RATE / SLOWEST_MASTER_RATE - 1);
logic [$clog2(COUNTER_END)-1:0] counter;
clock #(.COUNTER_WIDTH(COUNTER_WIDTH), .COUNTER_END(COUNTER_END), .COUNTER_HIGH(COUNTER_HIGH), .COUNTER_RISE(0), .MULTI_MASTER(1), .CLOCK_STRETCHING(1), .WAIT_WIDTH(WAIT_WIDTH), .WAIT_END(WAIT_END)) clock(.scl(scl), .clk_in(clk_in), .release_line(1'b0), .bus_clear(bus_clear), .counter(counter));

always @(posedge clk_in)
begin
  if (clock.counter < COUNTER_HIGH)
    assert (scl === 1'b0) else $fatal(1, "High when counter hasn't risen: %b", scl);
  else if (!inoutmode)
  begin
    assert (scl === 1'bz) else $fatal(1, "Low when counter has risen: %b", scl);
  end
end

initial
begin
  assert(COUNTER_WIDTH == 3) else $fatal(1, "Counter width should be 3 but was %d", COUNTER_WIDTH); 
  assert(COUNTER_END == 4) else $fatal(1, "Counter end should be 4 but was %d", COUNTER_END);
  #100ns;
  $display("Testing bus clear");
  wait (scl == 1'b0 && clk_in == 1'b0);
  scl_in <= 1'b0;
  inoutmode <= 1'b1;
  #400ps;
  assert (!clock.bus_clear) else $fatal(1, "Bus clear asserted early");
  #12ps;
  assert (clock.bus_clear) else $fatal(1, "Bus clear not asserted when SCL line stuck");
  scl_in <= 1'bz;
  inoutmode <= 1'b1;
  #6ps;
  assert (!clock.bus_clear) else $fatal(1, "Bus clear asserted after SCL line released");

  $display("Testing reset");
  #10ns;
  wait (scl === 1'bz && clk_in == 1'b0);
  scl_in <= 1'b0;
  inoutmode <= 1'b1;
  #4ps;
  assert (clock.counter == 0) else $fatal(1, "Counter did not reset after early drive to low");
  scl_in <= 1'bz;
  inoutmode <= 1'b0;

  $finish;
end

endmodule
