module master_tb();

initial begin
    #1us $finish;
end

localparam INPUT_CLK_RATE = 500000;
localparam TARGET_SCL_RATE = 100000;
localparam SLOWEST_MASTER_RATE = 10000;

logic scl_in = 1'bz;
logic sda_in = 1'bz;

logic inoutmode = 1'b0;
wire scl;
wire sda;
assign scl = inoutmode ? scl_in : 1'bz;
assign sda = inoutmode ? sda_in : 1'bz;


logic clk_in = 1'b0;
always #2 clk_in = ~clk_in;
logic bus_clear;
logic mode = 1'b0;
logic transfer_start = 1'b0;
logic transfer_continue = 1'b0;
logic transfer_ready;
logic interrupt;
logic transaction_complete;
logic ack;
logic start_err;
logic arbitration_err;
logic [7:0] data_tx = 8'd0;
logic [7:0] data_rx;

master #(
    .INPUT_CLK_RATE(INPUT_CLK_RATE),
    .TARGET_SCL_RATE(TARGET_SCL_RATE),
    .CLOCK_STRETCHING(0),
    .MULTI_MASTER(0),
    .SLOWEST_MASTER_RATE(SLOWEST_MASTER_RATE),
    .FORCE_PUSH_PULL(0)
) master (
    .scl(scl),
    .clk_in(clk_in),
    .bus_clear(bus_clear),
    .sda(sda),
    .mode(mode),
    .transfer_start(transfer_start),
    .transfer_continue(transfer_continue),
    .transfer_ready(transfer_ready),
    .interrupt(interrupt),
    .transaction_complete(transaction_complete),
    .ack(ack),
    .start_err(start_err),
    .arbitration_err(arbitration_err),
    .data_tx(data_tx),
    .data_rx(data_rx)
);

integer i;

logic [7:0] EXPECTED = 8'b10110100;

initial
begin
    wait (transfer_ready);
    mode <= 1'b0;
    transfer_start <= 1'b1;
    transfer_continue <= 1'b0;
    data_tx <= EXPECTED;
    wait (master.transaction_progress == 4'd2);
    for (i = 0; i < 8; i++)
    begin
        wait (master.counter == master.COUNTER_RECEIVE + 1);
        assert (master.sda_internal === EXPECTED[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", i, master.transaction_progress, EXPECTED[7 - i], master.sda_internal);
        wait (master.counter > master.COUNTER_RECEIVE + 1);
    end
end

endmodule

