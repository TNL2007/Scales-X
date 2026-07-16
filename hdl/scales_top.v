module scales_top #(
    parameter N     = 8,
    parameter N_ACT = 5,
    parameter V     = 2,
    parameter U     = 4,
    parameter K     = 32
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire         mode,
    input  wire [15:0]  batch_size,

    input  wire [K*U-1:0] d_in,
    input  wire            d_load,
    input  wire [$clog2((N_ACT+U-1)/U)-1:0] d_wr_addr,

    input  wire [2*N-1:0]  b_in,

    output wire            out_valid,
    output wire [K-1:0]    T_out,
    output wire            done,

    output wire [$clog2(N_ACT > 1 ? N_ACT : 2)-1:0] row_sel,

    output wire [15:0]     batch_cnt,
    output wire            bank_sel,
    output wire            d_load_next,

    output wire            error_flag,
    input  wire            fi_en,
    input  wire [$clog2(4*N)-1:0] fi_pos
);
    localparam W = (N_ACT + U - 1) / U;

    wire                          busy;
    wire [$clog2(W)-1:0]          cu_addr;
    wire                          b_load;
    wire                          shift_fwd;
    wire                          shift_bwd;
    wire                          acc_clear;
    wire                          acc_en;
    wire [$clog2(V)-1:0]          slot_sel;
    wire                          out_valid_cu;
    wire [$clog2(V)-1:0]          out_slot;
    wire                          done_cu;
    wire [2*N-1:0]                b_reg_out;
    wire [K-1:0]                  pec_result;
    wire [K*U-1:0]                d_out_flat0;
    wire [K*U-1:0]                d_out_flat1;
    wire [K*U-1:0]                d_out_flat;

    // Only use the bottom 2*U bits of b_reg_out for PEC
    wire [2*U-1:0] b_to_pec_orig;
    assign b_to_pec_orig = b_reg_out[2*U-1:0];

    // Pipeline registers to align signals with 1-cycle d_ram read latency
    reg                      acc_clear_reg;
    reg                      acc_en_reg;
    reg [$clog2(V)-1:0]      slot_sel_reg;
    reg                      out_valid_reg;
    reg                      done_reg;
    reg [2*U-1:0]            b_to_pec_reg;

    always @(posedge clk) begin
        if (rst) begin
            acc_clear_reg <= 1'b0;
            acc_en_reg    <= 1'b0;
            slot_sel_reg  <= 0;
            out_valid_reg <= 1'b0;
            done_reg      <= 1'b0;
            b_to_pec_reg  <= 0;
        end
        else begin
            acc_clear_reg <= acc_clear;
            acc_en_reg    <= acc_en;
            slot_sel_reg  <= slot_sel;
            out_valid_reg <= out_valid_cu;
            done_reg      <= done_cu;
            b_to_pec_reg  <= b_to_pec_orig;
        end
    end

    assign out_valid  = out_valid_reg;
    assign done       = done_reg || (|out_slot && 1'b0);
    assign d_out_flat = bank_sel ? d_out_flat1 : d_out_flat0;

    wire d_load0 = d_load && (!busy || (bank_sel == 1'b1));
    wire d_load1 = d_load && ( busy && (bank_sel == 1'b0));

    // -------------------------------------------------------------------------
    // CU
    // -------------------------------------------------------------------------
    cu #(
        .N    (N),
        .N_ACT(N_ACT),
        .V    (V),
        .U    (U)
    ) u_cu (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .error_detected(error_flag),
        .mode       (mode),
        .batch_size (batch_size),
        .busy       (busy),
        .addr       (cu_addr),
        .b_load     (b_load),
        .shift_fwd  (shift_fwd),
        .shift_bwd  (shift_bwd),
        .acc_clear  (acc_clear),
        .acc_en     (acc_en),
        .slot_sel   (slot_sel),
        .out_valid  (out_valid_cu),
        .out_slot   (out_slot),
        .done       (done_cu),
        .row_sel    (row_sel),
        .batch_cnt  (batch_cnt),
        .bank_sel   (bank_sel),
        .d_load_next(d_load_next)
    );

    // -------------------------------------------------------------------------
    // D-RAM bank 0
    // -------------------------------------------------------------------------
    d_ram #(
        .K    (K),
        .N    (N),
        .N_ACT(N_ACT),
        .U    (U)
    ) u_dram0 (
        .clk       (clk),
        .en        (1'b1),
        .load      (d_load0),
        .wr_addr   (d_wr_addr),
        .rd_addr   (cu_addr),
        .d_in_flat (d_in),
        .d_out_flat(d_out_flat0)
    );

    // -------------------------------------------------------------------------
    // D-RAM bank 1
    // -------------------------------------------------------------------------
    d_ram #(
        .K    (K),
        .N    (N),
        .N_ACT(N_ACT),
        .U    (U)
    ) u_dram1 (
        .clk       (clk),
        .en        (1'b1),
        .load      (d_load1),
        .wr_addr   (d_wr_addr),
        .rd_addr   (cu_addr),
        .d_in_flat (d_in),
        .d_out_flat(d_out_flat1)
    );

    // -------------------------------------------------------------------------
    // B-REG
    // -------------------------------------------------------------------------
    b_reg #(
        .N    (N),
        .N_ACT(N_ACT)
    ) u_breg (
        .clk           (clk),
        .rst           (rst),
        .load          (b_load),
        .shift_fwd     (shift_fwd),
        .shift_bwd     (shift_bwd),
        .mode          (mode),
        .b_in          (b_in),
        .b_out         (b_reg_out),
        .error_detected(b_reg_error),
        .fi_en         (fi_en),
        .fi_pos        (fi_pos)
    );

    wire b_reg_error;
    assign error_flag = b_reg_error || (|b_reg_out && 1'b0);

    // -------------------------------------------------------------------------
    // PEC
    // -------------------------------------------------------------------------
    pec #(
        .U(U)
    ) u_pec (
        .clk        (clk),
        .b_in       (b_to_pec_reg),
        .d_in       (d_out_flat),
        .T_chain_in (32'd0),
        .T_out      (pec_result)
    );

    // -------------------------------------------------------------------------
    // ACC — rst now connected (fixes ASSIGN-12#1)
    // -------------------------------------------------------------------------
    acc #(
        .V(V),
        .W(W)
    ) u_acc (
        .clk       (clk),
        .rst       (rst),
        .acc_clear (acc_clear_reg),
        .acc_en    (acc_en_reg),
        .slot_sel  (slot_sel_reg),
        .pec_result(pec_result),
        .out_valid (),
        .T_out     (T_out)
    );

endmodule