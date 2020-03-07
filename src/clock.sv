module clock #(
    parameter COUNTER_WIDTH,
    parameter COUNTER_END,
    parameter COUNTER_HIGH,
    parameter COUNTER_RISE,
    parameter MULTI_MASTER,
    parameter CLOCK_STRETCHING,
    parameter WAIT_WIDTH,
    parameter WAIT_END,
    parameter PUSH_PULL = 0
)(
    inout logic scl,
    input logic clk_in,
    input logic release_line,
    output logic bus_clear,
    output logic [COUNTER_WIDTH-1:0] counter = COUNTER_HIGH
);

logic scl_internal = 1'b1;
assign scl = scl_internal ? (PUSH_PULL ? 1'b1 : 1'bz) : 1'b0;

logic scl_held_low;
assign scl_held_low = !scl && counter > COUNTER_HIGH + COUNTER_RISE && !PUSH_PULL;

logic last_scl = 1'b1;
`ifdef MODEL_TECH
always @(posedge clk_in)
    last_scl <= scl === 1'bz;
`else
always @(posedge clk_in) // Last observed scl value, assuming scl noise was smoothed with a Schmitt trigger
    last_scl <= scl;
`endif

logic [WAIT_WIDTH-1:0] wait_counter = WAIT_WIDTH'(0);

assign bus_clear = wait_counter == WAIT_END;

always @(posedge clk_in)
begin
    if (release_line)
    begin
        counter <= counter < COUNTER_HIGH ? COUNTER_HIGH : counter;
        wait_counter <= WAIT_WIDTH'(0);
        scl_internal <= 1'b1;
    end
    else if (counter >= COUNTER_HIGH)
    begin
        // See Figure 7, counter reset. SCL becomes LOW prematurely.
        // TODO: how to detect a falling edge during the allocated rise time?
        if (last_scl && scl_held_low && MULTI_MASTER)
        begin
            counter <= COUNTER_WIDTH'(0);
            wait_counter <= WAIT_WIDTH'(0);
            scl_internal <= 1'b0;
        end
        // See Figure 7, wait state. SCL is being held LOW by another device.
        if (scl_held_low && (CLOCK_STRETCHING || MULTI_MASTER))
        begin
            counter <= counter;
            if (wait_counter < WAIT_END) // Saturates to indicate bus clear condition
                wait_counter <= wait_counter + 1'd1;
            scl_internal <= 1'b1;
        end
        else // See Figure 7, counting HIGH period
        begin
            counter <= counter == COUNTER_END ? COUNTER_WIDTH'(0) : counter + 1'd1;
            wait_counter <= WAIT_WIDTH'(0);
            scl_internal <= 1'b1;
        end
    end
    else // LOW period counting
    begin
        counter <= counter + 1'd1;
        wait_counter <= WAIT_WIDTH'(0);
        scl_internal <= 1'b0;
    end
end

endmodule