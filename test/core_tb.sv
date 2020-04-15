module core_tb #(
    parameter INPUT_CLK_RATE,
    parameter TARGET_SCL_RATE = 100000,
    parameter SLOWEST_DEVICE_RATE = 10000
) ();
logic sda_in = 1'bz;
logic inoutmode = 1'b0;
wire scl;
wire sda;
assign scl = 1'bz;
assign sda = inoutmode ? sda_in : 1'bz;


logic clk_in = 1'b0;
always #2 clk_in = ~clk_in;
logic bus_clear;
logic mode = 1'b0;
logic transfer_start = 1'b0;
logic transfer_continues = 1'b0;
logic transfer_ready;
logic interrupt;
logic transaction_complete;
logic nack;
logic start_err;
logic arbitration_err;
logic [7:0] data_tx = 8'd0;
logic [7:0] data_rx;

i2c_core #(
    .INPUT_CLK_RATE(INPUT_CLK_RATE),
    .TARGET_SCL_RATE(TARGET_SCL_RATE),
    .CLOCK_STRETCHING(0),
    .MULTI_MASTER(0),
    .SLOWEST_DEVICE_RATE(SLOWEST_DEVICE_RATE),
    .FORCE_PUSH_PULL(0)
) master (
    .scl(scl),
    .clk_in(clk_in),
    .bus_clear(bus_clear),
    .sda(sda),
    .mode(mode),
    .transfer_start(transfer_start),
    .transfer_continues(transfer_continues),
    .transfer_ready(transfer_ready),
    .interrupt(interrupt),
    .transaction_complete(transaction_complete),
    .nack(nack),
    .start_err(start_err),
    .arbitration_err(arbitration_err),
    .data_tx(data_tx),
    .data_rx(data_rx)
);

integer i, j;

logic [7:0] TEST1 = 8'b10110100;
logic [63:0] TEST2 = 64'hFEEDFACECAFEBEEF;
logic [63:0] TEST3 = 64'hFAC3B00CBAAAAAAD;

