`timescale 1ns/1ps

module scales_top_tb;

    parameter N     = 8;
    parameter N_ACT = 5;
    parameter V     = 2;
    parameter U     = 4;
    parameter K     = 32;
    localparam W = (N_ACT + U - 1) / U;
    localparam S = (N_ACT + V - 1) / V;

    reg  clk;
    reg  rst;
    reg  start;
    reg  mode;
    reg  [15:0] batch_size;

    reg  [K-1:0]    d_in [0:U-1];
    reg  d_load;
    reg  [$clog2(W > 1 ? W : 2)-1:0] d_wr_addr;

    wire [2*N-1:0]  b_in;
    wire            out_valid;
    wire [K-1:0]    T_out;
    wire            done;
    wire [$clog2(N_ACT > 1 ? N_ACT : 2)-1:0] row_sel;
    wire [15:0]     batch_cnt;
    wire            bank_sel;
    wire            d_load_next;

    // Extension 5: fault detection and injection ports
    wire            error_flag;
    reg             fi_en;
    reg  [$clog2(4*N)-1:0] fi_pos;

    wire [K*U-1:0] d_in_flat;
    genvar gi;
    generate
        for (gi = 0; gi < U; gi = gi + 1) begin : TB_D_IN_PACK
            assign d_in_flat[gi*K +: K] = d_in[gi];
        end
    endgenerate

    scales_top #(.N(N), .N_ACT(N_ACT), .V(V), .U(U), .K(K)) dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .mode       (mode),
        .batch_size (batch_size),
        .batch_cnt  (batch_cnt),
        .bank_sel   (bank_sel),
        .d_load_next(d_load_next),
        .d_in       (d_in_flat),
        .d_load     (d_load),
        .d_wr_addr  (d_wr_addr),
        .b_in       (b_in),
        .out_valid  (out_valid),
        .T_out      (T_out),
        .done       (done),
        .row_sel    (row_sel),
        .error_flag (error_flag),
        .fi_en      (fi_en),
        .fi_pos     (fi_pos)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    integer     B_coeff_batch [0:4][0:N_ACT-1];
    reg [K-1:0] D_coeff_batch   [0:4][0:N-1];
    reg [K-1:0] T_expected_batch[0:4][0:N-1];
    reg [K-1:0] T_collected     [0:4][0:N-1];

    reg [2*N-1:0] b_in_table_batch [0:4][0:N_ACT-1];
    assign b_in = b_in_table_batch[batch_cnt][row_sel];

    integer total_pass, total_fail;
    integer test_pass,  test_fail;
    integer b, k;

    integer tb_out_batch_cnt;
    integer tb_out_coeff_cnt;
    integer k_coeff;

    always @(posedge clk) begin
        #1;
        if (out_valid) begin
            k_coeff = ((tb_out_coeff_cnt % V) * S) + (tb_out_coeff_cnt / V);
            if (k_coeff < N_ACT) begin
                T_collected[tb_out_batch_cnt][k_coeff] <= T_out;
                $display("  [out] Batch %0d: seq=%0d -> T[%0d] = 0x%08h (%0d)",
                         tb_out_batch_cnt, tb_out_coeff_cnt, k_coeff, T_out, $signed(T_out));
            end else begin
                $display("  [out] Batch %0d: seq=%0d -> padding (k=%0d, discarded)",
                         tb_out_batch_cnt, tb_out_coeff_cnt, k_coeff);
            end

            if (tb_out_coeff_cnt == V * S - 1) begin
                tb_out_coeff_cnt <= 0;
                tb_out_batch_cnt <= tb_out_batch_cnt + 1;
            end else begin
                tb_out_coeff_cnt <= tb_out_coeff_cnt + 1;
            end
        end
    end

    reg [1:0] load_state;
    reg       load_start;
    integer   load_batch_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            load_state     <= 0;
            d_load         <= 0;
            load_batch_idx <= 0;
            d_wr_addr      <= 0;
            d_in[0] <= 0; d_in[1] <= 0; d_in[2] <= 0; d_in[3] <= 0;
        end else begin
            case (load_state)
                0: begin
                    d_load <= 0;
                    if (load_start) begin
                        load_state <= 1;
                    end else if (d_load_next) begin
                        load_batch_idx <= load_batch_idx + 1;
                        load_state     <= 1;
                    end
                end
                1: begin
                    d_load    <= 1;
                    d_wr_addr <= 0;
                    d_in[0]   <= D_coeff_batch[load_batch_idx][0];
                    d_in[1]   <= D_coeff_batch[load_batch_idx][1];
                    d_in[2]   <= D_coeff_batch[load_batch_idx][2];
                    d_in[3]   <= D_coeff_batch[load_batch_idx][3];
                    load_state <= 2;
                end
                2: begin
                    d_load    <= 1;
                    d_wr_addr <= 1;
                    d_in[0]   <= D_coeff_batch[load_batch_idx][4];
                    d_in[1]   <= 32'd0;
                    d_in[2]   <= 32'd0;
                    d_in[3]   <= 32'd0;
                    load_state <= 3;
                end
                3: begin
                    d_load     <= 0;
                    load_state <= 0;
                end
            endcase
        end
    end

    initial begin
        $dumpfile("scales_top_tb.vcd");
        $dumpvars(0, scales_top_tb);
    end

    function [1:0] enc;
        input integer x;
        begin
            if      (x > 0) enc = 2'b01;
            else if (x < 0) enc = 2'b11;
            else            enc = 2'b00;
        end
    endfunction

    task build_b_table_batch;
        input integer b_idx;
        input [0:0] test_mode;
        integer row, kk, sh, bval, wsign;
        reg [2*N-1:0] entry;
        begin
            wsign = (test_mode == 1'b0) ? -1 : 1;
            for (row = 0; row < N_ACT; row = row + 1) begin
                entry = 0;
                for (kk = 0; kk < N; kk = kk + 1) begin
                    if (kk >= N_ACT) begin
                        entry[2*kk +: 2] = 2'b00;
                    end else begin
                        sh = row - kk;
                        if (sh >= 0)
                            bval = B_coeff_batch[b_idx][sh % N_ACT];
                        else
                            bval = wsign * B_coeff_batch[b_idx][(N_ACT + sh) % N_ACT];
                        entry[2*kk +: 2] = enc(bval);
                    end
                end
                b_in_table_batch[b_idx][row] = entry;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Normal batch test (fi_en tied low)
    // -------------------------------------------------------------------------
    task run_batch_test;
        input [255:0] test_name;
        input [0:0]   test_mode;
        integer t;
        begin
            test_pass = 0;
            test_fail = 0;
            tb_out_batch_cnt = 0;
            tb_out_coeff_cnt = 0;

            $display("\n============================================================");
            $display("  BATCH TEST: %0s  MODE: %0s",
                test_name, test_mode ? "NTRU" : "BFV");
            $display("============================================================");

            rst        = 1;
            start      = 0;
            load_start = 0;
            batch_size = 5;
            mode       = test_mode;
            fi_en      = 0;
            fi_pos     = 0;

            for (b = 0; b < 5; b = b + 1)
                for (k = 0; k < N; k = k + 1)
                    T_collected[b][k] = 0;

            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 0;
            @(posedge clk); #1;

            load_start = 1;
            @(posedge clk); #1;
            load_start = 0;

            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            for (b = 0; b < 5; b = b + 1)
                build_b_table_batch(b, test_mode);
            $display("  b_in_table_batch built for all 5 batches");

            start = 1;
            @(posedge clk); #1;
            start = 0;

            begin : wait_done
                for (t = 0; t < 3000; t = t + 1) begin
                    @(posedge clk); #1;
                    if (done) begin
                        $display("  Done at cycle %0d", t);
                        disable wait_done;
                    end
                end
                $display("  TIMEOUT — done never asserted!");
            end

            @(posedge clk); #1;

            $display("  Comparing outputs for all 5 batches (N_ACT=%0d):", N_ACT);
            for (b = 0; b < 5; b = b + 1) begin
                $display("  --- Batch %0d ---", b);
                for (k = 0; k < N_ACT; k = k + 1) begin
                    if (T_collected[b][k] === T_expected_batch[b][k]) begin
                        $display("    PASS  T[%0d] = 0x%08h", k, T_collected[b][k]);
                        test_pass  = test_pass  + 1;
                        total_pass = total_pass + 1;
                    end else begin
                        $display("    FAIL  T[%0d]: got 0x%08h, expected 0x%08h",
                            k, T_collected[b][k], T_expected_batch[b][k]);
                        test_fail  = test_fail  + 1;
                        total_fail = total_fail + 1;
                    end
                end
            end
            $display("  Batch Test result: %0d passed, %0d failed", test_pass, test_fail);
        end
    endtask

    // -------------------------------------------------------------------------
    // Extension 5: Fault injection test
    // Loads B, runs for a few cycles, then injects a single-bit flip into
    // b_reg via fi_en/fi_pos, and verifies error_flag is asserted and the
    // CU halts (done never fires, error_flag goes high).
    // After confirming detection, resets and verifies normal operation resumes.
    // -------------------------------------------------------------------------
    task run_fault_injection_test;
        input [255:0] test_name;
        input [0:0]   test_mode;
        input [$clog2(4*N)-1:0] inject_pos;
        integer t;
        reg detected;
        begin
            $display("\n============================================================");
            $display("  FAULT INJECTION TEST: %0s  fi_pos=%0d", test_name, inject_pos);
            $display("============================================================");

            rst        = 1;
            start      = 0;
            load_start = 0;
            batch_size = 1;
            mode       = test_mode;
            fi_en      = 0;
            fi_pos     = inject_pos;

            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 0;
            @(posedge clk); #1;

            load_start = 1;
            @(posedge clk); #1;
            load_start = 0;

            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            build_b_table_batch(0, test_mode);

            // Start computation
            start = 1;
            @(posedge clk); #1;
            start = 0;

            // Let pipeline run for a few cycles then inject the fault
            repeat (5) @(posedge clk);
            #1;

            $display("  Injecting single-bit fault at fi_pos=%0d...", inject_pos);
            fi_en = 1;
            @(posedge clk); #1;
            fi_en = 0;

            // Wait up to 20 cycles for error_flag to assert
            detected = 0;
            begin : wait_error
                for (t = 0; t < 20; t = t + 1) begin
                    @(posedge clk); #1;
                    if (error_flag) begin
                        $display("  PASS  error_flag asserted at t+%0d after injection", t+1);
                        detected = 1;
                        total_pass = total_pass + 1;
                        disable wait_error;
                    end
                end
            end

            if (!detected) begin
                $display("  FAIL  error_flag never asserted — fault not detected!");
                total_fail = total_fail + 1;
            end

            // Verify CU is halted (done should NOT fire)
            begin : check_no_done
                for (t = 0; t < 10; t = t + 1) begin
                    @(posedge clk); #1;
                    if (done) begin
                        $display("  FAIL  done asserted after fault — CU should have halted");
                        total_fail = total_fail + 1;
                        disable check_no_done;
                    end
                end
                if (!done)
                    $display("  PASS  CU correctly halted (done not asserted after fault)");
            end

            // Reset and verify normal operation resumes
            $display("  Resetting and verifying normal operation resumes...");
            rst = 1;
            fi_en = 0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 0;
            @(posedge clk); #1;

            load_start = 1;
            @(posedge clk); #1;
            load_start = 0;

            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            build_b_table_batch(0, test_mode);

            start = 1;
            @(posedge clk); #1;
            start = 0;

            begin : wait_done_after_reset
                for (t = 0; t < 500; t = t + 1) begin
                    @(posedge clk); #1;
                    if (done) begin
                        $display("  PASS  Normal operation resumed — done asserted at t+%0d", t+1);
                        total_pass = total_pass + 1;
                        disable wait_done_after_reset;
                    end
                    if (error_flag) begin
                        $display("  FAIL  error_flag still set after reset — stuck fault");
                        total_fail = total_fail + 1;
                        disable wait_done_after_reset;
                    end
                end
                $display("  FAIL  TIMEOUT after reset — done never asserted");
                total_fail = total_fail + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        total_pass = 0; total_fail = 0;
        rst = 1; start = 0; d_load = 0; mode = 0; batch_size = 5;
        fi_en = 0; fi_pos = 0;
        d_in[0] = 0; d_in[1] = 0; d_in[2] = 0; d_in[3] = 0;

        $display("# SCALES Extensions 3+5 — Batching + Fault Detection Testbench");
        $display("# N=%0d, N_ACT=%0d, V=%0d, U=%0d, K=%0d, W=%0d, S=%0d",
            N, N_ACT, V, U, K, W, S);

        // =====================================================================
        // BFV batch test vectors
        // =====================================================================
        B_coeff_batch[0][0]=1; B_coeff_batch[0][1]=-1; B_coeff_batch[0][2]=0; B_coeff_batch[0][3]=1; B_coeff_batch[0][4]=0;
        D_coeff_batch[0][0]=32'd5; D_coeff_batch[0][1]=32'd3; D_coeff_batch[0][2]=32'd7; D_coeff_batch[0][3]=32'd2; D_coeff_batch[0][4]=32'd8;
        T_expected_batch[0][0]=32'h00000006; T_expected_batch[0][1]=32'hFFFFFFFC;
        T_expected_batch[0][2]=32'hFFFFFFFC; T_expected_batch[0][3]=32'h00000000; T_expected_batch[0][4]=32'h00000009;

        B_coeff_batch[1][0]=1; B_coeff_batch[1][1]=1; B_coeff_batch[1][2]=1; B_coeff_batch[1][3]=1; B_coeff_batch[1][4]=1;
        D_coeff_batch[1][0]=32'd10; D_coeff_batch[1][1]=32'd20; D_coeff_batch[1][2]=32'd30; D_coeff_batch[1][3]=32'd40; D_coeff_batch[1][4]=32'd50;
        T_expected_batch[1][0]=32'hFFFFFF7E; T_expected_batch[1][1]=32'hFFFFFFA6;
        T_expected_batch[1][2]=32'hFFFFFFE2; T_expected_batch[1][3]=32'h00000032; T_expected_batch[1][4]=32'h00000096;

        B_coeff_batch[2][0]=0; B_coeff_batch[2][1]=0; B_coeff_batch[2][2]=0; B_coeff_batch[2][3]=0; B_coeff_batch[2][4]=1;
        D_coeff_batch[2][0]=32'd0; D_coeff_batch[2][1]=32'd1; D_coeff_batch[2][2]=32'd0; D_coeff_batch[2][3]=32'd0; D_coeff_batch[2][4]=32'd0;
        T_expected_batch[2][0]=32'hFFFFFFFF; T_expected_batch[2][1]=32'h00000000;
        T_expected_batch[2][2]=32'h00000000; T_expected_batch[2][3]=32'h00000000; T_expected_batch[2][4]=32'h00000000;

        B_coeff_batch[3][0]=1; B_coeff_batch[3][1]=0; B_coeff_batch[3][2]=0; B_coeff_batch[3][3]=0; B_coeff_batch[3][4]=0;
        D_coeff_batch[3][0]=32'd7; D_coeff_batch[3][1]=32'd13; D_coeff_batch[3][2]=32'd3; D_coeff_batch[3][3]=32'd99; D_coeff_batch[3][4]=32'd42;
        T_expected_batch[3][0]=32'd7; T_expected_batch[3][1]=32'd13; T_expected_batch[3][2]=32'd3;
        T_expected_batch[3][3]=32'd99; T_expected_batch[3][4]=32'd42;

        B_coeff_batch[4][0]=1; B_coeff_batch[4][1]=-1; B_coeff_batch[4][2]=-1; B_coeff_batch[4][3]=1; B_coeff_batch[4][4]=0;
        D_coeff_batch[4][0]=32'h3EB13B90; D_coeff_batch[4][1]=32'h8B9D2434; D_coeff_batch[4][2]=32'h972A8469; D_coeff_batch[4][3]=32'h0822E8F3; D_coeff_batch[4][4]=32'h17FC695A;
        T_expected_batch[4][0]=32'hC7A60974; T_expected_batch[4][1]=32'h5CC5690B;
        T_expected_batch[4][2]=32'hB4DFBB4B; T_expected_batch[4][3]=32'h240C7BE6; T_expected_batch[4][4]=32'h044C2032;

        run_batch_test("Streaming 5 Polys BFV", 1'b0);

        // =====================================================================
        // NTRU batch test vectors
        // =====================================================================
        B_coeff_batch[0][0]=1; B_coeff_batch[0][1]=-1; B_coeff_batch[0][2]=0; B_coeff_batch[0][3]=1; B_coeff_batch[0][4]=0;
        D_coeff_batch[0][0]=32'd5; D_coeff_batch[0][1]=32'd3; D_coeff_batch[0][2]=32'd7; D_coeff_batch[0][3]=32'd2; D_coeff_batch[0][4]=32'd8;
        T_expected_batch[0][0]=32'h00000004; T_expected_batch[0][1]=32'h00000000;
        T_expected_batch[0][2]=32'h0000000C; T_expected_batch[0][3]=32'h00000000; T_expected_batch[0][4]=32'h00000009;

        B_coeff_batch[1][0]=1; B_coeff_batch[1][1]=1; B_coeff_batch[1][2]=1; B_coeff_batch[1][3]=1; B_coeff_batch[1][4]=1;
        D_coeff_batch[1][0]=32'd10; D_coeff_batch[1][1]=32'd20; D_coeff_batch[1][2]=32'd30; D_coeff_batch[1][3]=32'd40; D_coeff_batch[1][4]=32'd50;
        T_expected_batch[1][0]=32'h00000096; T_expected_batch[1][1]=32'h00000096;
        T_expected_batch[1][2]=32'h00000096; T_expected_batch[1][3]=32'h00000096; T_expected_batch[1][4]=32'h00000096;

        B_coeff_batch[2][0]=0; B_coeff_batch[2][1]=0; B_coeff_batch[2][2]=0; B_coeff_batch[2][3]=0; B_coeff_batch[2][4]=1;
        D_coeff_batch[2][0]=32'd0; D_coeff_batch[2][1]=32'd1; D_coeff_batch[2][2]=32'd0; D_coeff_batch[2][3]=32'd0; D_coeff_batch[2][4]=32'd0;
        T_expected_batch[2][0]=32'h00000001; T_expected_batch[2][1]=32'h00000000;
        T_expected_batch[2][2]=32'h00000000; T_expected_batch[2][3]=32'h00000000; T_expected_batch[2][4]=32'h00000000;

        B_coeff_batch[3][0]=1; B_coeff_batch[3][1]=0; B_coeff_batch[3][2]=0; B_coeff_batch[3][3]=0; B_coeff_batch[3][4]=0;
        D_coeff_batch[3][0]=32'd7; D_coeff_batch[3][1]=32'd13; D_coeff_batch[3][2]=32'd3; D_coeff_batch[3][3]=32'd99; D_coeff_batch[3][4]=32'd42;
        T_expected_batch[3][0]=32'd7; T_expected_batch[3][1]=32'd13; T_expected_batch[3][2]=32'd3;
        T_expected_batch[3][3]=32'd99; T_expected_batch[3][4]=32'd42;

        B_coeff_batch[4][0]=1; B_coeff_batch[4][1]=-1; B_coeff_batch[4][2]=-1; B_coeff_batch[4][3]=1; B_coeff_batch[4][4]=0;
        D_coeff_batch[4][0]=32'h3EB13B90; D_coeff_batch[4][1]=32'h8B9D2434; D_coeff_batch[4][2]=32'h972A8469; D_coeff_batch[4][3]=32'h0822E8F3; D_coeff_batch[4][4]=32'h17FC695A;
        T_expected_batch[4][0]=32'hB5BC6DAC; T_expected_batch[4][1]=32'h3D12683D;
        T_expected_batch[4][2]=32'hE4D88DFF; T_expected_batch[4][3]=32'h240C7BE6; T_expected_batch[4][4]=32'h044C2032;

        run_batch_test("Streaming 5 Polys NTRU", 1'b1);

        // =====================================================================
        // Extension 5: Fault injection tests
        // Test 1: flip parity bit of coeff 0 (hreg[0] bit 2, fi_pos=2)
        //         hreg[i][2] = d[1] (copy of MSB of data) -- flipping breaks parity
        // Test 2: flip data bit of coeff 3 (hreg[3] bit 0, fi_pos=12)
        //         changes the ternary value -> parity check fails
        // Test 3: flip data bit of last valid coeff (coeff 4, hreg[4] bit 1, fi_pos=17)
        // =====================================================================
        B_coeff_batch[0][0]=1; B_coeff_batch[0][1]=-1; B_coeff_batch[0][2]=0; B_coeff_batch[0][3]=1; B_coeff_batch[0][4]=0;
        D_coeff_batch[0][0]=32'd5; D_coeff_batch[0][1]=32'd3; D_coeff_batch[0][2]=32'd7; D_coeff_batch[0][3]=32'd2; D_coeff_batch[0][4]=32'd8;

        run_fault_injection_test("FI coeff0 parity bit  (fi_pos=2)",  1'b0, 5'd2);
        run_fault_injection_test("FI coeff3 data bit0   (fi_pos=12)", 1'b0, 5'd12);
        run_fault_injection_test("FI coeff4 data bit1   (fi_pos=17)", 1'b0, 5'd17);

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n============================================================");
        $display("FINAL RESULTS");
        $display("  Total PASS: %0d", total_pass);
        $display("  Total FAIL: %0d", total_fail);
        if (total_fail == 0)
            $display("  *** ALL TESTS PASSED — Extensions 3+5 verified! ***");
        else
            $display("  *** FAILURES DETECTED — check waveform in GTKWave ***");
        $display("============================================================\n");

        $finish;
    end

endmodule
