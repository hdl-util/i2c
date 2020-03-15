module clock_tb();



localparam INPUT_CLK_RATE = $unsigned(400000);
localparam TARGET_SCL_RATE = $unsigned(100000);
localparam SLOWEST_DEVICE_RATE = $unsigned(10000);

logic scl_in = 1'bz; // Initially, no other master present

logic inoutmode = 1'b0;
wire scl;
assign scl = inoutmode ? scl_in : 1'bz;

logic clk_in = 1'b0;
always #2 clk_in = ~clk_in;
logic bus_clear;

localparam MODE = $unsigned(TARGET_SCL_RATE) <= 100000 ? 0 : $unsigned(TARGET_SCL_RATE) <= 400000 ? 1 : $unsigned(TARGET_SCL_RATE) <= 1000000 ? 2 : -1;
localparam COUNTER_WIDTH = $clog2($unsigned(INPUT_CLK_RATE) / $unsigned(TARGET_SCL_RATE));
localparam COUNTER_END = COUNTER_WIDTH'($unsigned(INPUT_CLK_RATE) / $unsigned(TARGET_SCL_RATE) - 1);
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_HIGH = COUNTER_WIDTH'(MODE == 0 ? ( (COUNTER_WIDTH + 1)'(COUNTER_END) + 1) / 2 : (( (COUNTER_WIDTH + 2)'(COUNTER_END) + 1) * 2) / 3);
// Conforms to Table 10 tr (rise time) for SCL clock.
localparam COUNTER_RISE = COUNTER_WIDTH'($ceil($unsigned(INPUT_CLK_RATE) / 1.0E9 * $unsigned(MODE == 0 ? 1000 : MODE == 1 ? 300 : MODE == 2  ? 120 : 0)));

// Bus clear event counter
localparam WAIT_WIDTH = $clog2(2 * $unsigned(INPUT_CLK_RATE) / $unsigned(SLOWEST_DEVICE_RATE));
localparam WAIT_END = WAIT_WIDTH'(2 * $unsigned(INPUT_CLK_RATE) / $unsigned(SLOWEST_DEVICE_RATE) - 1);
logic [COUNTER_WIDTH-1:0] counter;
clock #(.COUNTER_WIDTH(COUNTER_WIDTH), .COUNTER_END(COUNTER_END), .COUNTER_HIGH(COUNTER_HIGH), .COUNTER_RISE(1), .MULTI_MASTER(1), .CLOCK_STRETCHING(1), .WAIT_WIDTH(WAIT_WIDTH), .WAIT_END(WAIT_END)) clock(.scl(scl), .clk_in(clk_in), .release_line(1'b0), .bus_clear(bus_clear), .counter(counter));

logic [COUNTER_WIDTH-1:0] last_counter = COUNTER_HIGH;
always @(posedge clk_in)
begin
  last_counter <= counter;
  if (last_counter < COUNTER_HIGH)
    assert (scl === 1'b0) else $fatal(1, "High when counter hasn't risen: %b", scl);
  else if (!inoutmode)
  begin
    assert (scl === 1'bz) else $fatal(1, "Low when counter has risen: %b", scl);
  end
end

initial
begin
  assert(COUNTER_WIDTH == 2) else $fatal(1, "Counter width should be 3 but was %d", COUNTER_WIDTH); 
  assert(COUNTER_END == 3) else $fatal(1, "Counter end should be 4 but was %d", COUNTER_END);
  #100ns;
  $display("Testing bus clear");
  wait (!scl && !clk_in && counter == COUNTER_HIGH);
  scl_in <= 1'b0;
  inoutmode <= 1'b1;
  #310ps;
  assert (!clock.bus_clear) else $fatal(1, "Bus clear asserted early");
  #50ps;
  assert (clock.bus_clear) else $fatal(1, "Bus clear not asserted when SCL line stuck");
  scl_in <= 1'bz;
  #6ps;
  assert (!clock.bus_clear) else $fatal(1, "Bus clear asserted after SCL line released");
  inoutmode <= 1'b0;

  #1ns;
  $display("Testing reset");
  wait (scl === 1'bz && !clk_in && counter == 0);
  scl_in <= 1'b0;
  inoutmode <= 1'b1;
  wait (clk_in);
  wait (!clk_in);
  assert (counter == 1) else $fatal(1, "Counter did not reset after early drive to low");
  scl_in <= 1'bz;
  inoutmode <= 1'b0;

  $finish;
end

endmodule
