module master #(
    // 50 MHz is commonly available in many FPGAs. Must be at least 4x the scl rate.
    parameter INPUT_CLK_RATE = 50000000,
    parameter MODE = 0, // 0 = Standard, 1 = Fast, 2 = Fast Plus

    // Is a slave on the bus capable of clock stretching or are there multiple masters? (if unsure, safer to assume yes)
    parameter CLOCK_STRETCHING = 1,

    // Are there multiple masters? (if unsure, safer to assume yes but more efficient to assume no)
    parameter MULTI_MASTER = 0,

    // Do some slaves sample at a lower rate? (if unsure, safer to assume yes)
    parameter START_BYTE = 1,

    // If there are multiple masters, detecting an scl line stuck LOW for bus_clear depends on knowing how slow the slowest master is.
    parameter SLOWEST_MASTER_RATE = 100,


    // "For a single master application, the master’s SCL output can be a push-pull driver design if there are no devices on the bus which would stretch the clock."
    // When using a push-pull driver, driving the scl line to HIGH while another device is driving it to LOW will create a short circuit.
    // If you enable the below parameter, you must be certain that this will not happen, and you accept the risks if it does.
    parameter FORCE_PUSH_PULL = 0
) (
    inout logic scl,
    input logic clk_in, // an arbitrary clock, used to derive the scl clock
    output logic bus_clear,

    inout logic sda = 1'bZ,
    input logic transfer_continue, // Synchronous control of master sda (graceful stop / start after current transaction)
    input logic mode, // 0 = transmit, 1 = receive
    input logic [7:0] data_rx,

    output logic data_rx_enable,
    output logic [7:0] data_tx,
    output logic data_rx_enable, // high when data_rx is ready
    output logic err = 1'b0, // whether there was an error during the last transaction, caused by a NACK or another master starting its own transaction
);

localparam TARGET_SCL_RATE = MODE == 0 ? 100000 : MODE == 1 ? 400000 : MODE == 2 ? 1000000 : 100000;

clock #(.INPUT_CLK_RATE(INPUT_CLK_RATE), .SLOWEST_MASTER_RATE(SLOWEST_MASTER_RATE), .TARGET_SCL_RATE(TARGET_SCL_RATE), .PUSH_PULL(FORCE_PUSH_PULL)) clock (.scl(scl), .bus_clear(bus_clear));

// See Section 3.1.4: START and STOP conditions
logic repeated_start_by_another_master = 1'd0;
logic busy = 1'd0;
always @(posedge sda or negedge sda)
begin
    if (scl)
    begin
        busy <= !sda;
        if (busy && !sda && transaction_progress != 4'd11 && MULTI_MASTER)
            repeated_start_by_another_master <= 1'd1;
    end
end

logic latched_mode;
logic [7:0] latched_data;
logic [3:0] transaction_progress = 4'd0;

localparam COUNTER_TRANSMIT = COUNTER_RISE / 2;
localparam COUNTER_RECEIVE = (COUNTER_END - COUNTER_RISE) / 2 + COUNTER_RISE;
always @(posedge clk_in or posedge repeated_start_by_another_master)
begin
    // See Note 4 in Section 3.1.10
    if (repeated_start_by_another_master)
    begin
        sda <= 1'bZ; // release line
        transaction_progress <= 4'd0;
        repeated_start_by_another_master <= 1'd0;
    end
    // "The HIGH or LOW state of the data line can only change when the clock signal on the SCL line is LOW"
    else if (counter == COUNTER_TRANSMIT && busy && transaction_progress != 4'd0)
    begin
        // See Section 3.1.5. Shift out data.
        if (transaction_progress >= 4'd1 && transaction_progress < 4'd9)
        begin
            if (!latched_mode) // transmit
                sda <= latched_data[4'd8 - transaction_progress] ? 1'bZ : 1'b0;
            transaction_progress <= transaction_progress + 4'd1;
        end
        // See Section 3.1.6. Expecting an acknowledge bit transfer in the next HIGH.
        else if (transaction_progress == 4'd9)
        begin
            if (!latched_mode)
                sda <= 1'bZ; // release line
            else
                sda <= transfer_continue ? 1'b0 : 1'bZ; // ACK / NACK
                // TODO: how should user gracefully indicate that the transaction is done at the time of the ACK?
            transaction_progress <= transaction_progress + 4'd1;
        end
        // See Section 3.1.4
        else if (transaction_progress == 4'd10)
        begin
            // prepares for repeated START condition or STOP condition
            sda <= transfer_continue ? 1'bZ : 1'b0;
            transaction_progress <= transaction_progress + 4'd1;
        end
    end
    // "The data on the SDA line must be stable during the HIGH period of the clock."
    else if (counter == COUNTER_RECEIVE)
    begin
        // START or repeated START condition
         if (transfer_continue && (!busy || (busy && transaction_progress == 4'd11)))
        begin
            sda <= 1'b0;
            transaction_progress <= 4'd1;
            latched_mode <= mode;
            if (!mode)
                latched_data <= data_in;
        end
        else if (busy)
        begin
            // See Section 3.1.5. Shift in data.
            if (latched_mode && transaction_progress >= 4'd2 && transaction_progress < 4'd10)
                latched_data[4'd9 - transaction_progress] <= sda;
            // See Section 3.1.6. Transmitter got an acknowledge bit or receiver sent it
            else if (transaction_progress == 4'd10)
            begin
                // transaction continues immediately in the next LOW, latch now
                // sda value is ACK, agnostic of transmit/receive
                if (transfer_continue && !sda)
                begin
                    latched_mode <= mode;
                    if (!mode)
                        latched_data <= data_in;
                    transaction_progress <= 4'd1;
                    // TODO: handle data out to disable the enable because there is a conflict here
                end
            end
            // STOP condition
            else if (transaction_progress == 4'd11)
            begin
                sda <= transfer_continue ? 1'b0 : 1'bZ;
                transaction_progress <= 4'd0;
            end
        end
        else if (busy && transaction_progress == 4'd0 && MULTI_MASTER) // Another master is doing a transaction (void messages tolerated, Note 5 in Section 3.1.10)
            sda <= 1'bZ;
    end
end

always @(posedge clk_in or posedge repeated_start_by_another_master)
    // transmitter notes whether ACK/NACK was received
    err <= repeated_start_by_another_master || (counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd10 && !latched_mode && sda);

always @(posedge clk_in)
begin
    if (counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd10 && latched_mode)
    begin
        data_rx_enable <= 1'b1;
        // receiver sent ACK and now gives the data to the user
        data_rx <= latched_data;
    end
    else
    begin
        data_rx_enable <= 1'b0;
        data_rx <= 8'dX;
    end
end

endmodule
