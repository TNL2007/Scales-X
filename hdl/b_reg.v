module b_reg #(
    parameter N     = 8,
    parameter N_ACT = 5
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           load,
    input  wire           shift_fwd,
    input  wire           shift_bwd,
    input  wire           mode,
    (* dont_touch = "true" *) input  wire [2*N-1:0] b_in,
    output reg  [2*N-1:0] b_out,
    output wire            error_detected,
    input  wire            fi_en,
    input  wire [$clog2(4*N)-1:0] fi_pos
);



    // Use localparam to avoid signed/unsigned mismatch on N-1 subtraction
    localparam N_LAST = N - 1;

    reg [3:0] hreg [0:N-1];
    reg [1:0] temp [0:N-1];
    reg [N-1:0] coeff_ok;
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) begin
                hreg[i] <= 4'b0000;
            end
        end
        else if (load) begin
            for (i = 0; i < N; i = i + 1) begin
                if (i < N_ACT) begin
                    hreg[i][1:0] <= b_in[2*i +: 2];
                    hreg[i][2]   <= b_in[2*i+1];
                    hreg[i][3]   <= b_in[2*i+1] ^ b_in[2*i];
                end
                else
                    hreg[i] <= 4'b0000;
            end
        end

        else if (shift_fwd) begin
            for (i = 0; i < N-1; i = i+1)
                temp[i] = hreg[i+1][1:0];
            temp[N_LAST] = hreg[0][1:0];
            for (i = 0; i < N; i = i+1) begin
                hreg[i][1:0] <= temp[i];
                hreg[i][2]   <= temp[i][1];
                hreg[i][3]   <= temp[i][1] ^ temp[i][0];
            end
        end

        else if (shift_bwd) begin
            temp[0] = hreg[N_LAST][1:0];
            if (mode == 1'b0) begin
                if      (temp[0] == 2'b01) temp[0] = 2'b11;
                else if (temp[0] == 2'b11) temp[0] = 2'b01;
            end
            for (i = 1; i < N; i = i+1)
                temp[i] = hreg[i-1][1:0];
            for (i = 0; i < N; i = i+1) begin
                hreg[i][1:0] <= temp[i];
                hreg[i][2]   <= temp[i][1];
                hreg[i][3]   <= temp[i][1] ^ temp[i][0];
            end
        end

        else if (fi_en) begin
            for (i = 0; i < N; i = i+1) begin
                if (fi_pos >= 4*i && fi_pos < 4*(i+1))
                    hreg[i][fi_pos - 4*$unsigned(i)] <= ~hreg[i][fi_pos - 4*$unsigned(i)];
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : PARITY_CHK
            wire [1:0] d_s = hreg[g][1:0];
            wire [1:0] c_s = hreg[g][3:2];
            always @(*) coeff_ok[g] = (c_s[0] == d_s[1]) &&
                                       (c_s[1] == (d_s[1] ^ d_s[0]));
        end
    endgenerate

    assign error_detected = ~(&coeff_ok);

    always @(*) begin
        for (i = 0; i < N; i = i+1)
            b_out[2*i +: 2] = hreg[i][1:0];
    end

endmodule