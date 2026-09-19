`timescale 1ns / 1ps
// NEW verification testbench for control_unit decode safety - does not modify any project file.

module tb_control_unit_check;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    logic       jalr;
    logic       reg_write;
    logic       alu_src;
    logic       mem_read;
    logic       mem_write;
    logic       branch;
    logic       jump;
    logic [2:0] imm_sel;
    logic       mem_to_reg;
    logic [3:0] alu_control;
    logic [1:0] mem_size;
    logic       load_unsigned;
    logic [1:0] alu_a_sel;

    int errors = 0;
    int checks = 0;

    control_unit dut (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),
        .jalr        (jalr),
        .reg_write   (reg_write),
        .alu_src     (alu_src),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .branch      (branch),
        .jump        (jump),
        .imm_sel     (imm_sel),
        .mem_to_reg  (mem_to_reg),
        .alu_control (alu_control),
        .mem_size      (mem_size),
        .load_unsigned (load_unsigned),
        .alu_a_sel     (alu_a_sel)
    );

    // An encoding is "safe" when it causes no architectural side effect:
    // no register write, no memory access, no branch, no jump.
    task automatic expect_safe(input string name,
                               input logic [6:0] op,
                               input logic [2:0] f3,
                               input logic [6:0] f7);
        opcode = op; funct3 = f3; funct7 = f7;
        #1;
        checks++;
        if (reg_write !== 1'b0 || mem_write !== 1'b0 || mem_read !== 1'b0 ||
            branch !== 1'b0 || jump !== 1'b0 || jalr !== 1'b0) begin
            errors++;
            $display("FAIL: %-45s rw=%b mw=%b mr=%b br=%b j=%b jr=%b (expected all 0)",
                     name, reg_write, mem_write, mem_read, branch, jump, jalr);
        end
        else begin
            $display("PASS: %-45s no side effects", name);
        end
    endtask

    task automatic expect_ctrl(input string name,
                               input logic [6:0] op,
                               input logic [2:0] f3,
                               input logic [6:0] f7,
                               input logic e_rw, input logic e_mw, input logic e_mr,
                               input logic e_br, input logic e_j,  input logic e_jr);
        opcode = op; funct3 = f3; funct7 = f7;
        #1;
        checks++;
        if (reg_write !== e_rw || mem_write !== e_mw || mem_read !== e_mr ||
            branch !== e_br || jump !== e_j || jalr !== e_jr) begin
            errors++;
            $display("FAIL: %-45s rw=%b mw=%b mr=%b br=%b j=%b jr=%b expected rw=%b mw=%b mr=%b br=%b j=%b jr=%b",
                     name, reg_write, mem_write, mem_read, branch, jump, jalr,
                     e_rw, e_mw, e_mr, e_br, e_j, e_jr);
        end
        else begin
            $display("PASS: %-45s decode correct", name);
        end
    endtask

    task automatic check_aux(input string name,
                             input logic [6:0] op,
                             input logic [2:0] f3,
                             input logic [6:0] f7,
                             input logic [1:0] e_size,
                             input logic e_lu,
                             input logic [1:0] e_asel);
        opcode = op; funct3 = f3; funct7 = f7;
        #1;
        checks++;
        if (mem_size !== e_size || load_unsigned !== e_lu || alu_a_sel !== e_asel) begin
            errors++;
            $display("FAIL: %-45s size=%b lu=%b asel=%b expected size=%b lu=%b asel=%b",
                     name, mem_size, load_unsigned, alu_a_sel, e_size, e_lu, e_asel);
        end
        else $display("PASS: %-45s aux controls correct", name);
    endtask

    initial begin
        $display("==== control_unit decode-safety checks ====");

        // ---- Invalid R-type funct7 combinations ----
        expect_safe("R-type ADD/SUB slot, funct7=1111111", 7'b0110011, 3'b000, 7'b1111111);
        expect_safe("R-type ADD/SUB slot, funct7=0000001", 7'b0110011, 3'b000, 7'b0000001);
        expect_safe("R-type SLL, illegal funct7=0100000",  7'b0110011, 3'b001, 7'b0100000);
        expect_safe("R-type SLT, illegal funct7=0000001",  7'b0110011, 3'b010, 7'b0000001);
        expect_safe("R-type SLTU, illegal funct7=1000000", 7'b0110011, 3'b011, 7'b1000000);
        expect_safe("R-type XOR, illegal funct7=0100000",  7'b0110011, 3'b100, 7'b0100000);
        expect_safe("R-type SRL/SRA, illegal funct7",      7'b0110011, 3'b101, 7'b1010101);
        expect_safe("R-type OR, illegal funct7=0100000",   7'b0110011, 3'b110, 7'b0100000);
        expect_safe("R-type AND, illegal funct7=0000010",  7'b0110011, 3'b111, 7'b0000010);

        // ---- Invalid branch funct3 encodings ----
        expect_safe("BRANCH invalid funct3=010",           7'b1100011, 3'b010, 7'b0000000);
        expect_safe("BRANCH invalid funct3=011",           7'b1100011, 3'b011, 7'b0000000);

        // ---- Implemented subword loads + illegal load funct3 ----
        //                                                    op          f3      f7          rw mw mr br j  jr
        expect_ctrl("LB decodes",        7'b0000011, 3'b000, 7'b0000000,    1, 0, 1, 0, 0, 0);
        expect_ctrl("LH decodes",        7'b0000011, 3'b001, 7'b0000000,    1, 0, 1, 0, 0, 0);
        expect_ctrl("LBU decodes",       7'b0000011, 3'b100, 7'b0000000,    1, 0, 1, 0, 0, 0);
        expect_ctrl("LHU decodes",       7'b0000011, 3'b101, 7'b0000000,    1, 0, 1, 0, 0, 0);
        expect_safe("LOAD illegal funct3=011",             7'b0000011, 3'b011, 7'b0000000);
        expect_safe("LOAD illegal funct3=111",             7'b0000011, 3'b111, 7'b0000000);

        // ---- Implemented subword stores + illegal store funct3 ----
        expect_ctrl("SB decodes",        7'b0100011, 3'b000, 7'b0000000,    0, 1, 0, 0, 0, 0);
        expect_ctrl("SH decodes",        7'b0100011, 3'b001, 7'b0000000,    0, 1, 0, 0, 0, 0);
        expect_safe("STORE illegal funct3=111",            7'b0100011, 3'b111, 7'b0000000);

        // ---- LUI / AUIPC (U-format has no funct3/funct7 - any bits there are imm) ----
        expect_ctrl("LUI decodes",       7'b0110111, 3'b000, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("LUI f3/f7 = imm bits", 7'b0110111, 3'b101, 7'b1111111, 1, 0, 0, 0, 0, 0);
        expect_ctrl("AUIPC decodes",     7'b0010111, 3'b000, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("AUIPC f3/f7 = imm bits", 7'b0010111, 3'b011, 7'b0101010, 1, 0, 0, 0, 0, 0);

        // ---- JALR only valid with funct3 = 000 ----
        expect_safe("JALR invalid funct3=001",             7'b1100111, 3'b001, 7'b0000000);
        expect_safe("JALR invalid funct3=111",             7'b1100111, 3'b111, 7'b1111111);

        // ---- Shift-immediate funct7 legality ----
        expect_ctrl("SLLI decodes",      7'b0010011, 3'b001, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("SRLI decodes",      7'b0010011, 3'b101, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("SRAI decodes",      7'b0010011, 3'b101, 7'b0100000,    1, 0, 0, 0, 0, 0);
        expect_safe("SLLI illegal funct7=0100000",         7'b0010011, 3'b001, 7'b0100000);
        expect_safe("SLLI illegal funct7=1111111",         7'b0010011, 3'b001, 7'b1111111);
        expect_safe("SRLI/SRAI illegal funct7=1010101",    7'b0010011, 3'b101, 7'b1010101);

        // ---- mem_size / load_unsigned / alu_a_sel side outputs ----
        check_aux("LB   size=BYTE signed",   7'b0000011, 3'b000, 7'b0000000, 2'b00, 1'b0, 2'b00);
        check_aux("LBU  size=BYTE unsigned", 7'b0000011, 3'b100, 7'b0000000, 2'b00, 1'b1, 2'b00);
        check_aux("LH   size=HALF signed",   7'b0000011, 3'b001, 7'b0000000, 2'b01, 1'b0, 2'b00);
        check_aux("LHU  size=HALF unsigned", 7'b0000011, 3'b101, 7'b0000000, 2'b01, 1'b1, 2'b00);
        check_aux("LW   size=WORD",          7'b0000011, 3'b010, 7'b0000000, 2'b10, 1'b0, 2'b00);
        check_aux("SB   size=BYTE",          7'b0100011, 3'b000, 7'b0000000, 2'b00, 1'b0, 2'b00);
        check_aux("SH   size=HALF",          7'b0100011, 3'b001, 7'b0000000, 2'b01, 1'b0, 2'b00);
        check_aux("SW   size=WORD",          7'b0100011, 3'b010, 7'b0000000, 2'b10, 1'b0, 2'b00);
        check_aux("LUI  operand A = zero",   7'b0110111, 3'b000, 7'b0000000, 2'b10, 1'b0, 2'b10);
        check_aux("AUIPC operand A = PC",    7'b0010111, 3'b000, 7'b0000000, 2'b10, 1'b0, 2'b01);
        check_aux("ADD  operand A = rs1",    7'b0110011, 3'b000, 7'b0000000, 2'b10, 1'b0, 2'b00);

        // ---- Garbage opcodes ----
        expect_safe("garbage opcode 1111111",              7'b1111111, 3'b111, 7'b1111111);
        expect_safe("garbage opcode 0000000",              7'b0000000, 3'b000, 7'b0000000);
        expect_safe("garbage opcode 1010101",              7'b1010101, 3'b010, 7'b0101010);

        // ---- Positive decode checks (existing instructions still decode) ----
        //                                                       op          f3      f7          rw mw mr br j  jr
        expect_ctrl("ADD decodes",       7'b0110011, 3'b000, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("SUB decodes",       7'b0110011, 3'b000, 7'b0100000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("ADDI decodes",      7'b0010011, 3'b000, 7'b0000000,    1, 0, 0, 0, 0, 0);
        expect_ctrl("LW decodes",        7'b0000011, 3'b010, 7'b0000000,    1, 0, 1, 0, 0, 0);
        expect_ctrl("SW decodes",        7'b0100011, 3'b010, 7'b0000000,    0, 1, 0, 0, 0, 0);
        expect_ctrl("BEQ decodes",       7'b1100011, 3'b000, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("BNE decodes",       7'b1100011, 3'b001, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("BLT decodes",       7'b1100011, 3'b100, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("BGE decodes",       7'b1100011, 3'b101, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("BLTU decodes",      7'b1100011, 3'b110, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("BGEU decodes",      7'b1100011, 3'b111, 7'b0000000,    0, 0, 0, 1, 0, 0);
        expect_ctrl("JAL decodes",       7'b1101111, 3'b000, 7'b0000000,    1, 0, 0, 0, 1, 0);
        expect_ctrl("JALR decodes",      7'b1100111, 3'b000, 7'b0000000,    1, 0, 0, 0, 0, 1);

        // JAL must select the J-type immediate
        opcode = 7'b1101111; funct3 = 3'b000; funct7 = 7'b0000000; #1;
        checks++;
        if (imm_sel !== 3'b100) begin
            errors++;
            $display("FAIL: JAL imm_sel=%b expected 100 (IMM_J)", imm_sel);
        end else $display("PASS: JAL selects J-type immediate");

        $display("==== control_unit result: %0d checks, %0d errors ====", checks, errors);
        if (errors == 0) $display("CONTROL_UNIT_TB: ALL PASS");
        else             $display("CONTROL_UNIT_TB: FAILED");
        $finish;
    end

endmodule
