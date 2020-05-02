module i2c_core #(
    // 50 MHz is commonly available in many FPGAs. Must be at least 4 times the target scl rate.
    parameter int INPUT_CLK_RATE,
    // Targeted i2c bus frequency. Actual frequency depends on the slowest device.
    parameter int TARGET_SCL_RATE,

    // Is a slave on the bus capable of clock stretching?
    // If unsure, it's safer to assume yes.
    parameter bit CLOCK_STRETCHING,

    // Are there multiple masters?
    // If unsure, it's safer to assume yes, but more efficient to assume no.
    parameter bit MULTI_MASTER,

    // Detecting a stuck state depends on knowing how slow the slowest device is.
    parameter int SLOWEST_DEVICE_RATE,

    // "For a single master application, the master’s SCL output can be a push-pull driver design if there are no devices on the bus which would stretch the clock."
    // When using a push-pull driver, driving SCL HIGH while another device is driving it LOW will create a short circuit, damaging your FPGA.
    // If you enable this, you must be certain that it will not happen.
    // By doing so, you acknowledge and accept the risks involved.
    parameter bit FORCE_PUSH_PULL
) (
    inout wire scl,
    input logic clk_in, // an arbitrary clock, used to derive the scl clock
    output logic bus_clear,

    inout wire sda,

    // When starting a single-byte transfer, only transfer_start should be true
    // When starting a multi-byte transfer, both transfer_start and transfer_continues should be true
    // When doing a repeated start after this upcoming transaction, only transfer_start should be true
    input logic transfer_start, // whether to begin a new transfer asap (repeated START, START)
    input logic transfer_continues, // whether the transfer contains another transaction AFTER this transaction.
    input logic mode, // 0 = transmit, 1 = receive
    input logic [7:0] data_tx,

    output logic transfer_ready, // ready for a new transfer (bus is free)
    output logic interrupt = 1'b0, // A transaction has completed or an error occurred.
    output logic transaction_complete, // ready for a new transaction
    output logic nack, // When a transaction is complete, whether ACK/NACK was received/sent for the last transaction (0 = ACK, 1 = NACK).
    output logic [7:0] data_rx,

    // The below errors matter ONLY IF there are multiple masters on the bus
    output logic start_err = 1'd0, // Another master illegally issued a START condition while the bus was busy
    output logic arbitration_err = 1'b0 // Another master won the transaction due to arbitration, (or issued a START condition, when the user of this master wanted to)
);

// Derives the desired i2c mode from target rate.
localparam int MODE = $unsigned(TARGET_SCL_RATE) <= 100000 ? 0 : $unsigned(TARGET_SCL_RATE) <= 400000 ? 1 : $unsigned(TARGET_SCL_RATE) <= 1000000 ? 2 : -1;

