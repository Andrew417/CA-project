onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -color Gray90 /tb_cache_system/clk
add wave -noupdate -divider {control signals}
add wave -noupdate /tb_cache_system/rd
add wave -noupdate /tb_cache_system/wr
add wave -noupdate -divider address
add wave -noupdate /tb_cache_system/addr
add wave -noupdate -divider data
add wave -noupdate /tb_cache_system/wdata
add wave -noupdate /tb_cache_system/rdata
add wave -noupdate -color Magenta /tb_cache_system/rdata_expected
add wave -noupdate -divider counters
add wave -noupdate -color Pink /tb_cache_system/error_count
add wave -noupdate -color Pink /tb_cache_system/correct_count
add wave -noupdate -color Pink /tb_cache_system/test_num
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {375 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {17850 ps}
