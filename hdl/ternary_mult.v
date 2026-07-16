module ternary_mult #(parameter K = 32)(
    input wire [1:0] b,
    input wire [K-1:0] d,
    output reg [K-1:0] result
);
    always @(*) begin
      case(b)
        2'b01: result = d;
        2'b11 : result = (~d)+1'b1;
        default: result = {K{1'b0}};
      endcase
    end
endmodule 