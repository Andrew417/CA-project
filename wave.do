onerror {resume}
quietly WaveActivateNextPane {} 0

# ==========================================
# SYSTEM CLOCK & RESET
# ==========================================
add wave -noupdate -divider "System"
add wave -noupdate -color Gray70 /tb_cache_system/clk
add wave -noupdate -color Red /tb_cache_system/rst

# ==========================================
# CPU INTERFACE (Inputs/Outputs)
# ==========================================
add wave -noupdate -divider "CPU Interface"
add wave -noupdate -color Gold /tb_cache_system/cpuRead
add wave -noupdate -color Gold /tb_cache_system/cpuWrite
add wave -noupdate -color {Cornflower Blue} /tb_cache_system/ready
add wave -noupdate -color Green /tb_cache_system/done
add wave -noupdate -radix hexadecimal /tb_cache_system/cpuAddr
add wave -noupdate -radix hexadecimal /tb_cache_system/cpuWriteData
add wave -noupdate -radix hexadecimal -color Cyan /tb_cache_system/cpuReadData

# ==========================================
# DEBUG HELPERS (New Signals)
# ==========================================
add wave -noupdate -divider "Expected Data"
add wave -noupdate -radix hexadecimal -color Magenta /tb_cache_system/rdata_expected

# ==========================================
# CONTROLLER INTERNALS (FSM & Logic)
# ==========================================
add wave -noupdate -divider "Controller State"
# 0:IDLE, 1:LOOKUP, 2:WB, 3:RAMRD, 4:FILL
add wave -noupdate -radix unsigned /tb_cache_system/dut/ctrl_inst/state
add wave -noupdate -radix unsigned /tb_cache_system/dut/ctrl_inst/next_state
add wave -noupdate -color Magenta /tb_cache_system/dut/ctrl_inst/hit
add wave -noupdate /tb_cache_system/dut/ctrl_inst/victim_need_wb
add wave -noupdate -radix hexadecimal /tb_cache_system/dut/ctrl_inst/reqAddr

# ==========================================
# CACHE & RAM INTERFACE
# ==========================================
add wave -noupdate -divider "Cache Internals"
add wave -noupdate -radix unsigned /tb_cache_system/dut/rdSet
add wave -noupdate -radix hexadecimal /tb_cache_system/dut/rdTags
add wave -noupdate /tb_cache_system/dut/rdValid
add wave -noupdate /tb_cache_system/dut/rdDirty

add wave -noupdate -divider "RAM Interface"
add wave -noupdate /tb_cache_system/dut/ram_inst/writeEnable
add wave -noupdate /tb_cache_system/dut/ram_inst/readEnable
add wave -noupdate -radix hexadecimal /tb_cache_system/dut/ram_inst/addr
add wave -noupdate -radix hexadecimal /tb_cache_system/dut/ram_inst/writeData
add wave -noupdate -radix hexadecimal /tb_cache_system/dut/ram_inst/readData

# ==========================================
# TESTBENCH STATS
# ==========================================
add wave -noupdate -divider "TB Stats"
add wave -noupdate -radix unsigned /tb_cache_system/test_num
add wave -noupdate -radix unsigned -color Red /tb_cache_system/error_count
add wave -noupdate -radix unsigned -color Green /tb_cache_system/correct_count

# ==========================================
# VIEW CONFIGURATION
# ==========================================
# This section makes the waves readable by removing full paths
# and setting column widths.
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 220
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {1000 ns}