`timescale 1ns/1ps
// =============================================================
// Project : VDOT.8 for Edge-AI Acceleration
// PDK     : SkyWater SKY130 fd_sc_hd
//
// 3-STAGE PIPELINED DOT PRODUCT
//   Stage 1: Input Gating and 4x Parallel Signed 8x8 Multipliers
//   Stage 2: Adder Tree (Reduces 4 products to a single sum)
//   Stage 3: 33-bit Accumulator with Hardware Saturation
// =============================================================
module vdot8 (
    input  wire        clk,        // System Clock
    input  wire        rst_n,      // Active-Low Asynchronous Reset
    input  wire        enable,     // Clock Gating / Core Enable
    input  wire        start,      // Start signal: 1 = Reset accumulation, 0 = Add to current
    input  wire [31:0] a,          // Input Vector A (Four 8-bit signed values)
    input  wire [31:0] b,          // Input Vector B (Four 8-bit signed values)
    output reg  signed [31:0] result,   // 32-bit Accumulator Output
    output reg         valid,       // Valid data flag
    output reg         overflow     // Saturation indicator flag
);

// --- Saturation Constants ---
// Define boundaries for 32-bit signed integer saturation
localparam signed [32:0] MAX_POS = 33'sh0_7FFF_FFFF;  // Max Positive (2,147,483,647)
localparam signed [32:0] MAX_NEG = 33'sh1_8000_0000;  // Min Negative (-2,147,483,648)

// --- Stage 1: Input Gating & Multiplier Array ---
// Disable inputs if enable is low to save switching power
wire [31:0] a_gated = enable ? a : 32'b0;
wire [31:0] b_gated = enable ? b : 32'b0;

// Split 32-bit input into four 8-bit signed segments
wire signed [7:0] a0 = a_gated[7:0];   wire signed [7:0] b0 = b_gated[7:0];
wire signed [7:0] a1 = a_gated[15:8];  wire signed [7:0] b1 = b_gated[15:8];
wire signed [7:0] a2 = a_gated[23:16]; wire signed [7:0] b2 = b_gated[23:16];
wire signed [7:0] a3 = a_gated[31:24]; wire signed [7:0] b3 = b_gated[31:24];

// Perform parallel 8x8 signed multiplication
wire signed [15:0] p0 = a0 * b0;
wire signed [15:0] p1 = a1 * b1;
wire signed [15:0] p2 = a2 * b2;
wire signed [15:0] p3 = a3 * b3;

// Pipeline Registers (Stage 1 -> 2)
reg signed [15:0] p0_r, p1_r, p2_r, p3_r;
reg               valid_s1;
reg               start_s1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {p0_r, p1_r, p2_r, p3_r} <= 64'b0;
        {valid_s1, start_s1}     <= 2'b0;
    end else begin
        p0_r     <= p0; p1_r <= p1; p2_r <= p2; p3_r <= p3;
        valid_s1 <= enable;
        start_s1 <= start;
    end
end

// --- Stage 2: Adder Tree ---
// Sum the products (16-bit -> 17-bit -> 18-bit)
wire signed [16:0] sum_1 = $signed(p0_r) + $signed(p1_r);
wire signed [16:0] sum_2 = $signed(p2_r) + $signed(p3_r);
wire signed [17:0] dot   = $signed(sum_1) + $signed(sum_2);

// Pipeline Registers (Stage 2 -> 3)
reg signed [17:0] dot_r;
reg               valid_s2;
reg               start_s2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dot_r    <= 18'sb0;
        valid_s2 <= 1'b0;
        start_s2 <= 1'b0;
    end else begin
        dot_r    <= dot;
        valid_s2 <= valid_s1;
        start_s2 <= start_s1;
    end
end

// --- Stage 3: Accumulation & Saturation ---
// Sign-extend 18-bit dot product to 33-bit for safe accumulation
wire signed [32:0] dot_ext = $signed({ {15{dot_r[17]}}, dot_r });
wire signed [32:0] accum_next = (start_s2) ? dot_ext : ($signed(result) + dot_ext);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        result   <= 32'sb0;
        valid    <= 1'b0;
        overflow <= 1'b0;
    end else if (valid_s2) begin
        valid <= 1'b1;

        // Saturation Logic: Prevent numerical wrap-around
        if (accum_next > MAX_POS) begin
            result   <= 32'sh7FFFFFFF; 
            overflow <= 1'b1;
        end else if (accum_next < MAX_NEG) begin
            result   <= 32'sh80000000;
            overflow <= 1'b1;
        end else begin
            result   <= accum_next[31:0];
            overflow <= 1'b0;
        end
    end else begin
        valid    <= 1'b0;
        overflow <= 1'b0;
    end
end
endmodule