localparam int COUNTER_WIDTH = $clog2(($unsigned(INPUT_CLK_RATE) - 1) / $unsigned(TARGET_SCL_RATE));
localparam bit [COUNTER_WIDTH-1:0] COUNTER_END = COUNTER_WIDTH'(($unsigned(INPUT_CLK_RATE) - 1) / $unsigned(TARGET_SCL_RATE));
// Conforms to Table 10 tLOW, tHIGH for SCL clock.
localparam bit [COUNTER_WIDTH-1:0] COUNTER_HIGH = COUNTER_WIDTH'(MODE == 0 ? ( (COUNTER_WIDTH + 1)'(COUNTER_END) + 1) / 2 : (( (COUNTER_WIDTH + 2)'(COUNTER_END) + 1) * 2) / 3);
// Conforms to Table 10 tr (rise time) for SCL clock.
localparam bit [COUNTER_WIDTH-1:0] COUNTER_RISE = COUNTER_WIDTH'(($unsigned(INPUT_CLK_RATE) - 1) / 1.0E9 * $unsigned(MODE == 0 ? 1000 : MODE == 1 ? 300 : MODE == 2  ? 120 : 0) + 1);

// Bus clear event counter
localparam int WAIT_WIDTH = $clog2(($unsigned(INPUT_CLK_RATE) - 1) / $unsigned(SLOWEST_DEVICE_RATE));
localparam bit [WAIT_WIDTH-1:0] WAIT_END = WAIT_WIDTH'(($unsigned(INPUT_CLK_RATE) - 1) / $unsigned(SLOWEST_DEVICE_RATE));

logic [COUNTER_WIDTH-1:0] counter;
// stick counter used to meet timing requirements
logic [COUNTER_WIDTH-1:0] countdown = COUNTER_WIDTH'(0);

logic [3:0] transaction_progress = 4'd0;

logic release_line;
assign release_line = (transaction_progress == 4'd0 && counter == COUNTER_HIGH) || countdown > 0;

clock #(
    .COUNTER_WIDTH(COUNTER_WIDTH),
    .COUNTER_END(COUNTER_END),
    .COUNTER_HIGH(COUNTER_HIGH),
    .COUNTER_RISE(COUNTER_RISE),
    .MULTI_MASTER(MULTI_MASTER),
    .CLOCK_STRETCHING(CLOCK_STRETCHING),
    .WAIT_WIDTH(WAIT_WIDTH),
    .WAIT_END(WAIT_END),
    .PUSH_PULL(!CLOCK_STRETCHING && !MULTI_MASTER && FORCE_PUSH_PULL)
) clock (.scl(scl), .clk_in(clk_in), .release_line(release_line), .bus_clear(bus_clear), .counter(counter));

logic sda_internal = 1'b1;
assign sda = sda_internal ? 1'bz : 1'b0;

// Conforms to Table 10 minimum setup/hold/bus free times.
localparam real TLOW_MIN = MODE == 0 ? 4.7 : MODE == 1 ? 1.3 : MODE == 2 ? 0.5 : 0; // in microseconds
localparam real THIGH_MIN = MODE == 0 ? 4.0 : MODE == 1 ? 0.6 : MODE == 2 ? 0.26 : 0; // in microseconds
localparam bit [COUNTER_WIDTH-1:0] COUNTER_SETUP_REPEATED_START = COUNTER_WIDTH'($unsigned(INPUT_CLK_RATE) / 1.0E6 * TLOW_MIN);
localparam bit [COUNTER_WIDTH-1:0] COUNTER_BUS_FREE = COUNTER_SETUP_REPEATED_START;
localparam bit [COUNTER_WIDTH-1:0] COUNTER_HOLD_REPEATED_START = COUNTER_WIDTH'($unsigned(INPUT_CLK_RATE) / 1.0E6 * THIGH_MIN);
localparam bit [COUNTER_WIDTH-1:0] COUNTER_SETUP_STOP = COUNTER_HOLD_REPEATED_START;

localparam bit [COUNTER_WIDTH-1:0] COUNTER_TRANSMIT = COUNTER_WIDTH'(COUNTER_HIGH / 2);
localparam bit [COUNTER_WIDTH-1:0] COUNTER_RECEIVE = COUNTER_WIDTH'(COUNTER_HIGH + COUNTER_RISE);

logic latched_mode;
logic [7:0] latched_data;
logic latched_transfer_continues;

assign data_rx = latched_data;

// assume bus is free
logic busy = 1'b0;
assign transfer_ready = counter == COUNTER_HIGH && !busy && countdown == 0;

// See Section 3.1.4: START and STOP conditions
logic last_sda = 1'b1;
always_ff @(posedge clk_in)
`ifdef MODEL_TECH
    last_sda <= sda === 1'bz;
`else
    last_sda <= sda;
`endif

logic start_by_a_master;
logic stop_by_a_master;
`ifdef MODEL_TECH
assign start_by_a_master = last_sda === 1'bz && sda === 1'b0 && scl === 1'bz;
assign stop_by_a_master = last_sda === 1'b0 && sda === 1'bz && scl === 1'bz;
`else
assign start_by_a_master = last_sda && !sda && scl;
assign stop_by_a_master = !last_sda && sda && scl;
`endif

// transmitter notes whether ACK/NACK was received
// receiver notes whether ACK/NACK was sent
// treats a start by another master as as an ACK
`ifdef MODEL_TECH
assign nack = sda === 1'bz;
`else
assign nack = sda;
`endif

always_ff @(posedge clk_in)
begin
    start_err = MULTI_MASTER && start_by_a_master && !(transaction_progress == 4'd0 || (transaction_progress == 4'd11 && transfer_start && counter == COUNTER_RECEIVE));

    // transmitter listens for loss of arbitration
    arbitration_err = MULTI_MASTER && (counter == COUNTER_RECEIVE && transaction_progress >= 4'd2 && transaction_progress < 4'd10 && !latched_mode && sda != latched_data[4'd9 - transaction_progress] && !start_err);

    transaction_complete = counter == COUNTER_RECEIVE - 2 && transaction_progress == (COUNTER_RECEIVE - 2 == COUNTER_TRANSMIT ? 4'd9 : 4'd10) && !start_err && !arbitration_err;

    interrupt = start_err || arbitration_err || transaction_complete;

    // See Note 4 in Section 3.1.10
    if (start_err || arbitration_err)
    begin
        sda_internal <= 1'b1; // release line
        transaction_progress <= 4'd0;
        countdown <= COUNTER_WIDTH'(0);
        busy <= 1'b1;
    end
    // Keep current state to meet setup/hold constraints in Table 10.
    else if (countdown != COUNTER_WIDTH'(0))
    begin
        countdown <= countdown - 1'b1;
    end
    else if (transaction_progress == 4'd0 && !(transfer_start && counter == COUNTER_HIGH) && MULTI_MASTER)
    begin
        busy <= busy ? !stop_by_a_master : start_by_a_master;
    end
    else if (counter == COUNTER_HIGH)
    begin
        if ((transaction_progress == 4'd0 || transaction_progress == 4'd11) && transfer_start)
        begin
            if (transaction_progress == 4'd0)
                transaction_progress <= 4'd1;

            latched_mode <= mode;
            // if (!mode) // Mode doesn't matter, save some logic cells
            latched_data <= data_tx;
            latched_transfer_continues <= transfer_continues;
        end
        if (transaction_progress == 4'd11) // Setup time padding for repeated start, stop
        begin
            if (transfer_start && COUNTER_SETUP_REPEATED_START > COUNTER_RECEIVE - COUNTER_HIGH)
                countdown <= COUNTER_SETUP_REPEATED_START - (COUNTER_RECEIVE - COUNTER_HIGH);
            else if (COUNTER_SETUP_STOP > COUNTER_RECEIVE - COUNTER_HIGH)
                countdown <= COUNTER_SETUP_STOP - (COUNTER_RECEIVE - COUNTER_HIGH);
        end
    end
    // "The data on the SDA line must be stable during the HIGH period of the clock."
    else if (counter == COUNTER_RECEIVE)
    begin
        if (transaction_progress == 4'd0)
            sda_internal <= 1'b1;
        // START or repeated START condition
        else if ((transaction_progress == 4'd1 || transaction_progress == 4'd11) && transfer_start)
        begin
            transaction_progress <= 4'd1;
            sda_internal <= 1'b0;
            if (transaction_progress == 4'd11 && COUNTER_HOLD_REPEATED_START > (COUNTER_END - COUNTER_RECEIVE)) // Hold time padding
                countdown <= COUNTER_HOLD_REPEATED_START - (COUNTER_END - COUNTER_RECEIVE);
            busy <= 1'b1;
        end
        // See Section 3.1.5. Shift in data.
        else if (transaction_progress >= 4'd2 && transaction_progress < 4'd10 && latched_mode)
        begin
            `ifdef MODEL_TECH
                latched_data[4'd9 - transaction_progress] <= sda === 1'bz;
            `else
                latched_data[4'd9 - transaction_progress] <= sda;
            `endif
                sda_internal <= 1'b1; // Should help reduce slave rise time
        end
        // See Section 3.1.6. Transmitter got an acknowledge bit or receiver sent it.
        // transfer continues immediately in the next LOW, latch now
        // refuses to continue the transfer if transmitter got a NACK (TODO: there should be no transfer_start here, it could be set but it doesn't make sense to set it)
        else if (transaction_progress == 4'd10 && latched_transfer_continues && (mode || !nack))
        begin
            transaction_progress <= 4'd1;
            latched_mode <= mode;
            // if (!mode) // Mode doesn't matter, save some logic cells
            latched_data <= data_tx;
            latched_transfer_continues <= transfer_continues;
        end
        // STOP condition
        else if (transaction_progress == 4'd11 && !transfer_start)
        begin
            sda_internal <= 1'b1;
            transaction_progress <= 4'd0;
            if (COUNTER_BUS_FREE > COUNTER_END - COUNTER_RECEIVE)
                countdown <= COUNTER_BUS_FREE - (COUNTER_END - COUNTER_RECEIVE);
            busy <= 1'b0;
        end
    end
    // "The HIGH or LOW state of the data line can only change when the clock signal on the SCL line is LOW"
    else if (counter == COUNTER_TRANSMIT && transaction_progress != 4'd0)
    begin
        transaction_progress <= transaction_progress + 4'd1;
        // See Section 3.1.5. Shift out data.
        if (transaction_progress < 4'd9)
        begin
            if (!latched_mode)
                sda_internal <= latched_data[4'd8 - transaction_progress];
            else
                sda_internal <= 1'b1; // release line for RX
        end
        // See Section 3.1.6. Expecting an acknowledge bit transfer in the next HIGH.
        else if (transaction_progress == 4'd9)
            sda_internal <= latched_mode ? !transfer_continues : 1'b1; // receiver sends ACK / NACK, transmitter releases line
        // See Section 3.1.4
        else if (transaction_progress == 4'd10)
            sda_internal <= transfer_start; // prepare for repeated START condition or STOP condition
    end
end

endmodule
