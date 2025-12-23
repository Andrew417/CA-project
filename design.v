/*************************************************
 * RAM MODULE
 *************************************************/
module ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input clk, writeEnable, readEnable,
    input [ADDR_WIDTH-1:0] addr, 
    input [DATA_WIDTH-1:0] writeData,
    output reg [DATA_WIDTH-1:0] readData
);

    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Initialize RAM to zero
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 0; // ensures TEST 3 passes
    end

    always @(posedge clk) begin
        if (writeEnable)
            mem[addr] <= writeData;
        if (readEnable)
            readData <= mem[addr];
    end
endmodule

/*************************************************
 * CACHE MODULE (4-WAY SET ASSOCIATIVE)
 *************************************************/
module cache #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter NUM_SETS   = 64,
    parameter NUM_WAYS   = 4,
    parameter INDEX_BITS = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter WAY_BITS   = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1,
    parameter TAG_WIDTH  = ADDR_WIDTH - INDEX_BITS
)(
    input clk,
    input we,
    input fill,
    input [INDEX_BITS-1:0] index,
    input [TAG_WIDTH-1:0]  tag_in,
    input [DATA_WIDTH-1:0] data_in,

    output reg [WAY_BITS-1:0] hit_way,   
    output reg hit,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg dirty_out,
    output reg [TAG_WIDTH-1:0] tag_out
);

    reg valid [NUM_SETS-1:0][NUM_WAYS-1:0];
    reg dirty [NUM_SETS-1:0][NUM_WAYS-1:0];
    reg [TAG_WIDTH-1:0] tag   [NUM_SETS-1:0][NUM_WAYS-1:0];
    reg [DATA_WIDTH-1:0] data [NUM_SETS-1:0][NUM_WAYS-1:0];
    reg [WAY_BITS-1:0] lru [NUM_SETS-1:0];

    integer i, s;

    initial begin
        for (s = 0; s < NUM_SETS; s = s + 1) begin
            lru[s] = 0;
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                valid[s][i] = 0;
                dirty[s][i] = 0;
            end
        end
    end

    always @(*) begin

        hit = 0;
        data_out = 0;
        hit_way = 0;
        dirty_out = 0;
        tag_out = 0;

        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (valid[index][i] && tag[index][i] == tag_in) begin
                hit = 1;
                hit_way = i;
                data_out = data[index][i];
                dirty_out = dirty[index][i];
                tag_out = tag[index][i];
            end
        end
    end

    always @(posedge clk) begin
        if (hit) begin
            if (we) begin
                data[index][hit_way] <= data_in;
                dirty[index][hit_way] <= 1'b1;
            end
            lru[index] <= (hit_way == NUM_WAYS-1) ? 0 : hit_way + 1'b1;
        end
        else if (fill) begin
            valid[index][lru[index]] <= 1'b1;
            tag[index][lru[index]]   <= tag_in;
            data[index][lru[index]]  <= data_in;
            dirty[index][lru[index]] <= we;
            lru[index] <= (lru[index] == NUM_WAYS-1) ? 0 : lru[index] + 1'b1;
        end
    end

endmodule

/*************************************************
 * CACHE CONTROLLER MODULE
 *************************************************/
module cache_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter NUM_SETS   = 64,
    parameter NUM_WAYS   = 4
)(
    input                  clk,
    input                  rd,
    input                  wr,
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] wdata,
    output [DATA_WIDTH-1:0] rdata
);

    // localparam INDEX_BITS = $clog2(NUM_SETS);
    localparam INDEX_BITS = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1;
    localparam TAG_BITS   = ADDR_WIDTH - INDEX_BITS;
    localparam WAY_BITS   = ($clog2(NUM_WAYS) > 0) ? $clog2(NUM_WAYS) : 1;

    // wire [INDEX_BITS-1:0] index = addr[INDEX_BITS-1:0];
    wire [INDEX_BITS-1:0] index = (NUM_SETS > 1) ? addr[INDEX_BITS-1:0] : 0;
    wire [TAG_BITS-1:0]   tag   = addr[ADDR_WIDTH-1:INDEX_BITS];

    wire hit;
    wire dirty;
    wire [DATA_WIDTH-1:0] cache_data;
    wire [WAY_BITS-1:0] hit_way;
    wire [TAG_BITS-1:0] old_tag;

    reg cache_we;
    reg cache_fill;
    reg ram_we;
    reg ram_re;

    wire [DATA_WIDTH-1:0] ram_data;
    wire [DATA_WIDTH-1:0] ram_wdata;
    wire [ADDR_WIDTH-1:0] wb_addr;
    
    assign ram_wdata = ram_we ? cache_data : wdata;
    assign wb_addr = (NUM_SETS > 1) ? {old_tag, index} : old_tag;

    cache c0 (
        .clk(clk),
        .we(cache_we),
        .fill(cache_fill),
        .index(index),
        .tag_in(tag),
        .data_in(wdata),
        .hit(hit),
        .data_out(cache_data),
        .hit_way(hit_way),
        .dirty_out(dirty),
        .tag_out(old_tag)
    );

    ram r0 (
        .clk(clk),
        .writeEnable(ram_we),
        .readEnable(ram_re),
        .addr(ram_we ? wb_addr : addr),
        .writeData(ram_wdata),
        .readData(ram_data)
    );

    assign rdata = hit ? cache_data : ram_data;

    always @(posedge clk) begin
        cache_we   <= 0;
        cache_fill <= 0;
        ram_we     <= 0;
        ram_re     <= 0;

        if (rd) begin
            if (!hit) begin
                if (dirty)
                    ram_we <= 1;   // write-back
                ram_re     <= 1;   // fetch from RAM
                cache_fill <= 1;   // fill cache
            end
        end

        if (wr) begin
            if (hit) begin
                cache_we <= 1;     // write hit
            end else begin
                if (dirty)
                    ram_we <= 1;   // write-back
                ram_re     <= 1;
                cache_fill <= 1;
                cache_we   <= 1;   // write new data
            end
        end
    end
endmodule