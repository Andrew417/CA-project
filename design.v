/*************************************************
 * RAM MODULE
 *************************************************/
module ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input   clk,
    input   rst,
    input   writeEnable,
    input   readEnable,
    input   [ADDR_WIDTH-1:0]  addr,
    input   [DATA_WIDTH-1:0]  writeData,
    output reg [DATA_WIDTH-1:0]  readData
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 0;
        readData = 0;
    end

    always @(posedge clk) begin
        if (rst) begin
            readData <= 0;
        end else begin
            if (writeEnable)
                mem[addr] <= writeData;
            if (readEnable)
                readData <= mem[addr];
        end
    end
endmodule

/*************************************************
 * CACHE MODULE
 *************************************************/
module cache #(
    parameter integer NUM_SETS     = 64,
    parameter integer NUM_WAYS     = 4,
    parameter integer TAG_WIDTH    = 8,
    parameter integer DATA_WIDTH   = 32,
    parameter integer SET_INDEX_W  = 6,
    parameter integer WAY_INDEX_W  = 2,
    parameter integer USE_DIRTY    = 1,
    parameter integer USE_LRU      = 1
)(
    input  wire clk,
    input  wire rst,
    // Read
    input  wire [SET_INDEX_W-1:0] rdSet,
    output wire [NUM_WAYS*TAG_WIDTH-1:0]   rdTags,
    output wire [NUM_WAYS*DATA_WIDTH-1:0]  rdData,
    output wire [NUM_WAYS-1:0]             rdValid,
    output wire [NUM_WAYS-1:0]             rdDirty,
    // Write
    input  wire                     lineWriteEn,
    input  wire [SET_INDEX_W-1:0]   lineWriteSet,
    input  wire [WAY_INDEX_W-1:0]   lineWriteWay,
    input  wire [TAG_WIDTH-1:0]     lineWriteTag,
    input  wire [DATA_WIDTH-1:0]    lineWriteData,
    input  wire                     lineWriteValid,
    input  wire                     lineWriteDirty,
    // LRU
    input  wire                     lruAccessEn,
    input  wire [SET_INDEX_W-1:0]   lruAccessSet,
    input  wire [WAY_INDEX_W-1:0]   lruAccessWay,
    // Victim
    input  wire [SET_INDEX_W-1:0]   victimSet,
    output wire [WAY_INDEX_W-1:0]   victimWay
);

    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1) v = v >> 1;
        end
    endfunction

    localparam integer LRU_AGE_W = (NUM_WAYS <= 1) ? 1 : clog2(NUM_WAYS);
    localparam integer NUM_LINES = NUM_SETS * NUM_WAYS;

    // Internal Memory
    reg [TAG_WIDTH-1:0]    tag_mem     [0:NUM_LINES-1];
    reg [DATA_WIDTH-1:0]   data_mem    [0:NUM_LINES-1];
    reg                    valid_mem   [0:NUM_LINES-1];
    reg                    dirty_mem   [0:NUM_LINES-1];
    reg [LRU_AGE_W-1:0]    lru_age_mem [0:NUM_LINES-1];

    // Helper for indexing
    function integer get_idx;
        input integer s_idx;
        input integer w_idx;
        begin
            get_idx = (s_idx * NUM_WAYS) + w_idx;
        end
    endfunction

    // --- SEQUENTIAL LOGIC ---
    integer s, w;
    integer old_age;
    integer wr_idx;
    integer lru_idx;

    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    valid_mem[get_idx(s,w)]   <= 1'b0;
                    dirty_mem[get_idx(s,w)]   <= 1'b0;
                    lru_age_mem[get_idx(s,w)] <= w[LRU_AGE_W-1:0];
                    tag_mem[get_idx(s,w)]     <= 0;
                    data_mem[get_idx(s,w)]    <= 0;
                end
            end
        end else begin
            // Write
            if (lineWriteEn) begin
                wr_idx = get_idx(lineWriteSet, lineWriteWay);
                tag_mem  [wr_idx] <= lineWriteTag;
                data_mem [wr_idx] <= lineWriteData;
                valid_mem[wr_idx] <= lineWriteValid;
                if (USE_DIRTY) dirty_mem[wr_idx] <= lineWriteDirty;
                else           dirty_mem[wr_idx] <= 1'b0;
            end

            // LRU Update
            if (USE_LRU && lruAccessEn) begin
                lru_idx = get_idx(lruAccessSet, lruAccessWay);
                old_age = lru_age_mem[lru_idx];
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    if (lruAccessWay == w[WAY_INDEX_W-1:0]) begin
                        lru_age_mem[get_idx(lruAccessSet, w)] <= 0; // MRU
                    end else begin
                        if (lru_age_mem[get_idx(lruAccessSet, w)] < old_age)
                            lru_age_mem[get_idx(lruAccessSet, w)] <= lru_age_mem[get_idx(lruAccessSet, w)] + 1;
                    end
                end
            end
        end
    end

    // --- COMBINATIONAL READ ---
    genvar gw;
    generate
        for (gw = 0; gw < NUM_WAYS; gw = gw + 1) begin : GEN_RD
            assign rdTags[(gw+1)*TAG_WIDTH-1 : gw*TAG_WIDTH]   = tag_mem [get_idx(rdSet, gw)];
            assign rdData[(gw+1)*DATA_WIDTH-1 : gw*DATA_WIDTH] = data_mem[get_idx(rdSet, gw)];
            assign rdValid[gw] = valid_mem[get_idx(rdSet, gw)];
            assign rdDirty[gw] = (USE_DIRTY) ? dirty_mem[get_idx(rdSet, gw)] : 1'b0;
        end
    endgenerate

    // --- VICTIM SELECTION ---
    reg [WAY_INDEX_W-1:0] victimWay_r;
    integer vw;
    integer best_age;
    always @(*) begin
        victimWay_r = 0;
        if (USE_LRU) begin
            best_age = -1;
            for (vw = 0; vw < NUM_WAYS; vw = vw + 1) begin
                if (lru_age_mem[get_idx(victimSet, vw)] > best_age) begin
                    best_age    = lru_age_mem[get_idx(victimSet, vw)];
                    victimWay_r = vw[WAY_INDEX_W-1:0];
                end
            end
        end
    end
    assign victimWay = victimWay_r;

