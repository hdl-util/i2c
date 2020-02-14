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

    inout logic sda,
    input logic mode, // 0 = transmit, 1 = receive

    // These two flags are exclusive
    input logic transfer_start, // begin a new transfer asap (repeated START, START)
    input logic transfer_continue, // continue transfer (send ACK and begin next transaction)
    output logic transaction_ready, // ready for a new transaction (idling)
    output logic interrupt = 1'b1, // A transaction has completed or an error occurred.
    output logic transaction_complete, // ready for a new transaction
    output logic ack = 1'b0, // Whether an ACK/NACK was received during the last transaction (0 = ACK, 1 = NACK)
    output logic start_err = 1'd0, // A master issued a START condition while the bus was busy
    output logic arbitration_err = 1'b0, // Another master won the transaction due to arbitration

    input logic [7:0] data_tx,
    output logic [7:0] data_rx = latched_data,
    output logic data_rx_enable = 1'b0,
);

localparam TARGET_SCL_RATE = MODE == 0 ? 100000 : MODE == 1 ? 400000 : MODE == 2 ? 1000000 : 100000;
localparam COUNTER_WIDTH = $clog2(INPUT_CLK_RATE / TARGET_SCL_RATE);
localparam COUNTER_END = COUNTER_WIDTH'(INPUT_CLK_RATE / TARGET_SCL_RATE);
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_RISE = COUNTER_WIDTH'(MODE == 0 ? COUNTER_END / 2 : (COUNER_END * 2) / 3);

clock #(.COUNTER_WIDTH(COUNTER_WIDTH), .COUNTER_END(COUNTER_END), .COUNTER_RISE(COUNTER_RISE), .PUSH_PULL(FORCE_PUSH_PULL)) clock (.scl(scl), .bus_clear(bus_clear));

// See Section 3.1.4: START and STOP conditions
logic busy = 1'b0;
logic repeated_start_by_another_master = 1'b0;
always @(posedge sda or negedge sda)
begin
    if (scl)
    begin
        busy <= !sda;
        // See Note 4 in Section 3.1.10
        if (busy && !sda && transaction_progress != 4'd11 && transaction_progress != 4'd0 && MULTI_MASTER)
            repeated_start_by_another_master <= 1'd1;
    end
end

localparam COUNTER_TRANSMIT = COUNTER_WIDTH'(COUNTER_RISE / 2);
localparam COUNTER_RECEIVE = COUNTER_WIDTH'((COUNTER_END - COUNTER_RISE) / 2 + COUNTER_RISE);

logic latched_mode;
logic [7:0] latched_data;
logic [3:0] transaction_progress = 4'd0;

// Raise flag to ask user what to do next (transaction_continue, transaction_start, or neither)
assign transaction_complete = counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd9;
assign transaction_ready = !busy;

always @(posedge clk_in or posedge repeated_start_by_another_master)
begin
    // See Note 4 in Section 3.1.10
    if (repeated_start_by_another_master)
    begin
        sda <= 1'bZ; // release line
        transaction_progress <= 4'd0;
        repeated_start_by_another_master <= 1'b0;
    end
    // "The data on the SDA line must be stable during the HIGH period of the clock."
    else if (counter == COUNTER_RECEIVE)
    begin
        // START or repeated START condition
        if ((transfer_start && !busy) || (transfer_continue && busy && transaction_progress == 4'd11))
        begin
            sda <= 1'b0;
            transaction_progress <= 4'd1;
            latched_mode <= mode;
            if (!mode)
                latched_data <= data_tx;
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
                // sda value must be ACK, agnostic of transmit/receive
                if (transfer_continue && !sda)
                begin
                    latched_mode <= mode;
                    if (!mode)
                        latched_data <= data_tx;
                    transaction_progress <= 4'd1;
                end
            end
            // STOP condition
            else if (transaction_progress == 4'd11)
            begin
                sda <= 1'bZ;
                transaction_progress <= 4'd0;
            end
        end
        else if (busy && transaction_progress == 4'd0 && MULTI_MASTER) // Another master is doing a transaction (void messages tolerated, Note 5 in Section 3.1.10)
            sda <= 1'bZ;
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
                sda <= 1'bZ; // transmitter releases line
            else
                sda <= transfer_continue ? 1'b0 : 1'bZ; // receiver sends ACK / NACK
            transaction_progress <= transaction_progress + 4'd1;
        end
        // See Section 3.1.4
        else if (transaction_progress == 4'd10)
        begin
            sda <= transfer_start ? 1'bZ : 1'b0; // prepare for repeated START condition or STOP condition
            transaction_progress <= transaction_progress + 4'd1;
        end
    end
end

// Flag assignment
always @(posedge clk_in or posedge repeated_start_by_another_master)
begin
    start_err = repeated_start_by_another_master;
    
    // transmitter notes whether ACK/NACK was received
    // receiver notes whether ACK/NACK was sent
    // assumes ACK when another master interrupts the transaction
    ack = repeated_start_by_another_master ? 1'b0 : sda && counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd10 && !latched_mode;

    interrupt = ack || start_err || transaction_complete;
end

always @(posedge clk_in)
    // receiver sent ACK and now gives the data to the user
    data_rx <= latched_mode && counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd10 ? latched_data : 8'dX;

endmodule
