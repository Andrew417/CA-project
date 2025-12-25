# 1. Create the library if it doesn't exist
if {[file exists work] == 0} {
    vlib work
}

# 2. Compile the design and testbench
#    Suppresses 'warning: always block has no event control' if present (optional)
vlog -reportprogress 300 -work work design.v
vlog -reportprogress 300 -work work tb_cache_system.v

# 3. Load the simulation
#    -voptargs=+acc is CRITICAL: it prevents optimization from hiding 
#    internal signals like the Controller State machine.
vsim -voptargs=+acc work.tb_cache_system

# 4. Load the waveform configuration
do wave.do

# 5. Run the simulation to completion
run -all

# 6. Zoom to fit the entire simulation
wave zoom full