module master #(
    // 50 MHz is commonly available in many FPGAs. Must be at least 4 times the scl rate.
    parameter INPUT_CLK_RATE = 50000000,
    // Targeted i2c frequency. Maximum depends on the desired mode.
    parameter TARGET_SCL_RATE = 100000,

    // Is a slave on the bus capable of clock stretching? (if unsure, safer to assume yes)
    parameter CLOCK_STRETCHING = 1,

    // Are there multiple masters? (if unsure, safer to assume yes but more efficient to assume no)
    parameter MULTI_MASTER = 0,

    // If there are multiple masters, detecting an scl line stuck LOW for bus_clear depends on knowing how slow the slowest master is.
    parameter SLOWEST_MASTER_RATE = 100,

    // "For a single master application, the master’s SCL output can be a push-pull driver design if there are no devices on the bus which would stretch the clock."
    // When using a push-pull driver, driving the scl line to HIGH while another device is driving it to LOW will create a short circuit, damaging your FPGA.
    // If you enable the below parameter, you must be certain that this will not happen, and you accept the risks if it does.
    parameter FORCE_PUSH_PULL = 0
) (
    inout logic scl,
    input logic clk_in, // an arbitrary clock, used to derive the scl clock
    output logic bus_clear,

    inout logic sda,
    input logic mode, // 0 = transmit, 1 = receive

    // These two flags are exclusive; a transfer can't continue if a new one is starting
    input logic transfer_start, // begin a new transfer asap (repeated START, START)
    input logic transfer_continue, // whether transfer continues AFTER this transaction. If not, a STOP or repeated START is issued.

    output logic transfer_ready, // ready for a new transfer (bus is not busy)
    output logic interrupt = 1'b1, // A transaction has completed or an error occurred.
    output logic transaction_complete, // ready for a new transaction
    output logic ack = 1'b0, // Whether an ACK/NACK was received during the last transaction (0 = ACK, 1 = NACK)
    output logic start_err = 1'd0, // Another master illegally issued a START condition while the bus was busy
    output logic arbitration_err = 1'b0, // Another master won the transaction due to arbitration, (or issued a START condition, when the user of this master wanted to)

    input logic [7:0] data_tx,
    output logic [7:0] data_rx
);
localparam MODE = TARGET_SCL_RATE <= 100000 ? 0 : TARGET_SCL_RATE <= 400000 ? 1 : TARGET_SCL_RATE <= 1000000 ? 2 : -1;
localparam COUNTER_WIDTH = $clog2(INPUT_CLK_RATE / TARGET_SCL_RATE);
localparam COUNTER_END = INPUT_CLK_RATE / TARGET_SCL_RATE;
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam COUNTER_RISE = MODE == 0 ? COUNTER_END / 2 : (COUNTER_END * 2) / 3;
localparam WAIT_END = 2 * INPUT_CLK_RATE / SLOWEST_MASTER_RATE;

logic [$clog2(COUNTER_END)-1:0] counter;
clock #(
    .COUNTER_END(COUNTER_END),
    .COUNTER_RISE(COUNTER_RISE),
    .MULTI_MASTER(MULTI_MASTER),
    .CLOCK_STRETCHING(CLOCK_STRETCHING),
    .WAIT_END(WAIT_END),
    .PUSH_PULL(!CLOCK_STRETCHING && !MULTI_MASTER && FORCE_PUSH_PULL)
) clock (.scl(scl), .clk_in(clk_in), .bus_clear(bus_clear), .counter(counter));

logic sda_internal = 1'b1;
assign sda = sda_internal ? 1'bz : 1'b0;

logic [3:0] transaction_progress = 4'd0;

// See Section 3.1.4: START and STOP conditions
logic busy = 1'b0;
logic start_by_another_master = 1'b0;
always @(posedge sda or negedge sda)
begin
    if (scl)
    begin
        busy <= !sda;
        // See Note 4 in Section 3.1.10
        // Should only trigger if a start occurs while this master was in the middle of something.
        if (busy && !sda && transaction_progress != 4'd0 && transaction_progress != 4'd11 && MULTI_MASTER)
            start_by_another_master <= 1'd1;
    end
end

localparam COUNTER_TRANSMIT = COUNTER_WIDTH'(COUNTER_RISE / 2);
localparam COUNTER_RECEIVE = COUNTER_WIDTH'((COUNTER_END - COUNTER_RISE) / 2 + COUNTER_RISE);

