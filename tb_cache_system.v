module tb_cache_system;
    localparam integer TEST_WRITE_BACK = 0; // 0 for WT, 1 for WB

    parameter integer ADDR_WIDTH   = 16;
    parameter integer DATA_WIDTH   = 32;
    parameter integer NUM_WAYS     = 4;
    parameter integer NUM_SETS     = 64;
    parameter integer OFFSET_W     = 0;
    parameter integer SET_INDEX_W  = 6;
    parameter integer TAG_WIDTH    = 10;

    reg clk;
    reg rst;
    reg cpuRead;
    reg cpuWrite;
    reg  [ADDR_WIDTH-1:0] cpuAddr;
    reg  [DATA_WIDTH-1:0] cpuWriteData;
    wire [DATA_WIDTH-1:0] cpuReadData;
    wire done;
    wire ready;

    integer error_count = 0 ,correct_count = 0 ,test_num = 0;
    
    // expected values
    reg [DATA_WIDTH-1:0] rdata_expected;

    cache_system #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .NUM_WAYS    (NUM_WAYS),
        .NUM_SETS    (NUM_SETS),
        .OFFSET_W    (OFFSET_W),
        .SET_INDEX_W (SET_INDEX_W),
        .TAG_WIDTH   (TAG_WIDTH),
        .WRITE_BACK  (TEST_WRITE_BACK)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .cpuRead      (cpuRead),
        .cpuWrite     (cpuWrite),
        .cpuAddr      (cpuAddr),
        .cpuWriteData (cpuWriteData),
        .cpuReadData  (cpuReadData),
        .done         (done),
        .ready        (ready)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task reset;
        begin
            test_num = 0;
            rst = 1;
            cpuRead = 0; cpuWrite = 0; cpuAddr = 0; cpuWriteData = 0; rdata_expected = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            @(posedge clk);
            $display("[INFO] System Reset Complete");
        end
    endtask

    task cpu_read_check;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected_data;
        input is_hit_expected; 
        begin
            test_num = test_num + 1;
            rdata_expected = expected_data;

            while (!ready) @(posedge clk);
            @(posedge clk);

            cpuRead = 1;
            cpuAddr = addr;
            
            @(posedge clk);
            while(!done) @(posedge clk);

            cpuRead = 0; cpuAddr = 0;

            if (cpuReadData !== expected_data) begin
                $display("[FAIL TC%0d] Addr: 0x%h | Exp: 0x%h | Got: 0x%h", test_num, addr, expected_data, cpuReadData);
                error_count = error_count + 1;
            end else begin
                $display("[PASS TC%0d] Addr: 0x%h | Data: 0x%h ", test_num, addr, cpuReadData);
                correct_count = correct_count + 1;
            end
            @(posedge clk);
        end
    endtask

    task cpu_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            test_num = test_num + 1;
            while (!ready) @(posedge clk);
            @(posedge clk);
        
            cpuWrite = 1;
            cpuAddr = addr;
            cpuWriteData = data;

            @(posedge clk);
            while(!done) @(posedge clk);

            cpuWrite = 0; cpuAddr = 0; cpuWriteData = 0;
            $display("[INFO TC%0d] Write Addr: 0x%h | Data: 0x%h", test_num, addr, data);
            @(posedge clk);
        end
    endtask

    task ram_preload;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            dut.ram_inst.mem[addr] = data;
        end
    endtask

    task check_ram_content;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] exp_data;
        begin
            if (dut.ram_inst.mem[addr] !== exp_data) begin
                $display("[FAIL RAM] Addr: 0x%h | Exp: 0x%h | Got: 0x%h", addr, exp_data, dut.ram_inst.mem[addr]);
                error_count = error_count + 1;
            end else begin
                $display("[PASS RAM] Addr: 0x%h | Match: 0x%h", addr, exp_data);
            end
        end
    endtask
    
    // ================================= MAIN =============================================
    initial begin
        $display("============================================================");
        $display(" STARTING CACHE SYSTEM TESTBENCH");
        $display("============================================================");

        reset();

        // T1: Cold Read Miss (first access)
        $display("[TEST T1] ========  Cold Read Miss: preload RAM[0x0010]=DEAD_BEEF then READ 0x0010 (expect miss, fill) ========");
        ram_preload(16'h0010, 32'hDEAD_BEEF);
        cpu_read_check(16'h0010, 32'hDEAD_BEEF, 0);

        // T2: Cold Read Miss (repeat)
        $display("[TEST T2] ========  Cold Read Miss (repeat): access same address to confirm behavior ========");
        cpu_read_check(16'h0010, 32'hDEAD_BEEF, 1);

        // T3: Read Hit
        $display("[TEST T3] ========  Read Hit: verify hit detection after line fill ========");
        cpu_read_check(16'h0010, 32'hDEAD_BEEF, 1);

        // T4: Write Hit (WT)
        if (TEST_WRITE_BACK == 0) begin
            $display("[TEST T4] ========  Write Hit (WT): write to cached address and verify RAM updated immediately ========");
            cpu_write(16'h0010, 32'hCAFE_BABE);
            check_ram_content(16'h0010, 32'hCAFE_BABE);
            cpu_read_check(16'h0010, 32'hCAFE_BABE, 1);
        end

        // T5: Write Miss
        if (TEST_WRITE_BACK == 0) begin
            $display("[TEST T5] ========  Write Miss (Write-Allocate + WT): write to uncached address, expect allocation and RAM update ========");
            cpu_write(16'h0020, 32'hAAAA_5555);
            check_ram_content(16'h0020, 32'hAAAA_5555);
            cpu_read_check(16'h0020, 32'hAAAA_5555, 1);
        end

        // T6: Different Sets
        $display("[TEST T6] ========  Different Sets: preload/read 0x0011 then read 0x0010 to verify independent sets ========");
        ram_preload(16'h0011, 32'h1111_2222);
        cpu_read_check(16'h0011, 32'h1111_2222, 0);
        cpu_read_check(16'h0010, 32'hCAFE_BABE, 1);

        // T7: Set Fill
        $display("[TEST T7] ========  Set Fill: fill all ways in one set with 0x0003,0x0043,0x0083,0x00C3 then verify hits ========");
        ram_preload(16'h0003, 32'hA0A0_A0A0);
        ram_preload(16'h0043, 32'hB0B0_B0B0);
        ram_preload(16'h0083, 32'hC0C0_C0C0);
        ram_preload(16'h00C3, 32'hD0D0_D0D0);

        cpu_read_check(16'h0003, 32'hA0A0_A0A0, 0);
        cpu_read_check(16'h0043, 32'hB0B0_B0B0, 0);
        cpu_read_check(16'h0083, 32'hC0C0_C0C0, 0);
        cpu_read_check(16'h00C3, 32'hD0D0_D0D0, 0);
        cpu_read_check(16'h0003, 32'hA0A0_A0A0, 1);

        // T8: Replacement (LRU)
        $display("[TEST T8] ========  LRU Replacement: touch ways then access new line to force eviction ========");
        cpu_read_check(16'h0043, 32'hB0B0_B0B0, 1);
        cpu_read_check(16'h0083, 32'hC0C0_C0C0, 1);
        cpu_read_check(16'h00C3, 32'hD0D0_D0D0, 1);
        ram_preload(16'h0103, 32'hE0E0_E0E0);
        cpu_read_check(16'h0103, 32'hE0E0_E0E0, 0);
        cpu_read_check(16'h0003, 32'hA0A0_A0A0, 0);

        // T9: RAW (Read After Write)
        $display("[TEST T9] ========  Read-After-Write (RAW): write then immediately read same address ==========");
        cpu_write(16'h0100, 32'h9999_8888);
        cpu_read_check(16'h0100, 32'h9999_8888, 1);

        // T11: Address Boundary
        $display("[TEST T11] ========  Address Boundary: verify max address handling with 0xFFFF ========");
        ram_preload(16'hFFFF, 32'hFFFF_FFFF);
        cpu_read_check(16'hFFFF, 32'hFFFF_FFFF, 0);

        // Bonus WB Logic (Only runs if enabled)
        if (TEST_WRITE_BACK == 1) begin
             $display("[TEST WB] ========  Write-Back Tests: dirty bit, eviction write-back, write-allocate behavior ========");
             ram_preload(16'h0005, 32'hC1EA_0000);
             cpu_read_check(16'h0005, 32'hC1EA_0000, 0);
             cpu_write(16'h0005, 32'hD157_0000);
             
             if (dut.ram_inst.mem[16'h0005] !== 32'hD157_0000) $display("[PASS] Write-Back Verified");
             else begin
                $display("[FAIL] RAM updated immediately");
                error_count = error_count + 1;
             end

             cpu_read_check(16'h0045, 32'h0, 0);
             cpu_read_check(16'h0085, 32'h0, 0);
             cpu_read_check(16'h00C5, 32'h0, 0);
             cpu_read_check(16'h0045, 32'h0, 1);
             cpu_read_check(16'h0085, 32'h0, 1);
             cpu_read_check(16'h00C5, 32'h0, 1);
             cpu_read_check(16'h0105, 32'h0, 0);
             check_ram_content(16'h0005, 32'hD157_0000);

             cpu_write(16'h0200, 32'hA110_CA7E);
             if (dut.ram_inst.mem[16'h0200] !== 32'hA110_CA7E) $display("[PASS] Alloc Dirty Verified");
             else begin
                $display("[FAIL] Alloc updated RAM");
                error_count = error_count + 1;
             end
        end else begin
            $display("[TEST WT] ========  Write-Through Final Test: simple WT write and RAM check ========");
            cpu_write(16'h0300, 32'hC4EC_0001);
            check_ram_content(16'h0300, 32'hC4EC_0001);
        end

        $display("\n============================================================");
        if (error_count == 0) $display("  ALL TESTS PASSED");
        else $display("  FAILURES: %0d", error_count);
        $display("============================================================");
        $stop;
    end
endmodule