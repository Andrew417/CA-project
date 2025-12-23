vlib work
vlog design.v tb_cache_system.v
vsim -voptargs=+acc work.tb_cache_system
do wave.do
run -all
#quit -sim