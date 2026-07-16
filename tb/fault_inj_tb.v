`timescale 1ns/1ps

module fault_inj_tb;
    // Local parameters to clean up dynamic math expressions
    localparam N = 8;
    localparam ADDR_WIDTH = $clog2((5+4-1)/4);

    // Clock and reset
    reg clk = 0;
    reg rst_n = 0;

    // Fault‑injection signals
    reg fi_en = 0;
    reg [7:0] fi_pos = 0; // enough bits for 4*N (N=8 → 32 bits)

    // Top‑level ports we need to drive / monitor
    wire error_flag;
    
    // Minimal connections for the other ports – tie them low / unused
    reg start = 0;
    reg mode  = 0;
    reg [15:0] batch_size = 16'd1;
    reg [31:0] d_in = 32'd0;
    reg d_load = 0;
    reg [ADDR_WIDTH-1:0] d_wr_addr = 0;
    reg [2*N-1:0] b_in = 16'd0; // N=8 → 2N bits

    // Instantiate the design under test
    scales_top dut (
        .clk(clk),
        .rst_n(rst_n),         // Corrected port name assignment to match rst_n wire
        .start(start),
        .mode(mode),
        .batch_size(batch_size),
        .d_in(d_in),
        .d_load(d_load),
        .d_wr_addr(d_wr_addr),
        .b_in(b_in),
        .fi_en(fi_en),
        .fi_pos(fi_pos),
        .error_flag(error_flag),
        // Unused outputs – left unconnected
        .out_valid(), 
        .T_out(), 
        .done(), 
        .row_sel(), 
        .batch_cnt(), 
        .bank_sel(), 
        .d_load_next()
    );

    // Clock generation – 100 MHz
    always #5 clk = ~clk;

    initial begin
        // VCD dump for waveform capture
        $dumpfile("fault_inj.vcd");
        $dumpvars(0, fault_inj_tb);

        // Reset sequence
        rst_n = 0;
        #20;
        rst_n = 1;

        // Let the design idle a few cycles
        repeat (10) @(posedge clk);

        // Inject a single‑bit fault (flip LSB of first Hamming word)
        fi_pos = 8'd0;        // selects bit 0 of the flattened 4*N vector
        fi_en  = 1'b1;
        @(posedge clk);
        fi_en  = 1'b0;
        fi_pos = 8'd0;        // de‑assert position

        // Observe the error flag for a few cycles
        repeat (10) @(posedge clk);

        $display("--- Simulation finished ---\n time=%0t  error_flag=%b", $time, error_flag);
        $finish;
    end
endmodule