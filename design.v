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
/*************************************************
 * SIMPLE CACHE CONTROLLER (Verilog-2001)
 * - Works with your exact ram + cache modules
 * - 1-word line cache (DATA_WIDTH bits)
 *
 * CPU protocol:
 *  - cpuRead or cpuWrite asserted for a request
 *  - Controller deasserts ready while busy
 *  - CPU should hold addr/writeData stable until ready==1 and done pulses
 *
 * Mandatory:
 *  - write-through supported (default WRITE_BACK=0)
 *
 * Bonus:
 *  - LRU replacement (uses cache victimWay + lruAccess updates)
 *  - write-back supported when WRITE_BACK=1
 *************************************************/
module cache_controller #(
    parameter integer ADDR_WIDTH   = 16,
    parameter integer DATA_WIDTH   = 32,
    parameter integer NUM_SETS     = 64,
    parameter integer NUM_WAYS     = 4,

    // Pure Verilog: provide these explicitly
    parameter integer SET_INDEX_W  = 6,   // log2(NUM_SETS)
    parameter integer WAY_INDEX_W  = 2,   // log2(NUM_WAYS)

    // Address split:
    // word addressing: OFFSET_W=0, TAG_WIDTH=ADDR_WIDTH-SET_INDEX_W
    // byte addressing (32-bit word): OFFSET_W=2, TAG_WIDTH=ADDR_WIDTH-SET_INDEX_W-2
    parameter integer OFFSET_W     = 0,
    parameter integer TAG_WIDTH    = 10,

    // 0 = write-through (MANDATORY behavior)
    // 1 = write-back (BONUS behavior)
    parameter integer WRITE_BACK   = 0
)(
    input  wire                   clk,
    input  wire                   rst,

    // ===== CPU Interface =====
    input  wire                   cpuRead,
    input  wire                   cpuWrite,
    input  wire [ADDR_WIDTH-1:0]  cpuAddr,
    input  wire [DATA_WIDTH-1:0]  cpuWriteData,
    output reg  [DATA_WIDTH-1:0]  cpuReadData,
    output reg                    done,
    output wire                   ready,

    // ===== Cache Interface =====
    output reg  [SET_INDEX_W-1:0] rdSet,
    input  wire [NUM_WAYS*TAG_WIDTH-1:0]   rdTags,
    input  wire [NUM_WAYS*DATA_WIDTH-1:0]  rdData,
    input  wire [NUM_WAYS-1:0]             rdValid,
    input  wire [NUM_WAYS-1:0]             rdDirty,

    output reg                    lineWriteEn,
    output reg  [SET_INDEX_W-1:0] lineWriteSet,
    output reg  [WAY_INDEX_W-1:0] lineWriteWay,
    output reg  [TAG_WIDTH-1:0]   lineWriteTag,
    output reg  [DATA_WIDTH-1:0]  lineWriteData,
    output reg                    lineWriteValid,
    output reg                    lineWriteDirty,

    output reg                    lruAccessEn,
    output reg  [SET_INDEX_W-1:0] lruAccessSet,
    output reg  [WAY_INDEX_W-1:0] lruAccessWay,

    output reg  [SET_INDEX_W-1:0] victimSet,
    input  wire [WAY_INDEX_W-1:0] victimWay,

    // ===== RAM Interface =====
    output reg                    ramWriteEnable,
    output reg                    ramReadEnable,
    output reg  [ADDR_WIDTH-1:0]  ramAddr,
    output reg  [DATA_WIDTH-1:0]  ramWriteData,
    input  wire [DATA_WIDTH-1:0]  ramReadData
);

    // ---------------------------------------------
    // FSM states
    // ---------------------------------------------
    localparam S_IDLE   = 3'd0;
    localparam S_LOOKUP = 3'd1;
    localparam S_WB     = 3'd2;
    localparam S_RAMRD  = 3'd3;
    localparam S_FILL   = 3'd4;

    reg [2:0] state, next_state;

    assign ready = (state == S_IDLE);

    // ---------------------------------------------
    // Latched request
    // ---------------------------------------------
    reg [ADDR_WIDTH-1:0] reqAddr;
    reg [DATA_WIDTH-1:0] reqWdata;
    reg                  reqRe, reqWe;

    wire [SET_INDEX_W-1:0] reqSet = reqAddr[OFFSET_W + SET_INDEX_W - 1 : OFFSET_W];
    wire [TAG_WIDTH-1:0]   reqTag = reqAddr[ADDR_WIDTH-1 : OFFSET_W + SET_INDEX_W];

    // ---------------------------------------------
    // Helpers: indexed part-select (Verilog-2001)
    // ---------------------------------------------
    function [TAG_WIDTH-1:0] GET_TAG_I;
        input integer wi;
        begin
            GET_TAG_I = rdTags[wi*TAG_WIDTH +: TAG_WIDTH];
        end
    endfunction

    function [DATA_WIDTH-1:0] GET_DATA_I;
        input integer wi;
        begin
            GET_DATA_I = rdData[wi*DATA_WIDTH +: DATA_WIDTH];
        end
    endfunction

    // ---------------------------------------------
    // Hit detect + invalid-first replacement
    // ---------------------------------------------
    integer i;

    reg hit;
    reg [WAY_INDEX_W-1:0] hitWay;
    reg [DATA_WIDTH-1:0]  hitData;

    reg foundInvalid;
    reg [WAY_INDEX_W-1:0] invalidWay;

    reg [WAY_INDEX_W-1:0] replWay_c;   // combinational replacement way

    always @(*) begin
        hit          = 1'b0;
        hitWay       = {WAY_INDEX_W{1'b0}};
        hitData      = {DATA_WIDTH{1'b0}};
        foundInvalid = 1'b0;
        invalidWay   = {WAY_INDEX_W{1'b0}};

        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (!foundInvalid && !rdValid[i]) begin
                foundInvalid = 1'b1;
                invalidWay   = i[WAY_INDEX_W-1:0];
            end

            if (rdValid[i] && (GET_TAG_I(i) == reqTag)) begin
                hit     = 1'b1;
                hitWay  = i[WAY_INDEX_W-1:0];
                hitData = GET_DATA_I(i);
            end
        end

        replWay_c = foundInvalid ? invalidWay : victimWay; // invalid-first else LRU victim
    end

    // *** FIX: combinational WB need based on current victim choice ***
    wire victim_need_wb;
    assign victim_need_wb = (WRITE_BACK != 0) && rdValid[replWay_c] && rdDirty[replWay_c];

    // ---------------------------------------------
    // Victim snapshot regs for write-back path
    // ---------------------------------------------
    reg [WAY_INDEX_W-1:0] replWay_r;
    reg                   victimValid_r, victimDirty_r;
    reg [TAG_WIDTH-1:0]    victimTag_r;
    reg [DATA_WIDTH-1:0]   victimData_r;

    wire [ADDR_WIDTH-1:0] victimAddr = { victimTag_r, reqSet, {OFFSET_W{1'b0}} };

    // ---------------------------------------------
    // Next-state logic
    // ---------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (cpuRead || cpuWrite)
                    next_state = S_LOOKUP;
            end

            S_LOOKUP: begin
                if (hit) begin
                    next_state = S_IDLE;
                end else begin
                    // *** FIX: use victim_need_wb (current) instead of victim*_r (stale) ***
                    if (victim_need_wb)
                        next_state = S_WB;
                    else if (reqRe)
                        next_state = S_RAMRD;
                    else
                        next_state = S_FILL; // write miss allocate
                end
            end

            S_WB: begin
                if (reqRe) next_state = S_RAMRD;
                else       next_state = S_FILL;
            end

            S_RAMRD: begin
                next_state = S_FILL; // RAM data available next clock
            end

            S_FILL: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ---------------------------------------------
    // OUTPUTS: single-driver combinational block
    // ---------------------------------------------
    always @(*) begin
        // defaults
        rdSet           = reqSet;
        victimSet       = reqSet;

        lineWriteEn     = 1'b0;
        lineWriteSet    = reqSet;
        lineWriteWay    = replWay_r;
        lineWriteTag    = reqTag;
        lineWriteData   = {DATA_WIDTH{1'b0}};
        lineWriteValid  = 1'b1;
        lineWriteDirty  = 1'b0;

        lruAccessEn     = 1'b0;
        lruAccessSet    = reqSet;
        lruAccessWay    = replWay_r;

        ramWriteEnable  = 1'b0;
        ramReadEnable   = 1'b0;
        ramAddr         = reqAddr;
        ramWriteData    = reqWdata;

        case (state)
            S_LOOKUP: begin
                if (hit) begin
                    // LRU update on hit
                    lruAccessEn  = 1'b1;
                    lruAccessWay = hitWay;

                    if (reqWe) begin
                        // Update cache line on write hit
                        lineWriteEn    = 1'b1;
                        lineWriteSet   = reqSet;
                        lineWriteWay   = hitWay;
                        lineWriteTag   = reqTag;
                        lineWriteData  = reqWdata;
                        lineWriteValid = 1'b1;
                        lineWriteDirty = (WRITE_BACK ? 1'b1 : 1'b0);

                        // Mandatory write-through when not write-back
                        if (!WRITE_BACK) begin
                            ramWriteEnable = 1'b1;
                            ramAddr        = reqAddr;
                            ramWriteData   = reqWdata;
                        end
                    end
                end
            end

            S_WB: begin
                // Write back dirty victim line
                ramWriteEnable = 1'b1;
                ramAddr        = victimAddr;
                ramWriteData   = victimData_r;
            end

            S_RAMRD: begin
                // Start RAM read for missed address
                ramReadEnable  = 1'b1;
                ramAddr        = reqAddr;
            end

            S_FILL: begin
                // Fill cache on miss (from RAM on read miss, or from CPU data on write miss)
                lineWriteEn    = 1'b1;
                lineWriteSet   = reqSet;
                lineWriteWay   = replWay_r;
                lineWriteTag   = reqTag;
                lineWriteValid = 1'b1;

                if (reqRe) begin
                    lineWriteData  = ramReadData;
                    lineWriteDirty = 1'b0;
                end else begin
                    lineWriteData  = reqWdata;
                    lineWriteDirty = (WRITE_BACK ? 1'b1 : 1'b0);

                    // write-through on write miss if not write-back
                    if (!WRITE_BACK) begin
                        ramWriteEnable = 1'b1;
                        ramAddr        = reqAddr;
                        ramWriteData   = reqWdata;
                    end
                end

                // LRU update on fill
                lruAccessEn  = 1'b1;
                lruAccessWay = replWay_r;
            end
        endcase
    end

    // ---------------------------------------------
    // SEQUENTIAL: state + latching + done/data
    // ---------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;

            reqAddr  <= {ADDR_WIDTH{1'b0}};
            reqWdata <= {DATA_WIDTH{1'b0}};
            reqRe    <= 1'b0;
            reqWe    <= 1'b0;

            replWay_r      <= {WAY_INDEX_W{1'b0}};
            victimValid_r  <= 1'b0;
            victimDirty_r  <= 1'b0;
            victimTag_r    <= {TAG_WIDTH{1'b0}};
            victimData_r   <= {DATA_WIDTH{1'b0}};

            cpuReadData <= {DATA_WIDTH{1'b0}};
            done        <= 1'b0;
        end else begin
            state <= next_state;
            done  <= 1'b0; // pulse

            // Accept new request only in IDLE
            if (state == S_IDLE) begin
                if (cpuRead || cpuWrite) begin
                    reqAddr  <= cpuAddr;
                    reqWdata <= cpuWriteData;
                    reqRe    <= cpuRead;
                    reqWe    <= cpuWrite;
                end
            end

            // In LOOKUP on miss: snapshot replacement choice and victim line for WB
            if (state == S_LOOKUP && !hit) begin
                replWay_r     <= replWay_c;

                victimValid_r <= rdValid[replWay_c];
                victimDirty_r <= rdDirty[replWay_c];
                victimTag_r   <= rdTags[replWay_c*TAG_WIDTH +: TAG_WIDTH];
                victimData_r  <= rdData[replWay_c*DATA_WIDTH +: DATA_WIDTH];
            end

            // Complete on hit in LOOKUP
            if (state == S_LOOKUP && hit) begin
                if (reqRe) cpuReadData <= hitData;
                done <= 1'b1;
            end

            // Complete on fill (miss path)
            if (state == S_FILL) begin
                if (reqRe) cpuReadData <= ramReadData;
                done <= 1'b1;
            end
        end
    end

endmodule