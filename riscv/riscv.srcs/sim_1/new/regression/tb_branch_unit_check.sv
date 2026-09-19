`timescale 1ns / 1ps
// NEW verification testbench for branch_unit - does not modify any project file.

module tb_branch_unit_check;

    logic        branch;
    logic [2:0]  funct3;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic        branch_taken;

    int errors = 0;
    int checks = 0;

    branch_unit dut (
        .branch       (branch),
        .funct3       (funct3),
        .operand_a    (operand_a),
        .operand_b    (operand_b),
        .branch_taken (branch_taken)
    );

    task automatic check(input string name,
                         input logic br,
                         input logic [2:0] f3,
                         input logic [31:0] a,
                         input logic [31:0] b,
                         input logic expected);
        branch    = br;
        funct3    = f3;
        operand_a = a;
        operand_b = b;
        #1;
        checks++;
        if (branch_taken !== expected) begin
            errors++;
            $display("FAIL: %-40s a=%h b=%h expected taken=%b got %b",
                     name, a, b, expected, branch_taken);
        end
        else begin
            $display("PASS: %-40s a=%h b=%h taken=%b", name, a, b, branch_taken);
        end
    endtask

    initial begin
        $display("==== branch_unit checks ====");

        // Gating: branch deasserted -> never taken
        check("gate: branch=0 BEQ equal",      1'b0, 3'b000, 32'd5, 32'd5, 1'b0);
        check("gate: branch=0 BNE unequal",    1'b0, 3'b001, 32'd5, 32'd3, 1'b0);

        // BEQ
        check("BEQ equal -> taken",            1'b1, 3'b000, 32'd7, 32'd7, 1'b1);
        check("BEQ unequal -> not taken",      1'b1, 3'b000, 32'd7, 32'd8, 1'b0);

        // BNE
        check("BNE unequal -> taken",          1'b1, 3'b001, 32'd5, 32'd3, 1'b1);
        check("BNE equal -> not taken",        1'b1, 3'b001, 32'd5, 32'd5, 1'b0);

        // BLT (signed)
        check("BLT -1 < 1 -> taken",           1'b1, 3'b100, 32'hFFFFFFFF, 32'd1, 1'b1);
        check("BLT 1 < -1 -> not taken",       1'b1, 3'b100, 32'd1, 32'hFFFFFFFF, 1'b0);
        check("BLT equal -> not taken",        1'b1, 3'b100, 32'd5, 32'd5, 1'b0);
        check("BLT INT_MIN < INT_MAX",         1'b1, 3'b100, 32'h80000000, 32'h7FFFFFFF, 1'b1);

        // BGE (signed)
        check("BGE equal -> taken",            1'b1, 3'b101, 32'd5, 32'd5, 1'b1);
        check("BGE -1 >= 1 -> not taken",      1'b1, 3'b101, 32'hFFFFFFFF, 32'd1, 1'b0);
        check("BGE 1 >= -1 -> taken",          1'b1, 3'b101, 32'd1, 32'hFFFFFFFF, 1'b1);
        check("BGE INT_MAX >= INT_MIN",        1'b1, 3'b101, 32'h7FFFFFFF, 32'h80000000, 1'b1);

        // BLTU (unsigned)
        check("BLTU FFFFFFFF < 1 -> not taken",1'b1, 3'b110, 32'hFFFFFFFF, 32'd1, 1'b0);
        check("BLTU 1 < FFFFFFFF -> taken",    1'b1, 3'b110, 32'd1, 32'hFFFFFFFF, 1'b1);
        check("BLTU equal -> not taken",       1'b1, 3'b110, 32'd0, 32'd0, 1'b0);

        // BGEU (unsigned)
        check("BGEU FFFFFFFF >= 1 -> taken",   1'b1, 3'b111, 32'hFFFFFFFF, 32'd1, 1'b1);
        check("BGEU equal -> taken",           1'b1, 3'b111, 32'd0, 32'd0, 1'b1);
        check("BGEU 1 >= 2 -> not taken",      1'b1, 3'b111, 32'd1, 32'd2, 1'b0);

        // Invalid funct3 encodings must never take the branch
        check("invalid funct3 010 -> not taken", 1'b1, 3'b010, 32'd0, 32'd0, 1'b0);
        check("invalid funct3 011 -> not taken", 1'b1, 3'b011, 32'd0, 32'd0, 1'b0);

        $display("==== branch_unit result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("BRANCH_UNIT_TB: ALL PASS");
        else             $display("BRANCH_UNIT_TB: FAILED");
        $finish;
    end

endmodule
