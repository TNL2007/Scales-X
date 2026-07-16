module pec #(parameter U = 4)(
    input wire clk,
    input wire [2*U-1:0] b_in,
    input wire [32*U-1:0] d_in,
    input wire [31:0] T_chain_in,
    output reg [31:0] T_out
);
    reg  [31:0] pipe_reg [0:U-2];
    wire [31:0] pe_wire  [0:U-1];
    wire [31:0] t_in     [0:U-1];

    assign t_in[0] = T_chain_in;

    genvar gi;
    generate
        for (gi = 1; gi < U; gi = gi + 1) begin : T_IN_CONN
            assign t_in[gi] = pipe_reg[gi-1];
        end
    endgenerate

    genvar k;
    generate
        for (k = 0; k < U; k = k + 1) begin : PE_STAGE
            wire [1:0]  b_k = b_in[2*k +: 2];
            wire [31:0] d_k = d_in[32*k +: 32];
            reg  [31:0] mult_r;

            always @(*) begin
                case (b_k)
                    2'b01:   mult_r = d_k;
                    2'b11:   mult_r = ~d_k + 1'b1;
                    default: mult_r = 32'd0;
                endcase
            end

            assign pe_wire[k] = t_in[k] + mult_r;
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        for (i = 0; i < U-1; i = i + 1)
            pipe_reg[i] <= pe_wire[i];
        T_out <= pe_wire[U-1];
    end

endmodule