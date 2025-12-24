`timescale 1ns / 1ps

module tb_cache_system;

    // ----------------------------------
    // Signals
    // ----------------------------------
    reg clk;
    reg rd;
    reg wr;
    reg [15:0] addr;
    reg [31:0] wdata;
    wire [31:0] rdata;

    reg [31:0] rdata_expected;

    integer test_num = 0;
    integer correct_count = 0;
    integer error_count = 0;

    // ----------------------------------
    // DUT: 4-Way Set Associative Cache
    // 64 sets × 4 ways = 256 entries
    // ----------------------------------
    cache_controller #(
        .NUM_SETS(64),
        .NUM_WAYS(4)
    ) dut (
        .clk(clk),
        .rd(rd),
        .wr(wr),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata)
    );


    // ========== Clock (2 ns period) ===========   
    initial begin
        clk = 0;
        forever #1 clk = ~clk;
    end

    // ========== Self-checking task (NO timing) ==========
    task check_output;
        input [31:0] expected;
        input [31:0] actual;
        begin
            test_num = test_num + 1;
            if (actual === expected) begin
                correct_count = correct_count + 1;
                $display("TEST %0d PASSED: expected=%h actual=%h time=%0t",
                         test_num, expected, actual, $time);
            end else begin
                error_count = error_count + 1;
                $display("TEST %0d FAILED: expected=%h got=%h time=%0t",
                         test_num, expected, actual, $time);
            end
        end
    endtask

    // ========== Write task (timing-safe) ==========   
    task write_op;
        input [15:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr = a;
            wdata = d;
            wr = 1;
            rd = 0;
            @(posedge clk);
            wr = 0;
        end
    endtask

    // ========== Read & check task (2-cycle latency) ==========
    task read_check;
        input [15:0] a;
        input [31:0] expected;
        begin
            @(negedge clk);
            addr = a;
            rd = 1;
            wr = 0;
            rdata_expected = expected;
            @(posedge clk);   // controller
            @(posedge clk);   // RAM/cache
            rd = 0;
            check_output(expected, rdata);
        end
    endtask

    // ========== TEST Cases Start ==========
    initial begin
        // Init
        rd = 0; wr = 0; addr = 0; wdata = 0;

        // SA-01: Cold miss (exercise only, no check)
        $display("TESTCASE SA-01: Cold miss");
        @(negedge clk);
        addr = 16'h0004;
        rd = 1;
        @(negedge clk);
        rd = 0;
        repeat(2) @(posedge clk);
        rdata_expected = 32'h00000000;
        check_output(rdata_expected, rdata); // RAM default 0

        // =========== SA-02: Write then read hit ===========
        $display("TESTCASE SA-02: Way fill");
        write_op(16'h0004, 32'h1111AAAA);
        read_check(16'h0004, 32'h1111AAAA);

        // ============ SA-02: Fill all 4 ways (same set)============
        $display("TESTCASE SA-02: Way fill (fill all 4 ways)");
        write_op(16'h0004, 32'hAAAA0001); 
        write_op(16'h0404, 32'hAAAA0002); 
        write_op(16'h0804, 32'hAAAA0003); 
        write_op(16'h0C04, 32'hAAAA0004); 

        // Round-robin LRU → last written way is most recent
        read_check(16'h0C04, 32'hAAAA0004);

        // =========== SA-03: LRU eviction (round-robin) ===========
        $display("TESTCASE SA-03: LRU eviction");
        write_op(16'h1004, 32'hAAAA0005);

        // The new line should be present
        read_check(16'h1004, 32'hAAAA0005);

        // SA-07: Read after eviction (clean line → RAM still 0)
        read_check(16'h0004, 32'h1111AAAA);

        // =========== SA-09: Address boundary test ===========
        $display("TESTCASE SA-09: Address boundary");
        write_op(16'hFFFF, 32'hDEADBEEF);
        read_check(16'hFFFF, 32'hDEADBEEF);

        // SUMMARY
        $display("--------------------------------");
        $display("Total Tests   : %0d", test_num);
        $display("Correct Tests : %0d", correct_count);
        $display("Error Tests   : %0d", error_count);
        $display("--------------------------------");

        $stop;
    end

endmodule