logic latched_mode;
logic [7:0] latched_data;
logic latched_transfer_continue;
logic latched_transfer_start;

assign data_rx = latched_data;


// Raise flag to ask user what to do next (transaction_continue, transaction_start, or neither)
assign transaction_complete = counter == (COUNTER_RECEIVE - 1) && busy && (transaction_progress == 4'd10 || (COUNTER_RECEIVE - 1 == COUNTER_TRANSMIT && transaction_progress == 4'd9));
assign transfer_ready = counter == (COUNTER_RECEIVE - 1) && !busy;

always @(posedge clk_in)
begin
    // See Note 4 in Section 3.1.10
    if (start_by_another_master)
    begin
        sda_internal <= 1'b1; // release line
        transaction_progress <= 4'd0;
        start_by_another_master <= 1'b0;
    end
    // "The data on the SDA line must be stable during the HIGH period of the clock."
    else if (counter == COUNTER_RECEIVE)
    begin
        // START or repeated START condition
        // TODO: what if the user saw transaction_ready and put in some stuff, but then busy went high before COUNTER_RECEIVE and now the transaction can't start? user thinks transaction began but it didn't, and there should be an arbitration error later on
        if (((transaction_progress == 4'd0 && !busy) || transaction_progress == 4'd11) && transfer_start)
        begin
            sda_internal <= 1'b0;
            transaction_progress <= 4'd1;
            latched_mode <= mode;
            if (!mode)
                latched_data <= data_tx;
            latched_transfer_continue <= transfer_continue;
        end
        else if (busy)
        begin
            // See Section 3.1.5. Shift in data.
            if (transaction_progress >= 4'd2 && transaction_progress < 4'd10)
            begin
                if (latched_mode)
                    latched_data[4'd9 - transaction_progress] <= sda;
            end
            // See Section 3.1.6. Transmitter got an acknowledge bit or receiver sent it.
            else if (transaction_progress == 4'd10)
            begin
                // transaction continues immediately in the next LOW, latch now
                // sda value must be ACK, agnostic of transmit/receive
                if (latched_transfer_continue && !sda)
                begin
                    transaction_progress <= 4'd1;
                    latched_mode <= mode;
                    if (!mode)
                        latched_data <= data_tx;
                    latched_transfer_continue <= transfer_continue;
                end
            end
            // STOP condition
            else if (transaction_progress == 4'd11 && !sda)
            begin
                sda_internal <= 1'b1;
                transaction_progress <= 4'd0;
            end
        end
        // Another master is doing a transaction (void messages tolerated, see Note 5 in Section 3.1.10)
        else if (busy && transaction_progress == 4'd0 && MULTI_MASTER)
            sda_internal <= 1'b1;
    end
    // "The HIGH or LOW state of the data line can only change when the clock signal on the SCL line is LOW"
    else if (counter == COUNTER_TRANSMIT && busy && transaction_progress != 4'd0)
    begin
        transaction_progress <= transaction_progress + 4'd1;
        // See Section 3.1.5. Shift out data.
        if (transaction_progress < 4'd9 && !latched_mode)
            sda_internal <= latched_data[4'd8 - transaction_progress] ? 1'b1 : 1'b0;
        // See Section 3.1.6. Expecting an acknowledge bit transfer in the next HIGH.
        else if (transaction_progress == 4'd9)
            sda_internal <= latched_mode && latched_transfer_continue ? 1'b0 : 1'b1; // receiver sends ACK / NACK, transmitter releases line
        // See Section 3.1.4
        else if (transaction_progress == 4'd10)
            sda_internal <= transfer_start ? 1'b1 : 1'b0; // prepare for repeated START condition or STOP condition
    end
end

// Flag assignment
logic [3:0] prev_transaction_progress = 4'd0;
always @(posedge clk_in)
begin
    start_err = start_by_another_master;

    // transmitter notes whether ACK/NACK was received
    // receiver does nothing
    // treats a start by another master as as an ACK
    ack = counter == COUNTER_RECEIVE && busy && transaction_progress == 4'd10 && !latched_mode && sda && !start_by_another_master;

    // transmitter listens for loss of arbitration on receive
    // treats a start by another master as no loss of arbitration
    arbitration_err = counter == COUNTER_RECEIVE && busy && transaction_progress >= 4'd2 && transaction_progress < 4'd10 && !latched_mode && MULTI_MASTER && sda != latched_data[4'd9 - transaction_progress] && !start_by_another_master;

    interrupt = ack || start_err || transaction_complete || arbitration_err;
end

endmodule
