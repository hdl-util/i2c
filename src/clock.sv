module clock #(
    parameter int COUNTER_WIDTH,
    parameter bit [COUNTER_WIDTH-1:0] COUNTER_END,
    parameter bit [COUNTER_WIDTH-1:0] COUNTER_HIGH,
    parameter bit [COUNTER_WIDTH-1:0] COUNTER_RISE,
    parameter bit MULTI_MASTER,
    parameter bit CLOCK_STRETCHING,
    parameter int WAIT_WIDTH,
    parameter bit [WAIT_WIDTH-1:0] WAIT_END,
    parameter bit PUSH_PULL = 0
)(
    inout wire scl,
    input logic clk_in,
    input logic release_line,
    output logic bus_clear,
    output logic [COUNTER_WIDTH-1:0] counter = COUNTER_HIGH
);

logic scl_internal = 1'b1;
assign scl = scl_internal ? (PUSH_PULL ? 1'b1 : 1'bz) : 1'b0;

logic last_scl = 1'b1;
always @(posedge clk_in)
`ifdef MODEL_TECH
    last_scl <= scl === 1'bz;
`else
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
    // See Figure 7, counter reset. SCL becomes LOW prematurely.
    // Detects a falling edge during a counter-sized interval
    else if (last_scl && !scl && (counter == COUNTER_WIDTH'(0) || counter >= COUNTER_HIGH + COUNTER_RISE) && MULTI_MASTER)
    begin
        counter <= COUNTER_WIDTH'(1);
        wait_counter <= WAIT_WIDTH'(0);
        scl_internal <= 1'b0;
    end
    // See Figure 7, wait state. SCL is being held LOW by another device after SCL should have risen.
    else if (!scl && (counter == COUNTER_HIGH + COUNTER_RISE) && !PUSH_PULL && (CLOCK_STRETCHING || MULTI_MASTER))
    begin
        counter <= COUNTER_HIGH + COUNTER_RISE;
        if (wait_counter < WAIT_END) // Saturates to indicate bus clear condition
            wait_counter <= wait_counter + 1'd1;
        scl_internal <= 1'b1;
    end
    else if (counter >= COUNTER_HIGH)
    begin
        // See Figure 7, counting HIGH period
        counter <= counter == COUNTER_END ? COUNTER_WIDTH'(0) : counter + 1'd1;
        wait_counter <= WAIT_WIDTH'(0);
        scl_internal <= 1'b1;
    end
    else // LOW period counting
    begin
        counter <= counter + 1'd1;
        wait_counter <= WAIT_WIDTH'(0);
        scl_internal <= 1'b0;
    end
end

endmodule
