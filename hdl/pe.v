module pe #(parameter K = 32)(
    input wire[1:0] b,
    input wire[K-1:0] d,
    input wire[K-1:0] t_in,
    output wire[K-1:0] mult_out,
    output wire[K-1:0] t_out
);

    ternary_mult #(.K(K)) u_mult(
        .b(b),
        .d(d),
        .result(mult_out)
    );

    mod_adder #(.K(K)) u_adder(
        .t_in(t_in),
        .mult(mult_out),
        .t_out(t_out)
    );

endmodule