iverilog -o mac_timing mac_tb.v mac.v
vvp mac_timing
gtkwave mac_timing.vcd
