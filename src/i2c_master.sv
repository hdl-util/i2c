module i2c_master #(
    // 50 MHz is commonly available in many FPGAs. Must be at least 4 times the target scl rate.
    parameter int INPUT_CLK_RATE = 50000000,
    // Targeted i2c bus frequency. Actual frequency depends on the slowest device.
    parameter int TARGET_SCL_RATE = 100000,

    // Is a slave on the bus capable of clock stretching?
    // If unsure, it's safer to assume yes.
    parameter bit CLOCK_STRETCHING = 1,

    // Are there multiple masters?
    // If unsure, it's safer to assume yes, but more efficient to assume no.
    parameter bit MULTI_MASTER = 0,

    // Detecting a stuck state depends on knowing how slow the slowest device is.
    parameter int SLOWEST_DEVICE_RATE = 100,

    // "For a single master application, the master’s SCL output can be a push-pull driver design if there are no devices on the bus which would stretch the clock."
    // When using a push-pull driver, driving SCL HIGH while another device is driving it LOW will create a short circuit, damaging your FPGA.
    // If you enable this, you must be certain that it will not happen.
    // By doing so, you acknowledge and accept the risks involved.
    parameter bit FORCE_PUSH_PULL = 0
) (
    inout wire scl,
    input logic clk_in, // an arbitrary clock, used to derive the scl clock
    output logic bus_clear,

    inout wire sda,

    // 7-bit device address followed by 1 bit mode (1 = read, 0 = write)
    input logic [7:0] address,

    // When starting a single-byte transfer, only transfer_start should be true
    // When starting a multi-byte transfer, both transfer_start and transfer_continues should be true
    // When doing a repeated start after this upcoming transaction, only transfer_start should be true
    input logic transfer_start, // whether to begin a new transfer asap (repeated START, START)
    input logic transfer_continues, // whether the transfer contains another transaction AFTER this transaction.
    input logic [7:0] data_tx,

    output logic transfer_ready, // ready for a new transfer (bus is free)

    output logic interrupt, // A transaction has completed or an error occurred.
    output logic transaction_complete, // ready for a new transaction
    output logic nack, // When a transaction is complete, whether ACK/NACK was received/sent for the last transaction (0 = ACK, 1 = NACK).
    output logic [7:0] data_rx,

    output logic address_err, // Address was not acknowledged by a slave

    // The below errors matter ONLY IF there are multiple masters on the bus
    output logic start_err, // Another master illegally issued a START condition while the bus was busy
    output logic arbitration_err // Another master won the transaction due to arbitration, (or issued a START condition, when the user of this master wanted to)
);

logic internal_interrupt;
logic internal_transaction_complete;

// 0 = address transfer
// 1 = regular transfer
logic state = 1'b0;

logic just_interrupted = 1'd0;
always @(posedge clk_in) just_interrupted <= interrupt;

// Transition to 1 after address sent, transition back to 0 after transfer completes
logic instantaneous_state;
assign instantaneous_state = state ? !(transfer_ready || (transfer_start && just_interrupted)) : (internal_interrupt && internal_transaction_complete);

// Transfer must continue after sending I2C address
logic internal_transfer_continues;
assign internal_transfer_continues = instantaneous_state ? transfer_continues : 1'b1;


assign interrupt = internal_interrupt && (state == 1'd1 || address_err);

// Don't send a complete until after the I2C address is sent
assign transaction_complete = state ? internal_transaction_complete : 1'b0;

// TX address, either TX/RX the rest by user command
logic mode;
assign mode = instantaneous_state ? address[0] : 1'b0;

// Transmit address, then user data
logic [7:0] internal_data_tx;
assign internal_data_tx = instantaneous_state ? data_tx : address;

// First transmit transaction completes but got a NACK
assign address_err = state ? 1'b0 : internal_transaction_complete && nack;

always_ff @(posedge clk_in) state <= instantaneous_state;

i2c_core #(
    .INPUT_CLK_RATE(INPUT_CLK_RATE),
    .TARGET_SCL_RATE(TARGET_SCL_RATE),
    .CLOCK_STRETCHING(CLOCK_STRETCHING),
    .MULTI_MASTER(MULTI_MASTER),
    .SLOWEST_DEVICE_RATE(SLOWEST_DEVICE_RATE),
    .FORCE_PUSH_PULL(FORCE_PUSH_PULL)
) core (
    .scl(scl),
    .clk_in(clk_in),
    .bus_clear(bus_clear),
    .sda(sda),
    .transfer_start(transfer_start),
    .transfer_continues(internal_transfer_continues),
    .mode(mode),
    .data_tx(internal_data_tx),
    .transfer_ready(transfer_ready),
    .interrupt(internal_interrupt),
    .transaction_complete(internal_transaction_complete),
    .nack(nack),
    .data_rx(data_rx),
    .start_err(start_err),
    .arbitration_err(arbitration_err)
);

endmodule
