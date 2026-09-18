`timescale 1ns/1ps
// =============================================================
// Testbench : VDOT.8 Verification
// Purpose   : Functional verification, pipeline validation, 
//             saturation logic, and Overflow check.
// =============================================================
module tb_vdot8;
    // Testbench signals
    reg        clk, rst_n, enable, start;
    reg [31:0] a, b;
    wire signed [31:0] result;
    wire               valid, overflow;

    // Clock generation: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Unit Under Test (UUT) instantiation
    vdot8 uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (enable),
        .start    (start),
        .a        (a),
        .b        (b),
        .result   (result),
        .valid    (valid),
        .overflow (overflow)
    );

    integer pass=0, fail=0;

    // Task: Apply stimulus and verify expected output
    task check;
        input [31:0] in_a, in_b;
        input        in_start;
        input [31:0] expected;
        input        exp_overflow;
        input [7:0]  tnum;
        begin
            @(negedge clk);
            enable=1; start=in_start; a=in_a; b=in_b;
            @(posedge clk); #1; // Capture at Stage 1
            @(negedge clk); enable=0;
            @(posedge clk); #1; // Stage 2 flow
            @(posedge clk); #1; // Stage 3 output
            
            // Result verification
            if (result===expected && overflow===exp_overflow) begin
                $display("  [PASS] T%0d: result=%0d overflow=%b", tnum, result, overflow);
                pass=pass+1;
            end else begin
                $display("  [FAIL] T%0d: got result=%0d(exp %0d) overflow=%b(exp %b)",
                         tnum, $signed(result), $signed(expected), overflow, exp_overflow);
                fail=fail+1;
            end
        end
    endtask

    // Task: Single accumulation cycle for stress testing
    task pulse_accumulate;
        input [31:0] in_a, in_b;
        begin
            @(negedge clk);
            enable=1; start=0; a=in_a; b=in_b;
            @(posedge clk); #1;
            @(negedge clk); enable=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
        end
    endtask

    // Safety timeout: Terminates simulation if it runs beyond 3ms
    initial begin
        #2100000;
        $display("  [TIMEOUT] Simulation reached 3ms limit before $finish");
        $finish;
    end

    // Main Test Stimulus
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_vdot8);
        
        // Initialize inputs and perform reset
        clk=0; rst_n=0; enable=0; start=1; a=0; b=0;
        #20 rst_n=1;

        $display("=====================================================");
        $display("  VDOT.8 3-Stage Pipelined Verification");
        $display("  Chennai Institute of Technology | SKY130");
        $display("=====================================================");

        // Functional correctness tests
        check(32'h01010101, 32'h01010101, 1, 32'd4, 0, 1);
        check(32'h04030201, 32'h01020304, 1, 32'd20, 0, 2);
        check(32'h04030201, 32'h04030201, 1, 32'd30, 0, 3);
        check(32'hFFFFFFFF, 32'h01010101, 1, 32'hFFFFFFFC, 0, 4);
        check(32'h05FC03FE, 32'hFE03FC05, 1, 32'hFFFFFFD4, 0, 5);
        check(32'h04030201, 32'h01020304, 1, 32'd20, 0, 6);
        check(32'h04030201, 32'h01020304, 0, 32'd40, 0, 100);

        // Saturation Test: Positive overflow detection
        check(32'h7F7F7F7F, 32'h7F7F7F7F, 1, 32'd64516, 0, 7);
        begin : accum_loop
            integer i;
            reg found_overflow;
            found_overflow = 0;
            for (i=0; i<40000; i=i+1) begin
                pulse_accumulate(32'h7F7F7F7F, 32'h7F7F7F7F);
                if (overflow) begin
                    found_overflow = 1;
                    if (result===32'h7FFFFFFF) begin
                        $display("  [PASS] T7: positive overflow detected at accumulate #%0d, clamped to result=0x%08X",i+1,result);
                        pass=pass+1;
                    end else begin
                        $display("  [FAIL] T7: overflow flagged at accumulate #%0d but result=0x%08X",i+1,result);
                        fail=fail+1;
                    end
                    disable accum_loop;
                end
            end
            if (!found_overflow) begin
                $display("  [FAIL] T7: positive saturation never triggered within 40000 iterations");
                fail=fail+1;
            end
        end

        // Saturation Test: Negative overflow detection
        check(32'hFF818181, 32'h01010101, 1, 32'hFFFFFE82, 0, 8);
        begin : neg_loop
            integer j;
            reg found_overflow;
            found_overflow = 0;
            for (j=0; j<40000; j=j+1) begin
                pulse_accumulate(32'h80808080, 32'h7F7F7F7F);
                if (overflow) begin
                    found_overflow = 1;
                    if (result===32'h80000000) begin
                        $display("  [PASS] T8: negative overflow detected at accumulate #%0d, clamped to result=0x%08X",j+1,result);
                        pass=pass+1;
                    end else begin
                        $display("  [FAIL] T8: overflow flagged at accumulate #%0d but result=0x%08X",j+1,result);
                        fail=fail+1;
                    end
                    disable neg_loop;
                end
            end
            if (!found_overflow) begin
                $display("  [FAIL] T8: negative saturation never triggered within 40000 iterations");
                fail=fail+1;
            end
        end

        // Clock Gating Test: Verify zero output when disabled
        @(negedge clk);
        rst_n=0; #12; rst_n=1;
        @(negedge clk);
        enable=0; start=1;
        a=32'hFFFFFFFF; b=32'hFFFFFFFF;
        #30;
        if (result===32'b0 && valid===1'b0) begin
            $display("  [PASS] T9: enable=0 -> result=0 valid=0 (clock gating OK)");
            pass=pass+1;
        end else begin
            $display("  [FAIL] T9: enable=0 but result=%0d valid=%b",result,valid);
            fail=fail+1;
        end
        // Summary report
        $display("=====================================================");
        $display("  RESULTS: %0d PASS | %0d FAIL | %0d TOTAL",pass,fail,pass+fail);
        if (fail==0)
            $display("  ALL TESTS PASSED - VDOT.8 3-STAGE SILICON READY");
        else
            $display("  CHECK FAILED TESTS");
        $display("=====================================================");
        $finish;
    end
endmodule
