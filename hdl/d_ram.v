module d_ram #(
    parameter K     = 32,
    parameter N     = 8,
    parameter N_ACT = 5,
    parameter U     = 4
)(
    input  wire clk,
    input  wire en,
    input  wire load,
    input  wire [$clog2((N_ACT+U-1)/U)-1:0] wr_addr,
    input  wire [$clog2((N_ACT+U-1)/U)-1:0] rd_addr,
    input  wire [K*U-1:0]                    d_in_flat,
    output wire [K*U-1:0]                    d_out_flat
);
    localparam DEPTH = (N_ACT + U - 1) / U;

    reg [K*U-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (load)
            mem[wr_addr] <= d_in_flat;
    end

    reg [K*U-1:0] d_out_reg;
    always @(posedge clk) begin
        if (en)
            d_out_reg <= mem[rd_addr];
    end
    assign d_out_flat = d_out_reg;

endmodule