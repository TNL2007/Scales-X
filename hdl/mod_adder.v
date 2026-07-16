module mod_adder #(parameter K = 32)(
    input wire [K-1:0] t_in,
    input wire [K-1:0] mult,
    output wire [K-1:0] t_out
);
    assign t_out = t_in + mult;
endmodule