initial
begin
    $display("Parameters: COUNTER_END %d, COUNTER_HIGH %d, COUNTER_RECEIVE %d, COUNTER_TRANSMIT %d", master.COUNTER_END, master.COUNTER_HIGH, master.COUNTER_RECEIVE, master.COUNTER_TRANSMIT);
    wait (!clk_in && transfer_ready);
    $display("Beginning transmission ending with NACK");
    mode <= 1'b0;
    transfer_start <= 1'b1;
    transfer_continues <= 1'b0;
    data_tx <= TEST1;
    wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
    assert (master.busy) else $fatal(1, "Master should be busy");
    for (i = 0; i < 8; i++)
    begin
        wait (master.counter == master.COUNTER_TRANSMIT + 1 && !clk_in);
        assert (master.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.transaction_progress, i + 2);
        assert (master.busy) else $fatal(1, "Master should be busy in %d", 3'(i));
        assert (master.sda_internal === TEST1[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", i, master.transaction_progress, TEST1[7 - i], master.sda_internal);
        wait (master.counter == master.COUNTER_TRANSMIT && !clk_in);
    end
    wait (interrupt && !clk_in);
    assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
    assert (nack) else $fatal(1, "Slave sent NACK, master should've noted it");
    transfer_start <= 1'b0;
    transfer_continues <= 1'b0;

    wait (!clk_in && transfer_ready);
    $display("Beginning transmission ending with ACK");
    mode <= 1'b0;
    transfer_start <= 1'b1;
    transfer_continues <= 1'b0;
    data_tx <= TEST1;
    wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
    assert (master.busy) else $fatal(1, "Master should be busy");
    for (i = 0; i < 8; i++)
    begin
        wait (master.counter == master.COUNTER_TRANSMIT + 1 && !clk_in);
        assert (master.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.transaction_progress, i + 2);
        assert (master.busy) else $fatal(1, "Master should be busy in %d", 3'(i));
        assert (master.sda_internal === TEST1[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", i, master.transaction_progress, TEST1[7 - i], master.sda_internal);
        wait (master.counter == master.COUNTER_TRANSMIT && !clk_in);
    end
    inoutmode <= 1'b1;
    sda_in <= 1'b0;
    wait (interrupt && !clk_in);
    inoutmode <= 1'b0;
    assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
    assert (!nack) else $fatal(1, "Slave sent ACK, master should've noted it");


    $display("Beginning repeated start reception ending with NACK");
    mode <= 1'b1;
    transfer_start <= 1'b1;
    transfer_continues <= 1'b0;
    data_tx <= 8'd0;
    inoutmode <= 1'b1;
    wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
    wait (master.counter == (master.COUNTER_RECEIVE) % (master.COUNTER_END + 1) && !clk_in);
    wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
    assert (master.busy) else $fatal(1, "Master should be busy");
    for (i = 0; i < 8; i++)
    begin
        wait (master.counter == master.COUNTER_TRANSMIT && !clk_in);
        wait (clk_in);
        sda_in <= TEST1[7 - i] ? 1'bz : 1'b0;
        wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
        assert (master.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.transaction_progress, i + 2);
        assert (master.latched_data[7 - i] == TEST1[7 - i]) else $fatal(1, "Loop %d RX progress %d expected %b but was %b", i, master.transaction_progress, TEST1[7 - i], master.latched_data[7 - i]);
    end
    inoutmode <= 1'b0;
    wait (master.counter == master.COUNTER_TRANSMIT + 1 && !clk_in);
    wait (interrupt && !clk_in);
    assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
    assert (nack) else $fatal(1, "Master should've sent NACK");
    assert (data_rx == TEST1) else $fatal(1, "Expected %b, was %b", TEST1, data_rx);
    transfer_start <= 1'b0;
    transfer_continues <= 1'b0;
    
    
    
    wait (transfer_ready && !clk_in);
    $display("\nBeginning bulk transmission");
    mode <= 1'b0;
    transfer_start <= 1'b1;
    transfer_continues <= 1'b1;
    data_tx <= TEST2[7:0];
    for (j = 0; j < 8; j++)
    begin
        wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) + (j == 0 ? 0 : 1) && !clk_in);
        $display("Byte %d (%h)", j, TEST2[7:0]);
        assert (master.busy) else $fatal(1, "Master should be busy");
        wait (master.counter == master.COUNTER_TRANSMIT && !clk_in);
        assert (master.latched_data == TEST2[7:0]) else $fatal(1, "Master didn't latch current byte expected %h but was %h", TEST2[7:0], master.latched_data);
        inoutmode <= 1'b0;
        for (i = 0; i < 8; i++)
        begin
            wait (master.counter == master.COUNTER_TRANSMIT + 1 && !clk_in);
            assert (master.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.transaction_progress, i + 2);
            assert (master.busy) else $fatal(1, "Master should be busy");
            assert (master.sda_internal == TEST2[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", 3'(i), master.transaction_progress, TEST2[7 - i], master.sda_internal);
            wait (master.counter == master.COUNTER_TRANSMIT && !clk_in);
        end
        inoutmode <= 1'b1;
        sda_in <= j == 7 ? 1'bz : 1'b0; // NACK or ACK
        wait (interrupt && !clk_in);
        assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
        assert (j == 7 ? nack : !nack) else $fatal(1, "Unexpected ACK/NACK for %d", j);
        transfer_start <= 1'b0;
        transfer_continues <= 1'(j + 1 != 7);
        if (j != 7)
        begin
            TEST2 <= {8'd0, TEST2[63:8]};
            data_tx <= TEST2[15:8];
        end
    end

    wait (transfer_ready && !clk_in);
    $display("\nBeginning bulk reception");
    mode <= 1'b1;
    transfer_start <= 1'b1;
    transfer_continues <= 1'b1;
    for (j = 0; j < 8; j++)
    begin
        wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) + (j == 0 ? 0 : 1) && !clk_in);
        $display("Byte %d (%h)", j, TEST3[7:0]);
        assert (master.busy) else $fatal(1, "Master should be busy");
        inoutmode <= 1'b1;
        for (i = 0; i < 8; i++)
        begin
            wait (master.counter == master.COUNTER_TRANSMIT && clk_in);
            sda_in <= TEST3[7 - i] ? 1'bz : 1'b0;
            wait (master.counter == (master.COUNTER_RECEIVE + 1) % (master.COUNTER_END + 1) && !clk_in);
            assert (master.latched_data[7 - i] == TEST3[7 - i]) else $fatal(1, "Loop %d RX progress %d expected %b but was %b", i, master.transaction_progress, TEST3[7 - i], master.latched_data[7 - i]);
        end
        inoutmode <= 1'b0;
        wait (master.counter == master.COUNTER_TRANSMIT + 1 && !clk_in);
        wait (interrupt && !clk_in);
        assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
        assert (j == 7 ? nack : !nack) else $fatal(1, "Master sent unexpected ACK/NACK for %d", j);
        assert (data_rx == TEST3[7:0]) else $fatal(1, "Data did not reach data_rx");
        transfer_start <= 1'b0;
        transfer_continues <= 1'(j + 1 != 7);
        if (j != 7)
            TEST3 <= {8'd0, TEST3[63:8]};
    end

    wait(transfer_ready && !clk_in);

    $finish;
end

endmodule