endmodule

/*************************************************
 * CACHE CONTROLLER
 *************************************************/
module cache_controller #(
    parameter integer ADDR_WIDTH   = 16,
    parameter integer DATA_WIDTH   = 32,
    parameter integer NUM_SETS     = 64,
    parameter integer NUM_WAYS     = 4,
    parameter integer SET_INDEX_W  = 6,
    parameter integer WAY_INDEX_W  = 2,
    parameter integer OFFSET_W     = 0,
    parameter integer TAG_WIDTH    = 10,
    parameter integer WRITE_BACK   = 0
)(
    input  wire                   clk,
    input  wire                   rst,
    // CPU
    input  wire                   cpuRead,
    input  wire                   cpuWrite,
    input  wire [ADDR_WIDTH-1:0]  cpuAddr,
    input  wire [DATA_WIDTH-1:0]  cpuWriteData,
    output reg  [DATA_WIDTH-1:0]  cpuReadData,
    output reg                    done,
    output wire                   ready,
    // Cache
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
    // RAM
    output reg                    ramWriteEnable,
    output reg                    ramReadEnable,
    output reg  [ADDR_WIDTH-1:0]  ramAddr,
    output reg  [DATA_WIDTH-1:0]  ramWriteData,
    input  wire [DATA_WIDTH-1:0]  ramReadData
);

    localparam S_IDLE   = 3'd0;
    localparam S_LOOKUP = 3'd1;
    localparam S_WB     = 3'd2;
    localparam S_RAMRD  = 3'd3;
    localparam S_FILL   = 3'd4;

    reg [2:0] state, next_state;
    assign ready = (state == S_IDLE);

    reg [ADDR_WIDTH-1:0] reqAddr;
    reg [DATA_WIDTH-1:0] reqWdata;
    reg                  reqRe, reqWe;

    wire [SET_INDEX_W-1:0] reqSet = reqAddr[OFFSET_W + SET_INDEX_W - 1 : OFFSET_W];
    wire [TAG_WIDTH-1:0]   reqTag = reqAddr[ADDR_WIDTH-1 : OFFSET_W + SET_INDEX_W];

    // Helper functions
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

    // Hit Logic
    integer i;
    reg hit;
    reg [WAY_INDEX_W-1:0] hitWay;
    reg [DATA_WIDTH-1:0]  hitData;
    reg foundInvalid;
    reg [WAY_INDEX_W-1:0] invalidWay;
    reg [WAY_INDEX_W-1:0] replWay_c;

    always @(*) begin
        hit = 0;
        hitWay = 0;
        hitData = 0;
        foundInvalid = 0;
        invalidWay = 0;

        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            if (!foundInvalid && !rdValid[i]) begin
                foundInvalid = 1;
                invalidWay = i[WAY_INDEX_W-1:0];
            end
            if (rdValid[i] && (GET_TAG_I(i) == reqTag)) begin
                hit = 1;
                hitWay = i[WAY_INDEX_W-1:0];
                hitData = GET_DATA_I(i);
            end
        end
        replWay_c = foundInvalid ? invalidWay : victimWay;
    end

    wire victim_need_wb = (WRITE_BACK != 0) && rdValid[replWay_c] && rdDirty[replWay_c];

    // Snapshot regs
    reg [WAY_INDEX_W-1:0] replWay_r;
    reg [TAG_WIDTH-1:0]   victimTag_r;
    reg [DATA_WIDTH-1:0]  victimData_r;
    wire [ADDR_WIDTH-1:0] victimAddr = { victimTag_r, reqSet, {OFFSET_W{1'b0}} };

    // FSM
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            reqAddr <= 0; reqWdata <= 0; reqRe <= 0; reqWe <= 0;
            done <= 0; cpuReadData <= 0;
            replWay_r <= 0; victimTag_r <= 0; victimData_r <= 0;
        end else begin
            state <= next_state;
            
            // Clear done (pulse logic)
            done <= 0;

            if (state == S_IDLE) begin
                // FIX: Unconditionally latch address/data in IDLE to prevent aliasing
                reqAddr <= cpuAddr;
                reqWdata <= cpuWriteData;
                
                // Only latch commands if active
                if (cpuRead || cpuWrite) begin
                    reqRe <= cpuRead;
                    reqWe <= cpuWrite;
                end
            end

            if (state == S_LOOKUP) begin
                if (hit) begin
                    if (reqRe) cpuReadData <= hitData;
                    done <= 1;
                end else begin
                    replWay_r <= replWay_c;
                    victimTag_r <= rdTags[replWay_c*TAG_WIDTH +: TAG_WIDTH];
                    victimData_r <= rdData[replWay_c*DATA_WIDTH +: DATA_WIDTH];
                end
            end

            if (state == S_FILL) begin
                if (reqRe) cpuReadData <= ramReadData;
                done <= 1;
            end
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (cpuRead || cpuWrite) next_state = S_LOOKUP;
            end
            S_LOOKUP: begin
                if (hit) next_state = S_IDLE;
                else begin
                    if (victim_need_wb) next_state = S_WB;
                    else if (reqRe) next_state = S_RAMRD;
                    else next_state = S_FILL;
                end
            end
            S_WB: next_state = reqRe ? S_RAMRD : S_FILL;
            S_RAMRD: next_state = S_FILL;
            S_FILL: next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    // Outputs
    always @(*) begin
        // Default Cache inputs
        rdSet = reqSet;
        victimSet = reqSet;
        lineWriteEn = 0;
        lineWriteSet = reqSet;
        lineWriteWay = replWay_r; // Default to stored way
        lineWriteTag = reqTag;
        lineWriteData = 0;
        lineWriteValid = 1;
        lineWriteDirty = 0;
        lruAccessEn = 0;
        lruAccessSet = reqSet;
        lruAccessWay = replWay_r;

        // Default RAM inputs
        ramWriteEnable = 0;
        ramReadEnable = 0;
        ramAddr = reqAddr;
        ramWriteData = reqWdata;

        case (state)
            S_LOOKUP: begin
                if (hit) begin
                    lruAccessEn = 1;
                    lruAccessWay = hitWay;
                    if (reqWe) begin
                        lineWriteEn = 1;
                        lineWriteWay = hitWay;
                        lineWriteData = reqWdata;
                        lineWriteDirty = (WRITE_BACK ? 1 : 0);
                        // WT Logic
                        if (!WRITE_BACK) begin
                            ramWriteEnable = 1;
                        end
                    end
                end
            end
            S_WB: begin
                ramWriteEnable = 1;
                ramAddr = victimAddr;
                ramWriteData = victimData_r;
            end
            S_RAMRD: begin
                ramReadEnable = 1;
            end
            S_FILL: begin
                lineWriteEn = 1;
                lineWriteWay = replWay_r;
                lruAccessEn = 1;
                lruAccessWay = replWay_r;
                
                if (reqRe) begin
                    lineWriteData = ramReadData;
                    lineWriteDirty = 0;
                end else begin
                    lineWriteData = reqWdata;
                    lineWriteDirty = (WRITE_BACK ? 1 : 0);
                    if (!WRITE_BACK) begin
                        ramWriteEnable = 1;
                    end
                end
            end
        endcase
    end

endmodule

module cache_system #(
    parameter integer ADDR_WIDTH   = 16,
    parameter integer DATA_WIDTH   = 32,
    parameter integer NUM_WAYS     = 4,
    parameter integer NUM_SETS     = 64,
    parameter integer OFFSET_W     = 0,
    parameter integer SET_INDEX_W  = 6,
    parameter integer WAY_INDEX_W  = 2,
    parameter integer TAG_WIDTH    = 10,
    parameter integer WRITE_BACK   = 0
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   cpuRead,
    input  wire                   cpuWrite,
    input  wire [ADDR_WIDTH-1:0]  cpuAddr,
    input  wire [DATA_WIDTH-1:0]  cpuWriteData,
    output wire [DATA_WIDTH-1:0]  cpuReadData,
    output wire                   done,
    output wire                   ready
);

    wire [SET_INDEX_W-1:0] rdSet;
    wire [NUM_WAYS*TAG_WIDTH-1:0] rdTags;
    wire [NUM_WAYS*DATA_WIDTH-1:0] rdData;
    wire [NUM_WAYS-1:0] rdValid, rdDirty;
    wire lineWriteEn, lineWriteValid, lineWriteDirty, lruAccessEn, ramWriteEnable, ramReadEnable;
    wire [SET_INDEX_W-1:0] lineWriteSet, lruAccessSet, victimSet;
    wire [WAY_INDEX_W-1:0] lineWriteWay, lruAccessWay, victimWay;
    wire [TAG_WIDTH-1:0] lineWriteTag;
    wire [DATA_WIDTH-1:0] lineWriteData, ramWriteData, ramReadData;
    wire [ADDR_WIDTH-1:0] ramAddr;

    ram #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) ram_inst (
        .clk(clk), .rst(rst),
        .writeEnable(ramWriteEnable), .readEnable(ramReadEnable),
        .addr(ramAddr), .writeData(ramWriteData), .readData(ramReadData)
    );

    cache #(
        .NUM_SETS(NUM_SETS), .NUM_WAYS(NUM_WAYS),
        .TAG_WIDTH(TAG_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .SET_INDEX_W(SET_INDEX_W), .WAY_INDEX_W(WAY_INDEX_W),
        .USE_DIRTY(1), .USE_LRU(1)
    ) cache_inst (
        .clk(clk), .rst(rst),
        .rdSet(rdSet), .rdTags(rdTags), .rdData(rdData), .rdValid(rdValid), .rdDirty(rdDirty),
        .lineWriteEn(lineWriteEn), .lineWriteSet(lineWriteSet), .lineWriteWay(lineWriteWay),
        .lineWriteTag(lineWriteTag), .lineWriteData(lineWriteData),
        .lineWriteValid(lineWriteValid), .lineWriteDirty(lineWriteDirty),
        .lruAccessEn(lruAccessEn), .lruAccessSet(lruAccessSet), .lruAccessWay(lruAccessWay),
        .victimSet(victimSet), .victimWay(victimWay)
    );

    cache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS(NUM_SETS), .NUM_WAYS(NUM_WAYS),
        .SET_INDEX_W(SET_INDEX_W), .WAY_INDEX_W(WAY_INDEX_W),
        .OFFSET_W(OFFSET_W), .TAG_WIDTH(TAG_WIDTH),
        .WRITE_BACK(WRITE_BACK)
    ) ctrl_inst (
        .clk(clk), .rst(rst),
        .cpuRead(cpuRead), .cpuWrite(cpuWrite), .cpuAddr(cpuAddr), .cpuWriteData(cpuWriteData),
        .cpuReadData(cpuReadData), .done(done), .ready(ready),
        .rdSet(rdSet), .rdTags(rdTags), .rdData(rdData), .rdValid(rdValid), .rdDirty(rdDirty),
        .lineWriteEn(lineWriteEn), .lineWriteSet(lineWriteSet), .lineWriteWay(lineWriteWay),
        .lineWriteTag(lineWriteTag), .lineWriteData(lineWriteData),
        .lineWriteValid(lineWriteValid), .lineWriteDirty(lineWriteDirty),
        .lruAccessEn(lruAccessEn), .lruAccessSet(lruAccessSet), .lruAccessWay(lruAccessWay),
        .victimSet(victimSet), .victimWay(victimWay),
        .ramWriteEnable(ramWriteEnable), .ramReadEnable(ramReadEnable),
        .ramAddr(ramAddr), .ramWriteData(ramWriteData), .ramReadData(ramReadData)
    );

endmodule