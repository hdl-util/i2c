module clock #(
    parameter COUNTER_END,
    parameter COUNTER_RISE,
    parameter MULTI_MASTER,
    parameter CLOCK_STRETCHING,
    parameter WAIT_END,
    parameter PUSH_PULL = 0
)(
    inout logic scl,
    input logic clk_in,
    output logic bus_clear,
    output logic [$clog2(COUNTER_END)-1:0] counter = COUNTER_RISE + 1
);
localparam COUNTER_WIDTH = $clog2(COUNTER_END);
localparam WAIT_WIDTH = $clog2(WAIT_END);

logic scl_internal;
assign scl_internal = counter >= COUNTER_RISE;
assign scl = scl_internal ? (PUSH_PULL ? 1'b1 : 1'bz) : 1'b0;

logic scl_held_low;
assign scl_held_low = !scl && counter > COUNTER_RISE && !PUSH_PULL;

logic last_scl = 1'b1;
always @(posedge clk_in) // Last observed scl value, assuming scl noise was smoothed with a Schmitt trigger
    last_scl <= scl;

logic [WAIT_WIDTH-1:0] wait_counter = WAIT_WIDTH'(0);

assign bus_clear = wait_counter == WAIT_END;

always @(posedge clk_in)
begin
    if (counter > COUNTER_RISE)
    begin
        // See Figure 7, counter reset. SCL becomes LOW prematurely.
        if (scl_held_low && last_scl && MULTI_MASTER) 
        begin
            counter <= COUNTER_WIDTH'(0);
            wait_counter <= WAIT_WIDTH'(0);
        end
        // See Figure 7, wait state. SCL is being held LOW by another device.
        else if (scl_held_low && !last_scl && (CLOCK_STRETCHING || MULTI_MASTER))
        begin
            counter <= counter;
            if (wait_counter < WAIT_END) // Saturates to indicate bus clear condition
                wait_counter <= wait_counter + 1'd1;
        end
        else // See Figure 7, counting HIGH period
        begin
            counter <= counter == COUNTER_END ? COUNTER_WIDTH'(0) : counter + 1'd1;
            wait_counter <= WAIT_WIDTH'(0);
        end
    end
    else // LOW period counting
    begin
        counter <= counter + 1'd1;
        wait_counter <= WAIT_WIDTH'(0);
    end
end

endmodule