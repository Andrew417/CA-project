module main_memory #(
    // Parameters set to defaults based on the table in 
    parameter DATA_WIDTH = 32,      // Width of data bus
    parameter ADDR_WIDTH = 16       // Width of address bus
)(
    input wire clk,                 // Clock signal for synchronous operations 
    input wire we,                  // Write Enable signal 
    input wire re,                  // Read Enable signal 
    input wire [ADDR_WIDTH-1:0] addr, // Address input
    input wire [DATA_WIDTH-1:0] wdata, // Write data input
    output reg [DATA_WIDTH-1:0] rdata  // Read data output
);

    // Calculate memory depth based on address width (2^ADDR_WIDTH)
    localparam MEM_DEPTH = 1 << ADDR_WIDTH;

    // Declare the memory array
    reg [DATA_WIDTH-1:0] ram_block [0:MEM_DEPTH-1];

    // Synchronous Read and Write Logic 
    always @(posedge clk) begin
        // Write Operation controlled by Write Enable 
        if (we) begin
            ram_block[addr] <= wdata;
        end
        
        // Read Operation controlled by Read Enable 
        if (re) begin
            rdata <= ram_block[addr];
        end
    end

endmodule

//======================================================
// Parameterized Synchronous RAM
// - Synchronous write: on posedge clk when we=1
// - Synchronous read : dout updates on posedge clk when re=1
// - Fully parameterized address/data width
//======================================================
module ram_sync #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    // Default depth matches full address range
    parameter DEPTH      = (1 << ADDR_WIDTH)
)(
    input                      clk,
    input                      rst,      // optional reset behavior (see notes)
    input                      re,       // read enable
    input                      we,       // write enable
    input      [ADDR_WIDTH-1:0] addr,
    input      [DATA_WIDTH-1:0] din,
    output reg [DATA_WIDTH-1:0] dout
);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    integer i;

    // Optional: initialize memory to 0 for simulation cleanliness
    // (Not required for synthesis; many tools ignore this for hardware)
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
        dout = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (rst) begin
            // Optional reset: clears output register only
            // (Clearing full mem here is usually not synthesizable for large RAMs)
            dout <= {DATA_WIDTH{1'b0}};
        end else begin
            // WRITE (synchronous)
            if (we) begin
                mem[addr] <= din;
            end

            // READ (synchronous)
            if (re) begin
                // If re and we are both 1 on same address in same cycle,
                // this returns the "old" data in many synth RAMs (read-first).
                // If you want write-first behavior, we can modify this.
                dout <= mem[addr];
            end
        end
    end

endmodule