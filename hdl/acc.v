module acc #(parameter V = 2, parameter W = 2)(
    input wire clk,
    input wire rst,
    input wire acc_clear,
    input wire acc_en,
    input wire[$clog2(V)-1:0] slot_sel,
    input wire[31:0] pec_result,
    output reg out_valid,
    output reg[31:0] T_out
);
    reg [31:0] acc_reg [0:V-1];

    integer j;
    always @(posedge clk) begin
        if(rst) begin
            for(j = 0; j < V; j = j + 1)
                acc_reg[j] <= 32'd0;
            out_valid <= 1'b0;
        end
        else if(acc_clear) begin
            acc_reg[slot_sel] <= 32'd0;
            out_valid <= 1'b0;
        end
        else if(acc_en) begin
            acc_reg[slot_sel] <= acc_reg[slot_sel] + pec_result;
        end
    end

    always @(*) begin
        T_out = acc_reg[slot_sel];
    end

    always @(posedge clk) begin
        if(acc_en) begin
            $display(
                "ACC slot=%0d old=%0d add=%0d new=%0d",
                slot_sel,
                acc_reg[slot_sel],
                pec_result,
                acc_reg[slot_sel] + pec_result
            );
        end
    end
endmodule
