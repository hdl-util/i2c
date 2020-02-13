module clock #(
    parameter INPUT_CLK_RATE,
    parameter SLOWEST_MASTER_RATE,
    parameter TARGET_SCL_RATE,
    parameter PUSH_PULL = 0,
)(
    inout scl = 1'bZ,
    input clk_in,
    output bus_clear = 1'b0,
);

localparam COUNTER_WIDTH = $clog2(INPUT_CLK_RATE / TARGET_SCL_RATE);
localparam COUNTER_END = COUNTER_WIDTH'(INPUT_CLK_RATE / TARGET_SCL_RATE);
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_RISE = MODE == 0 ? COUNTER_END / 2 : (COUNER_END * 2) / 3;
logic [COUNTER_WIDTH-1:0] counter = COUNTER_WIDTH'(0);

logic scl_held_low;
assign scl_held_low = !scl && counter > COUNTER_RISE && !PUSH_PULL;

logic last_scl = 1'b0;
always @(posedge clk_in) // Last observed scl value, assuming scl noise was smoothed with a Schmitt trigger
    last_scl <= scl;

localparam MASTER_WAIT_WIDTH = $clog2(INPUT_CLK_RATE / SLOWEST_MASTER_RATE * 2);
localparam MASTER_WAIT_END = INPUT_CLK_RATE / SLOWEST_MASTER_RATE * 2;
logic [MASTER_WAIT_WIDTH-1:0] master_wait = MASTER_WAIT_WIDTH'(0);

assign bus_clear = master_wait == MASTER_WAIT_END;

always @(posedge clk_in)
begin
    if (counter < COUNTER_RISE) // LOW period
        scl <= 1'b0;
    else // HIGH period
        scl <= PUSH_PULL ? 1'b1 : 1'bZ;
end

always @(posedge clk_in)
    if (counter > COUNTER_RISE)
    begin
        // See Figure 7, counter reset. SCL becomes LOW prematurely.
        if (scl_held_low && last_scl && MULTI_MASTER) 
        begin
            counter <= COUNTER_WIDTH'(0);
            master_wait <= MASTER_WAIT_WIDTH'(0);
        end
        // See Figure 7, wait state. SCL is being held LOW by another device.
        else if (scl_held_low && !last_scl)
        begin
            counter <= counter;
            if (master_wait < MASTER_WAIT_END) // Saturates to indicate bus clear condition
                master_wait <= master_wait + 1'd1;
        end
        else // See Figure 7, counting HIGH period
        begin
            counter <= counter == COUNTER_END ? COUNTER_WIDTH'(0) : counter + 1'd1;
            master_wait <= MASTER_WAIT_WIDTH'(0);
        end
    end
    else // LOW period counting
    begin
        counter <= counter + 1'd1;
        master_wait <= MASTER_WAIT_WIDTH'(0);
    end
end

endmodule