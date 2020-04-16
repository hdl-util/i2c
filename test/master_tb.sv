module master_tb #(
    parameter INPUT_CLK_RATE = 50000000,
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


logic [7:0] address;

i2c_master #(
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
    .address(address),
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

integer i, j, k;
logic [63:0] TEST2_CONST = {56'hFEEDFACECAFEBE, 8'h54};
logic [63:0] TEST2 = TEST2_CONST;

logic [63:0] TEST3_CONST = {56'hFAC3B00CBAAAAA, 8'h21};
logic [63:0] TEST3 = TEST3_CONST;

initial
begin
    wait (transfer_ready && !clk_in);

    for (k = 0; k < 4; k++)
    begin
        $display("Beginning bulk transmission");
        transfer_start <= 1'b1;
        transfer_continues <= 1'b1;
        address <= TEST2_CONST[7:0];
        if (k != 0) wait (master.core.transaction_progress == 4'd11);

        for (j = 0; j < 8; j++)
        begin
            wait (master.core.counter == (master.core.COUNTER_RECEIVE + 1) % (master.core.COUNTER_END + 1) + (j == 0 ? 0 : 1) && !clk_in);
            $display("Byte %d (%h)", j, TEST2[7:0]);
            assert (master.core.busy) else $fatal(1, "Master should be busy");
            wait (master.core.counter == master.core.COUNTER_TRANSMIT && !clk_in);
            assert (master.core.latched_data == TEST2[7:0]) else $fatal(1, "Master didn't latch current byte expected %h but was %h", TEST2[7:0], master.core.latched_data);
            inoutmode <= 1'b0;
            for (i = 0; i < 8; i++)
            begin
                wait (master.core.counter == master.core.COUNTER_TRANSMIT + 1 && !clk_in);
                assert (master.core.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.core.transaction_progress, i + 2);
                assert (master.core.busy) else $fatal(1, "Master should be busy");
                assert (master.core.sda_internal == TEST2[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", 3'(i), master.core.transaction_progress, TEST2[7 - i], master.core.sda_internal);
                wait (master.core.counter == master.core.COUNTER_TRANSMIT && !clk_in);
            end
            inoutmode <= 1'b1;
            sda_in <= j == 7 ? 1'bz : 1'b0; // NACK or ACK
            wait ((j == 0 ? master.internal_interrupt : interrupt) && !clk_in);
            assert (j == 0 ? master.internal_transaction_complete : transaction_complete) else $fatal(1, "Transaction did not complete successfully");
            assert (j == 7 ? nack : !nack) else $fatal(1, "Unexpected ACK/NACK for %d", j);
            transfer_start <= 1'b0;
            transfer_continues <= 1'(j + 1 != 7);
            if (j != 7)
            begin
                TEST2 <= {8'd0, TEST2[63:8]};
                data_tx <= TEST2[15:8];
            end
        end

        TEST2 <= TEST2_CONST;
    end

    wait (transfer_ready && !clk_in);

    $display("\nBeginning bulk reception");
    transfer_start <= 1'b1;
    transfer_continues <= 1'b1;
    address <= TEST3[7:0];
    for (j = 0; j < 8; j++)
    begin
        wait (master.core.counter == (master.core.COUNTER_RECEIVE + 1) % (master.core.COUNTER_END + 1) + (j == 0 ? 0 : 1) && !clk_in);
        $display("Byte %d (%h)", j, TEST3[7:0]);
        assert (master.core.busy) else $fatal(1, "Master should be busy");
        if (j == 0)
        begin
            wait (master.core.counter == master.core.COUNTER_TRANSMIT && !clk_in);
            assert (master.core.latched_data == TEST3[7:0]) else $fatal(1, "Master didn't latch address expected %h but was %h", TEST3[7:0], master.core.latched_data);
            inoutmode <= 1'b0;
        end
        else
        begin
            inoutmode <= 1'b1;
        end
        for (i = 0; i < 8; i++)
        begin
            if (j == 0)
            begin
                wait (master.core.counter == master.core.COUNTER_TRANSMIT + 1 && !clk_in);
                assert (master.core.transaction_progress == 4'(i + 2)) else $fatal(1, "Unexpected TX progress: %d should be ", master.core.transaction_progress, i + 2);
                assert (master.core.busy) else $fatal(1, "Master should be busy");
                assert (master.core.sda_internal == TEST3[7 - i]) else $fatal(1, "Loop %d TX progress %d expected %b but was %b", 3'(i), master.core.transaction_progress, TEST3[7 - i], master.core.sda_internal);
                wait (master.core.counter == master.core.COUNTER_TRANSMIT && !clk_in);
            end
            else
            begin
                wait (master.core.counter == master.core.COUNTER_TRANSMIT && clk_in);
                sda_in <= TEST3[7 - i] ? 1'bz : 1'b0;
                wait (master.core.counter == (master.core.COUNTER_RECEIVE + 1) % (master.core.COUNTER_END + 1) && !clk_in);
                assert (master.core.latched_data[7 - i] == TEST3[7 - i]) else $fatal(1, "Loop %d RX progress %d expected %b but was %b", i, master.core.transaction_progress, TEST3[7 - i], master.core.latched_data[7 - i]);
            end
        end
        inoutmode <= j == 0 ? 1'b1 : 1'b0;
        if (j == 0)
        begin
            sda_in <= 1'b0;
            wait (master.internal_interrupt && !clk_in);
            assert (master.internal_transaction_complete) else $fatal(1, "Address transmit did not complete successfully");
        end
        else
        begin
            wait (master.core.counter == master.core.COUNTER_TRANSMIT + 1 && !clk_in);
            wait (interrupt && !clk_in);
            assert (transaction_complete) else $fatal(1, "Transaction did not complete successfully");
            assert (j == 7 ? nack : !nack) else $fatal(1, "Master sent unexpected ACK/NACK for %d", j);
            assert (data_rx == TEST3[7:0]) else $fatal(1, "Data did not reach data_rx");
        end
        transfer_start <= 1'b0;
        transfer_continues <= 1'(j + 1 != 7);
        if (j != 7)
            TEST3 <= {8'd0, TEST3[63:8]};
    end

    $finish;
end

endmodule
