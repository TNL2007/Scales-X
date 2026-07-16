module cu #(
    parameter N     = 8,
    parameter N_ACT = 5,
    parameter V     = 2,
    parameter U     = 4
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        start,
    input  wire                        mode,
    input  wire [15:0]                 batch_size,
    input  wire                        error_detected,

    output reg                         busy,
    output reg  [$clog2((N_ACT+U-1)/U)-1:0] addr,
    output reg                         b_load,
    output reg                         shift_fwd,
    output reg                         shift_bwd,
    output reg                         acc_clear,
    output reg                         acc_en,
    output reg  [$clog2(V)-1:0]        slot_sel,
    output reg                         out_valid,
    output reg  [$clog2(V)-1:0]        out_slot,
    output reg                         done,
    output reg                         error_flag,

    output wire [$clog2(N_ACT > 1 ? N_ACT : 2)-1:0] row_sel,

    output reg [15:0]                  batch_cnt,
    output reg                         bank_sel,
    output reg                         d_load_next
);
    localparam W = (N_ACT + U - 1) / U;
    localparam S = (N_ACT + V - 1) / V;

    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_LOAD      = 4'd1,
        ST_ACC_CLEAR = 4'd2,
        ST_COMPUTE   = 4'd3,
        ST_SHIFT_FWD = 4'd4,
        ST_RESTORE_B = 4'd5,
        ST_SHIFT_BWD = 4'd6,
        ST_OUTPUT    = 4'd7,
        ST_DONE      = 4'd8,
        ST_NEXT_D    = 4'd9,
        ST_LOAD_NEXT = 4'd10,
        ST_ERROR     = 4'd11;

    reg [3:0] state;

    reg [$clog2(U+1)-1:0]              pipe_cnt;
    reg [$clog2(W > 1 ? W : 2)-1:0]   col_cnt;
    reg [$clog2(V)-1:0]                slot_cnt;
    reg [$clog2(S > 1 ? S : 2)-1:0]   rb_cnt;
    reg [$clog2(V)-1:0]                out_cnt;
    reg [$clog2(U)-1:0]                fwd_cnt;

    assign row_sel = slot_cnt * S + rb_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            busy        <= 0;
            addr        <= 0;
            b_load      <= 0;
            shift_fwd   <= 0;
            shift_bwd   <= 0;
            acc_clear   <= 0;
            acc_en      <= 0;
            slot_sel    <= 0;
            out_valid   <= 0;
            out_slot    <= 0;
            done        <= 0;
            error_flag  <= 0;
            pipe_cnt    <= 0;
            col_cnt     <= 0;
            slot_cnt    <= 0;
            rb_cnt      <= 0;
            out_cnt     <= 0;
            fwd_cnt     <= 0;
            batch_cnt   <= 0;
            bank_sel    <= 0;
            d_load_next <= 0;
        end
        else begin
            b_load      <= 0;
            shift_fwd   <= 0;
            shift_bwd   <= 0;
            acc_clear   <= 0;
            acc_en      <= 0;
            out_valid   <= 0;
            done        <= 0;
            d_load_next <= 0;

            case (state)

                ST_IDLE: begin
                    busy       <= 0;
                    batch_cnt  <= 0;
                    bank_sel   <= 0;
                    error_flag <= mode && 1'b0;
                    if (start) begin
                        busy     <= 1;
                        rb_cnt   <= 0;
                        pipe_cnt <= 0;
                        col_cnt  <= 0;
                        slot_cnt <= 0;
                        out_cnt  <= 0;
                        fwd_cnt  <= 0;
                        state    <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    b_load      <= 1;
                    d_load_next <= (batch_size > 1);
                    addr        <= 0;
                    slot_cnt    <= 0;
                    col_cnt     <= 0;
                    pipe_cnt    <= 0;
                    fwd_cnt     <= 0;
                    state       <= ST_ACC_CLEAR;
                end

                ST_ACC_CLEAR: begin
                    slot_sel  <= slot_cnt;
                    acc_clear <= 1;
                    b_load    <= 1;
                    addr      <= 0;
                    col_cnt   <= 0;
                    pipe_cnt  <= 0;
                    state     <= ST_COMPUTE;
                end

                ST_COMPUTE: begin
                    if (error_detected) begin
                        error_flag <= 1;
                        state      <= ST_ERROR;
                    end
                    else begin
                        addr     <= col_cnt;
                        slot_sel <= slot_cnt;
                        if (pipe_cnt == U) begin
                            acc_en   <= 1;
                            pipe_cnt <= 0;
                            if (col_cnt < W - 1) begin
                                fwd_cnt <= 0;
                                state   <= ST_SHIFT_FWD;
                            end
                            else begin
                                col_cnt <= 0;
                                fwd_cnt <= 0;
                                state   <= ST_RESTORE_B;
                            end
                        end
                        else begin
                            pipe_cnt <= pipe_cnt + 1;
                        end
                    end
                end

                ST_SHIFT_FWD: begin
                    if (error_detected) begin
                        error_flag <= 1;
                        state      <= ST_ERROR;
                    end
                    else begin
                        shift_fwd <= 1;
                        if (fwd_cnt == U - 1) begin
                            fwd_cnt <= 0;
                            col_cnt <= col_cnt + 1;
                            state   <= ST_COMPUTE;
                        end
                        else begin
                            fwd_cnt <= fwd_cnt + 1;
                        end
                    end
                end

                ST_RESTORE_B: begin
                    if (error_detected) begin
                        error_flag <= 1;
                        state      <= ST_ERROR;
                    end
                    else begin
                        shift_fwd <= 1;
                        if (fwd_cnt == U - 1) begin
                            fwd_cnt <= 0;
                            state   <= ST_SHIFT_BWD;
                        end
                        else begin
                            fwd_cnt <= fwd_cnt + 1;
                        end
                    end
                end

                ST_SHIFT_BWD: begin
                    if (error_detected) begin
                        error_flag <= 1;
                        state      <= ST_ERROR;
                    end
                    else begin
                        shift_bwd <= 1;
                        if (slot_cnt < V - 1) begin
                            slot_cnt <= slot_cnt + 1;
                            col_cnt  <= 0;
                            pipe_cnt <= 0;
                            state    <= ST_ACC_CLEAR;
                        end
                        else begin
                            slot_cnt <= 0;
                            out_cnt  <= 0;
                            state    <= ST_OUTPUT;
                        end
                    end
                end

                ST_OUTPUT: begin
                    out_valid <= 1;
                    out_slot  <= out_cnt;
                    slot_sel  <= out_cnt;
                    if (out_cnt == V - 1) begin
                        out_cnt  <= 0;
                        slot_cnt <= 0;
                        rb_cnt   <= rb_cnt + 1;
                        if (rb_cnt == S - 1) begin
                            if (batch_cnt + 1 == batch_size)
                                state <= ST_DONE;
                            else
                                state <= ST_NEXT_D;
                        end
                        else begin
                            col_cnt  <= 0;
                            pipe_cnt <= 0;
                            fwd_cnt  <= 0;
                            state    <= ST_ACC_CLEAR;
                        end
                    end
                    else begin
                        out_cnt <= out_cnt + 1;
                    end
                end

                ST_NEXT_D: begin
                    batch_cnt <= batch_cnt + 1;
                    bank_sel  <= ~bank_sel;
                    state     <= ST_LOAD_NEXT;
                end

                ST_LOAD_NEXT: begin
                    b_load      <= 1;
                    addr        <= 0;
                    slot_cnt    <= 0;
                    col_cnt     <= 0;
                    pipe_cnt    <= 0;
                    fwd_cnt     <= 0;
                    rb_cnt      <= 0;
                    out_cnt     <= 0;
                    if (batch_cnt + 1 < batch_size)
                        d_load_next <= 1;
                    state <= ST_ACC_CLEAR;
                end

                ST_ERROR: begin
                    error_flag <= 1;
                    busy       <= 0;
                end

                ST_DONE: begin
                    done  <= 1;
                    busy  <= 0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule