/*************************************************
 * RAM MODULE
 *************************************************/
/*************************************************
 * RAM MODULE (Synchronous Read/Write, Parameterized)
 * - Synchronous write: on posedge clk when writeEnable=1
 * - Synchronous read : readData updates on posedge clk when readEnable=1
 *
 * Optional (NOT required by spec):
 * - rst input clears output register only
 * - initial block initializes memory to 0 for clean simulation
 *************************************************/
module ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input   clk,
    input   rst,          // OPTIONAL (not required)
    input   writeEnable,
    input   readEnable,
    input   [ADDR_WIDTH-1:0]  addr,
    input   [DATA_WIDTH-1:0]  writeData,
    output reg [DATA_WIDTH-1:0]  readData
);

    // Depth derived from address width (2^ADDR_WIDTH)
    localparam DEPTH = (1 << ADDR_WIDTH);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // OPTIONAL: Initialize RAM to zero (simulation convenience)
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_WIDTH{1'b0}};
        readData = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (rst) begin
            // OPTIONAL: reset output register only
            readData <= {DATA_WIDTH{1'b0}};
        end else begin
            if (writeEnable)
                mem[addr] <= writeData;

            if (readEnable)
                readData <= mem[addr]; // read-first if read & write same cycle
        end
    end

endmodule
/*************************************************
 * CACHE MODULE (Data + Tag Array + Metadata)
 *
 * Supports (via parameters):
 *  - Direct-mapped:        NUM_WAYS = 1
 *  - Fully-associative:    NUM_SETS = 1, NUM_WAYS = total lines
 *  - N-way set associative: any NUM_SETS >= 1, NUM_WAYS >= 1
 *
 * Mandatory (per project):
 *  - Parameterized NUM_SETS, NUM_WAYS, TAG_WIDTH, DATA_WIDTH
 *
 * Bonus-ready features INCLUDED (controller may use or ignore):
 *  - Dirty bit storage (for write-back technique)
 *  - True LRU metadata + victim selection (for replacement)
 *************************************************/
/*************************************************
 * CACHE MODULE (Verilog-2001 compatible)
 *************************************************/
module cache #(
    parameter integer NUM_SETS     = 64,
    parameter integer NUM_WAYS     = 4,
    parameter integer TAG_WIDTH    = 8,
    parameter integer DATA_WIDTH   = 32,

    // In pure Verilog, you must provide these (no $clog2)
    parameter integer SET_INDEX_W  = 6, // log2(NUM_SETS)
    parameter integer WAY_INDEX_W  = 2, // log2(NUM_WAYS)

    // BONUS toggles
    parameter integer USE_DIRTY    = 1,
    parameter integer USE_LRU      = 1
)(
    input  wire clk,
    input  wire rst,

    // Read view of one set
    input  wire [SET_INDEX_W-1:0] rdSet,
    output wire [NUM_WAYS*TAG_WIDTH-1:0]   rdTags,
    output wire [NUM_WAYS*DATA_WIDTH-1:0]  rdData,
    output wire [NUM_WAYS-1:0]             rdValid,
    output wire [NUM_WAYS-1:0]             rdDirty,

    // Write one way in one set
    input  wire                       lineWriteEn,
    input  wire [SET_INDEX_W-1:0]      lineWriteSet,
    input  wire [WAY_INDEX_W-1:0]      lineWriteWay,
    input  wire [TAG_WIDTH-1:0]        lineWriteTag,
    input  wire [DATA_WIDTH-1:0]       lineWriteData,
    input  wire                       lineWriteValid,
    input  wire                       lineWriteDirty,

    // LRU update
    input  wire                       lruAccessEn,
    input  wire [SET_INDEX_W-1:0]      lruAccessSet,
    input  wire [WAY_INDEX_W-1:0]      lruAccessWay,

    // Victim selection
    input  wire [SET_INDEX_W-1:0]      victimSet,
    output wire [WAY_INDEX_W-1:0]      victimWay
);

    // ---------- internal clog2 for LRU width only ----------
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam integer LRU_AGE_W = (NUM_WAYS <= 1) ? 1 : clog2(NUM_WAYS);
    localparam integer NUM_LINES = NUM_SETS * NUM_WAYS;

    function integer line_index;
        input integer set_i;
        input integer way_i;
        begin
            line_index = (set_i * NUM_WAYS) + way_i;
        end
    endfunction

    reg [TAG_WIDTH-1:0]    tag_mem     [0:NUM_LINES-1];
    reg [DATA_WIDTH-1:0]   data_mem    [0:NUM_LINES-1];
    reg                    valid_mem   [0:NUM_LINES-1];
    reg                    dirty_mem   [0:NUM_LINES-1];
    reg [LRU_AGE_W-1:0]    lru_age_mem [0:NUM_LINES-1];

    integer s, w;
    integer old_age;   // moved out of always block (Verilog-legal)

    // ---------- sequential: reset, writes, LRU updates ----------
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    valid_mem[line_index(s,w)]   <= 1'b0;
                    dirty_mem[line_index(s,w)]   <= 1'b0;
                    lru_age_mem[line_index(s,w)] <= w[LRU_AGE_W-1:0];
                    tag_mem[line_index(s,w)]     <= {TAG_WIDTH{1'b0}};
                    data_mem[line_index(s,w)]    <= {DATA_WIDTH{1'b0}};
                end
            end
        end else begin
            if (lineWriteEn) begin
                tag_mem  [line_index(lineWriteSet, lineWriteWay)] <= lineWriteTag;
                data_mem [line_index(lineWriteSet, lineWriteWay)] <= lineWriteData;
                valid_mem[line_index(lineWriteSet, lineWriteWay)] <= lineWriteValid;

                if (USE_DIRTY)
                    dirty_mem[line_index(lineWriteSet, lineWriteWay)] <= lineWriteDirty;
                else
                    dirty_mem[line_index(lineWriteSet, lineWriteWay)] <= 1'b0;
            end

            if (USE_LRU && lruAccessEn) begin
                old_age = lru_age_mem[line_index(lruAccessSet, lruAccessWay)];

                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    if (lruAccessWay == w[WAY_INDEX_W-1:0]) begin
                        lru_age_mem[line_index(lruAccessSet, w)] <= {LRU_AGE_W{1'b0}}; // MRU
                    end else begin
                        if (lru_age_mem[line_index(lruAccessSet, w)] < old_age[LRU_AGE_W-1:0])
                            lru_age_mem[line_index(lruAccessSet, w)] <= lru_age_mem[line_index(lruAccessSet, w)] + 1'b1;
                    end
                end
            end
        end
    end

    // ---------- combinational: expose whole set ----------
    genvar gw;
    generate
        for (gw = 0; gw < NUM_WAYS; gw = gw + 1) begin : GEN_RD
            assign rdTags[(gw+1)*TAG_WIDTH-1 : gw*TAG_WIDTH]   = tag_mem [(rdSet * NUM_WAYS) + gw];
            assign rdData[(gw+1)*DATA_WIDTH-1 : gw*DATA_WIDTH] = data_mem[(rdSet * NUM_WAYS) + gw];
            assign rdValid[gw] = valid_mem[(rdSet * NUM_WAYS) + gw];
            assign rdDirty[gw] = (USE_DIRTY) ? dirty_mem[(rdSet * NUM_WAYS) + gw] : 1'b0;
        end
    endgenerate

    // ---------- combinational: victim way from LRU ----------
    reg [WAY_INDEX_W-1:0] victimWay_r;
    integer vw;
    integer best_age;

    always @(*) begin
        victimWay_r = {WAY_INDEX_W{1'b0}};

        if (USE_LRU) begin
            best_age = -1;
            for (vw = 0; vw < NUM_WAYS; vw = vw + 1) begin
                if (lru_age_mem[line_index(victimSet, vw)] > best_age) begin
                    best_age    = lru_age_mem[line_index(victimSet, vw)];
                    victimWay_r = vw[WAY_INDEX_W-1:0];
                end
            end
        end
    end

    assign victimWay = victimWay_r;

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