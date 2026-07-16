# =====================================================================
# SCALES Extended — Basys 3 Constraints
# Board:  Digilent Basys 3 (xc7a35tcpg236-1)
# Clock:  100 MHz onboard oscillator -> W5
# =====================================================================
# Extensions implemented:
#   Ext 3: Multi-poly batching (batch_size, d_load_next, bank_sel)
#   Ext 5: Fault-tolerant B-REG (error_flag, fi_en, fi_pos)
#   Ext 7: Dual-mode BFV/NTRU (mode)
# =====================================================================

# =====================================================================
# 1. PRIMARY CLOCK
# =====================================================================
create_clock -period 9.000 -name clk [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk]

# =====================================================================
# 2. PIN ASSIGNMENTS
# =====================================================================

# --- Clock ---
set_property PACKAGE_PIN W5  [get_ports clk]

# --- Buttons (active high on Basys 3) ---
# BTNC = reset
# BTNU = start
set_property PACKAGE_PIN V17 [get_ports rst]
set_property PACKAGE_PIN T18 [get_ports start]

# --- Switches ---
# SW0 = mode    (0=BFV, 1=NTRU)
# SW1 = fi_en   (fault injection enable, Extension 5)
# SW2-SW6 = fi_pos[4:0] (which bit to flip in b_reg hreg)
# SW7-SW9 = cfg_v[2:0]  (active V slots, Extension 2 if used)
# SW10-SW14 = cfg_u[4:0] (active U lanes, Extension 2 if used)
# SW15 = batch_size LSB (just for demo — tie rest to 0 internally)
set_property PACKAGE_PIN W14 [get_ports mode]
set_property PACKAGE_PIN V2  [get_ports fi_en]
set_property PACKAGE_PIN T3  [get_ports {fi_pos[0]}]
set_property PACKAGE_PIN T2  [get_ports {fi_pos[1]}]
set_property PACKAGE_PIN R3  [get_ports {fi_pos[2]}]
set_property PACKAGE_PIN W2  [get_ports {fi_pos[3]}]
set_property PACKAGE_PIN U1  [get_ports {fi_pos[4]}]

# --- LEDs ---
# LD0 = done
# LD1 = out_valid
# LD2 = error_flag  (Extension 5 — lights up on B-REG corruption)
# LD3 = bank_sel    (Extension 3 — shows which D-RAM bank is active)
# LD4 = d_load_next (Extension 3 — pulses when next D is needed)
set_property PACKAGE_PIN U16 [get_ports done]
set_property PACKAGE_PIN E19 [get_ports out_valid]
set_property PACKAGE_PIN U19 [get_ports error_flag]
set_property PACKAGE_PIN V19 [get_ports bank_sel]
set_property PACKAGE_PIN W18 [get_ports d_load_next]

# =====================================================================
# 3. IOSTANDARD
# =====================================================================
# Basys 3 uses 3.3V LVCMOS on all user I/O

set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports start]
set_property IOSTANDARD LVCMOS33 [get_ports mode]
set_property IOSTANDARD LVCMOS33 [get_ports fi_en]
set_property IOSTANDARD LVCMOS33 [get_ports {fi_pos[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports done]
set_property IOSTANDARD LVCMOS33 [get_ports out_valid]
set_property IOSTANDARD LVCMOS33 [get_ports error_flag]
set_property IOSTANDARD LVCMOS33 [get_ports bank_sel]
set_property IOSTANDARD LVCMOS33 [get_ports d_load_next]

# =====================================================================
# 4. INPUT / OUTPUT DELAYS
# =====================================================================
set_input_delay -clock clk -max 4.000 [get_ports rst]
set_input_delay -clock clk -min 3.000 [get_ports rst]
set_input_delay -clock clk -max 4.000 [get_ports start]
set_input_delay -clock clk -min 3.000 [get_ports start]
set_input_delay -clock clk -max 4.000 [get_ports mode]
set_input_delay -clock clk -min 3.000 [get_ports mode]
set_input_delay -clock clk -max 4.000 [get_ports fi_en]
set_input_delay -clock clk -min 3.000 [get_ports fi_en]
set_input_delay -clock clk -max 4.000 [get_ports {fi_pos[*]}]
set_input_delay -clock clk -min 3.000 [get_ports {fi_pos[*]}]

set_output_delay -clock clk -max 1.000 [get_ports done]
set_output_delay -clock clk -min 0.000 [get_ports done]
set_output_delay -clock clk -max 1.000 [get_ports out_valid]
set_output_delay -clock clk -min 0.000 [get_ports out_valid]
set_output_delay -clock clk -max 1.000 [get_ports error_flag]
set_output_delay -clock clk -min 0.000 [get_ports error_flag]
set_output_delay -clock clk -max 1.000 [get_ports bank_sel]
set_output_delay -clock clk -min 0.000 [get_ports bank_sel]
set_output_delay -clock clk -max 1.000 [get_ports d_load_next]
set_output_delay -clock clk -min 0.000 [get_ports d_load_next]

# =====================================================================
# 5. IOB PLACEMENT
# =====================================================================
set_property IOB TRUE [get_ports rst]
set_property IOB TRUE [get_ports start]
set_property IOB TRUE [get_ports mode]
set_property IOB TRUE [get_ports fi_en]
set_property IOB TRUE [get_ports {fi_pos[*]}]
set_property IOB TRUE [get_ports done]
set_property IOB TRUE [get_ports out_valid]
set_property IOB TRUE [get_ports error_flag]
set_property IOB TRUE [get_ports bank_sel]
set_property IOB TRUE [get_ports d_load_next]

# =====================================================================
# 6. TIMING OVERRIDES
# =====================================================================
set_multicycle_path -setup -from [all_inputs]  2
set_multicycle_path -setup -to   [all_outputs] 2
set_multicycle_path -hold  -from [all_inputs]  1
set_multicycle_path -hold  -to   [all_outputs] 1

# =====================================================================
# 7. POWER AND METHODOLOGY
# =====================================================================
set_operating_conditions -grade commercial
set_switching_activity -default_toggle_rate 12.500
set_property CFGBVS      VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3      [current_design]
set_switching_activity -toggle_rate 12.500 -static_probability 0.500 [all_inputs]
set_switching_activity -toggle_rate 12.500 -static_probability 0.500 [all_outputs]

# =====================================================================
# NOTE: The wide internal buses (d_in, b_in, T_out, batch_size,
# d_wr_addr, row_sel) are NOT mapped to physical pins here because:
# 1. They are too wide for the available Basys 3 I/O
# 2. In a real system they would connect to a UART or AXI interface
# 3. For synthesis/timing analysis purposes Vivado will treat them
#    as internally driven — this is fine for area/timing reports
# =====================================================================
