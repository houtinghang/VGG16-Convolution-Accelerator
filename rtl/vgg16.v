`define HW_IMG_W 226 
`define HW_IMG_H 226
`define buffer_size 226*2+3

module vgg16 (
    input clk,
    input rst,
    input layer_sel, // 0: Layer 1, 1: Layer 2

    // --- 統一像素輸入 (Unsigned 8-bit, 0~255) ---
    input [7:0] din_0,
    input [7:0] din_1,
    input [7:0] din_2,
    input [7:0] din_3, // Layer 1 時忽略此輸入

    // --- 權重輸入 (以 Layer 2 的 4x4 需求為最大集合) ---
    // Output Channel 0 Weights
    input signed [15:0] w00_0, w00_1, w00_2, w00_3, w00_4, w00_5, w00_6, w00_7, w00_8,
    input signed [15:0] w01_0, w01_1, w01_2, w01_3, w01_4, w01_5, w01_6, w01_7, w01_8,
    input signed [15:0] w02_0, w02_1, w02_2, w02_3, w02_4, w02_5, w02_6, w02_7, w02_8,
    input signed [15:0] w03_0, w03_1, w03_2, w03_3, w03_4, w03_5, w03_6, w03_7, w03_8, // L1 忽略

    // Output Channel 1 Weights
    input signed [15:0] w10_0, w10_1, w10_2, w10_3, w10_4, w10_5, w10_6, w10_7, w10_8,
    input signed [15:0] w11_0, w11_1, w11_2, w11_3, w11_4, w11_5, w11_6, w11_7, w11_8,
    input signed [15:0] w12_0, w12_1, w12_2, w12_3, w12_4, w12_5, w12_6, w12_7, w12_8,
    input signed [15:0] w13_0, w13_1, w13_2, w13_3, w13_4, w13_5, w13_6, w13_7, w13_8, // L1 忽略

    // Output Channel 2 Weights
    input signed [15:0] w20_0, w20_1, w20_2, w20_3, w20_4, w20_5, w20_6, w20_7, w20_8,
    input signed [15:0] w21_0, w21_1, w21_2, w21_3, w21_4, w21_5, w21_6, w21_7, w21_8,
    input signed [15:0] w22_0, w22_1, w22_2, w22_3, w22_4, w22_5, w22_6, w22_7, w22_8,
    input signed [15:0] w23_0, w23_1, w23_2, w23_3, w23_4, w23_5, w23_6, w23_7, w23_8, // L1 忽略

    // Output Channel 3 Weights (Layer 1 完全不使用這組)
    input signed [15:0] w30_0, w30_1, w30_2, w30_3, w30_4, w30_5, w30_6, w30_7, w30_8,
    input signed [15:0] w31_0, w31_1, w31_2, w31_3, w31_4, w31_5, w31_6, w31_7, w31_8,
    input signed [15:0] w32_0, w32_1, w32_2, w32_3, w32_4, w32_5, w32_6, w32_7, w32_8,
    input signed [15:0] w33_0, w33_1, w33_2, w33_3, w33_4, w33_5, w33_6, w33_7, w33_8,

    // Bias
    input signed [15:0] b0, b1, b2, b3, // L1 只用 b0-b2

    // --- Layer 2 專用控制 ---
    input is_last_group,
    input signed [35:0] psum_in_ch0,
    input signed [35:0] psum_in_ch1,
    input signed [35:0] psum_in_ch2,
    input signed [35:0] psum_in_ch3,

    // --- Outputs ---
    output [7:0] out_ch0,
    output [7:0] out_ch1,
    output [7:0] out_ch2,
    output [7:0] out_ch3, // L1 時此值為 0
    
    output signed [35:0] psum_out_ch0,
    output signed [35:0] psum_out_ch1,
    output signed [35:0] psum_out_ch2,
    output signed [35:0] psum_out_ch3,

    output enable,
    output partial_valid,      // L2 專用
    output final_pixel_valid   // L2 專用
);

    // 1. 資料預處理 (Input Formatting)
    reg signed [8:0] pixel_in_formatted_0;
    reg signed [8:0] pixel_in_formatted_1;
    reg signed [8:0] pixel_in_formatted_2;
    reg signed [8:0] pixel_in_formatted_3;

    always @(*) begin
        if (layer_sel == 1'b0) begin 
            // Layer 1: 輸入減 128 (Zero-centering)
            pixel_in_formatted_0 = $signed({1'b0, din_0}) - 9'd128;
            pixel_in_formatted_1 = $signed({1'b0, din_1}) - 9'd128;
            pixel_in_formatted_2 = $signed({1'b0, din_2}) - 9'd128;
            pixel_in_formatted_3 = 9'd0; 
        end else begin
            // Layer 2: 用layer1輸入直接轉為signed
            pixel_in_formatted_0 = $signed({1'b0, din_0});
            pixel_in_formatted_1 = $signed({1'b0, din_1});
            pixel_in_formatted_2 = $signed({1'b0, din_2});
            pixel_in_formatted_3 = $signed({1'b0, din_3});
        end
    end

    // 2. Layer 1 實例化
    wire [7:0] l1_out0, l1_out1, l1_out2;
    wire l1_enable;

    vgg16_LAYER1 L1_inst (
        .clk(clk), .rst(rst),
        .pixel_c0(pixel_in_formatted_0),
        .pixel_c1(pixel_in_formatted_1),
        .pixel_c2(pixel_in_formatted_2),
        // Mapping weights
        .w00_0(w00_0), .w00_1(w00_1), .w00_2(w00_2), .w00_3(w00_3), .w00_4(w00_4), .w00_5(w00_5), .w00_6(w00_6), .w00_7(w00_7), .w00_8(w00_8),
        .w01_0(w01_0), .w01_1(w01_1), .w01_2(w01_2), .w01_3(w01_3), .w01_4(w01_4), .w01_5(w01_5), .w01_6(w01_6), .w01_7(w01_7), .w01_8(w01_8),
        .w02_0(w02_0), .w02_1(w02_1), .w02_2(w02_2), .w02_3(w02_3), .w02_4(w02_4), .w02_5(w02_5), .w02_6(w02_6), .w02_7(w02_7), .w02_8(w02_8),
        .w10_0(w10_0), .w10_1(w10_1), .w10_2(w10_2), .w10_3(w10_3), .w10_4(w10_4), .w10_5(w10_5), .w10_6(w10_6), .w10_7(w10_7), .w10_8(w10_8),
        .w11_0(w11_0), .w11_1(w11_1), .w11_2(w11_2), .w11_3(w11_3), .w11_4(w11_4), .w11_5(w11_5), .w11_6(w11_6), .w11_7(w11_7), .w11_8(w11_8),
        .w12_0(w12_0), .w12_1(w12_1), .w12_2(w12_2), .w12_3(w12_3), .w12_4(w12_4), .w12_5(w12_5), .w12_6(w12_6), .w12_7(w12_7), .w12_8(w12_8),
        .w20_0(w20_0), .w20_1(w20_1), .w20_2(w20_2), .w20_3(w20_3), .w20_4(w20_4), .w20_5(w20_5), .w20_6(w20_6), .w20_7(w20_7), .w20_8(w20_8),
        .w21_0(w21_0), .w21_1(w21_1), .w21_2(w21_2), .w21_3(w21_3), .w21_4(w21_4), .w21_5(w21_5), .w21_6(w21_6), .w21_7(w21_7), .w21_8(w21_8),
        .w22_0(w22_0), .w22_1(w22_1), .w22_2(w22_2), .w22_3(w22_3), .w22_4(w22_4), .w22_5(w22_5), .w22_6(w22_6), .w22_7(w22_7), .w22_8(w22_8),
        .b0(b0), .b1(b1), .b2(b2),
        .out_ch0(l1_out0), .out_ch1(l1_out1), .out_ch2(l1_out2), .enable(l1_enable)
    );

    // 3. Layer 2 實例化
    wire [7:0] l2_out0, l2_out1, l2_out2, l2_out3;
    wire l2_enable, l2_partial_valid, l2_final_valid;
    wire signed [35:0] l2_psum_out0, l2_psum_out1, l2_psum_out2, l2_psum_out3;

    vgg16_LAYER2 L2_inst (
        .clk(clk), .rst(rst),
        .pixel_c0(pixel_in_formatted_0),
        .pixel_c1(pixel_in_formatted_1),
        .pixel_c2(pixel_in_formatted_2),
        .pixel_c3(pixel_in_formatted_3),
        // Connecting all weights
        .w00_0(w00_0), .w00_1(w00_1), .w00_2(w00_2), .w00_3(w00_3), .w00_4(w00_4), .w00_5(w00_5), .w00_6(w00_6), .w00_7(w00_7), .w00_8(w00_8),
        .w01_0(w01_0), .w01_1(w01_1), .w01_2(w01_2), .w01_3(w01_3), .w01_4(w01_4), .w01_5(w01_5), .w01_6(w01_6), .w01_7(w01_7), .w01_8(w01_8),
        .w02_0(w02_0), .w02_1(w02_1), .w02_2(w02_2), .w02_3(w02_3), .w02_4(w02_4), .w02_5(w02_5), .w02_6(w02_6), .w02_7(w02_7), .w02_8(w02_8),
        .w03_0(w03_0), .w03_1(w03_1), .w03_2(w03_2), .w03_3(w03_3), .w03_4(w03_4), .w03_5(w03_5), .w03_6(w03_6), .w03_7(w03_7), .w03_8(w03_8),
        .w10_0(w10_0), .w10_1(w10_1), .w10_2(w10_2), .w10_3(w10_3), .w10_4(w10_4), .w10_5(w10_5), .w10_6(w10_6), .w10_7(w10_7), .w10_8(w10_8),
        .w11_0(w11_0), .w11_1(w11_1), .w11_2(w11_2), .w11_3(w11_3), .w11_4(w11_4), .w11_5(w11_5), .w11_6(w11_6), .w11_7(w11_7), .w11_8(w11_8),
        .w12_0(w12_0), .w12_1(w12_1), .w12_2(w12_2), .w12_3(w12_3), .w12_4(w12_4), .w12_5(w12_5), .w12_6(w12_6), .w12_7(w12_7), .w12_8(w12_8),
        .w13_0(w13_0), .w13_1(w13_1), .w13_2(w13_2), .w13_3(w13_3), .w13_4(w13_4), .w13_5(w13_5), .w13_6(w13_6), .w13_7(w13_7), .w13_8(w13_8),
        .w20_0(w20_0), .w20_1(w20_1), .w20_2(w20_2), .w20_3(w20_3), .w20_4(w20_4), .w20_5(w20_5), .w20_6(w20_6), .w20_7(w20_7), .w20_8(w20_8),
        .w21_0(w21_0), .w21_1(w21_1), .w21_2(w21_2), .w21_3(w21_3), .w21_4(w21_4), .w21_5(w21_5), .w21_6(w21_6), .w21_7(w21_7), .w21_8(w21_8),
        .w22_0(w22_0), .w22_1(w22_1), .w22_2(w22_2), .w22_3(w22_3), .w22_4(w22_4), .w22_5(w22_5), .w22_6(w22_6), .w22_7(w22_7), .w22_8(w22_8),
        .w23_0(w23_0), .w23_1(w23_1), .w23_2(w23_2), .w23_3(w23_3), .w23_4(w23_4), .w23_5(w23_5), .w23_6(w23_6), .w23_7(w23_7), .w23_8(w23_8),
        .w30_0(w30_0), .w30_1(w30_1), .w30_2(w30_2), .w30_3(w30_3), .w30_4(w30_4), .w30_5(w30_5), .w30_6(w30_6), .w30_7(w30_7), .w30_8(w30_8),
        .w31_0(w31_0), .w31_1(w31_1), .w31_2(w31_2), .w31_3(w31_3), .w31_4(w31_4), .w31_5(w31_5), .w31_6(w31_6), .w31_7(w31_7), .w31_8(w31_8),
        .w32_0(w32_0), .w32_1(w32_1), .w32_2(w32_2), .w32_3(w32_3), .w32_4(w32_4), .w32_5(w32_5), .w32_6(w32_6), .w32_7(w32_7), .w32_8(w32_8),
        .w33_0(w33_0), .w33_1(w33_1), .w33_2(w33_2), .w33_3(w33_3), .w33_4(w33_4), .w33_5(w33_5), .w33_6(w33_6), .w33_7(w33_7), .w33_8(w33_8),
        .b0(b0), .b1(b1), .b2(b2), .b3(b3),
        .is_last_group(is_last_group),
        .psum_in_ch0(psum_in_ch0), .psum_in_ch1(psum_in_ch1), .psum_in_ch2(psum_in_ch2), .psum_in_ch3(psum_in_ch3),
        .psum_out_ch0(l2_psum_out0), .psum_out_ch1(l2_psum_out1), .psum_out_ch2(l2_psum_out2), .psum_out_ch3(l2_psum_out3),
        .out_ch0(l2_out0), .out_ch1(l2_out1), .out_ch2(l2_out2), .out_ch3(l2_out3),
        .enable(l2_enable), .partial_valid(l2_partial_valid), .final_pixel_valid(l2_final_valid)
    );

    // 4. MUX 選擇輸出
    assign out_ch0 = (layer_sel == 1'b0) ? l1_out0 : l2_out0;
    assign out_ch1 = (layer_sel == 1'b0) ? l1_out1 : l2_out1;
    assign out_ch2 = (layer_sel == 1'b0) ? l1_out2 : l2_out2;
    assign out_ch3 = (layer_sel == 1'b0) ? 8'd0    : l2_out3;

    assign enable  = (layer_sel == 1'b0) ? l1_enable : l2_enable;
    
    assign partial_valid     = (layer_sel == 1'b1) ? l2_partial_valid : 1'b0;
    assign final_pixel_valid = (layer_sel == 1'b1) ? l2_final_valid   : 1'b0;
    
    assign psum_out_ch0 = (layer_sel == 1'b1) ? l2_psum_out0 : 36'd0;
    assign psum_out_ch1 = (layer_sel == 1'b1) ? l2_psum_out1 : 36'd0;
    assign psum_out_ch2 = (layer_sel == 1'b1) ? l2_psum_out2 : 36'd0;
    assign psum_out_ch3 = (layer_sel == 1'b1) ? l2_psum_out3 : 36'd0;

endmodule

module vgg16_LAYER1
(
    input clk,
    input rst,
    input  signed [8:0] pixel_c0,
    input  signed [8:0] pixel_c1,
    input  signed [8:0] pixel_c2,
    input  signed [15:0] w00_0, w00_1, w00_2, w00_3, w00_4, w00_5, w00_6, w00_7, w00_8,
    input  signed [15:0] w01_0, w01_1, w01_2, w01_3, w01_4, w01_5, w01_6, w01_7, w01_8,
    input  signed [15:0] w02_0, w02_1, w02_2, w02_3, w02_4, w02_5, w02_6, w02_7, w02_8,
    input  signed [15:0] w10_0, w10_1, w10_2, w10_3, w10_4, w10_5, w10_6, w10_7, w10_8,
    input  signed [15:0] w11_0, w11_1, w11_2, w11_3, w11_4, w11_5, w11_6, w11_7, w11_8,
    input  signed [15:0] w12_0, w12_1, w12_2, w12_3, w12_4, w12_5, w12_6, w12_7, w12_8,
    input  signed [15:0] w20_0, w20_1, w20_2, w20_3, w20_4, w20_5, w20_6, w20_7, w20_8,
    input  signed [15:0] w21_0, w21_1, w21_2, w21_3, w21_4, w21_5, w21_6, w21_7, w21_8,
    input  signed [15:0] w22_0, w22_1, w22_2, w22_3, w22_4, w22_5, w22_6, w22_7, w22_8,
    input  signed [15:0] b0, b1, b2,
    output [7:0] out_ch0,
    output [7:0] out_ch1,
    output [7:0] out_ch2,
    output enable
);
    wire [8:0] r0_c0,r1_c0,r2_c0,r3_c0,r4_c0,r5_c0,r6_c0,r7_c0,r8_c0;
    wire [8:0] r0_c1,r1_c1,r2_c1,r3_c1,r4_c1,r5_c1,r6_c1,r7_c1,r8_c1;
    wire [8:0] r0_c2,r1_c2,r2_c2,r3_c2,r4_c2,r5_c2,r6_c2,r7_c2,r8_c2;
    wire signed [35:0] p00, p01, p02;
    wire signed [35:0] p10, p11, p12;
    wire signed [35:0] p20, p21, p22;
    wire v00,v01,v02,v10,v11,v12,v20,v21,v22;

    Line_buffer LB0(.clk(clk), .rst(rst), .input_data(pixel_c0), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0));
    Line_buffer LB1(.clk(clk), .rst(rst), .input_data(pixel_c1), .enable(),       .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1));
    Line_buffer LB2(.clk(clk), .rst(rst), .input_data(pixel_c2), .enable(),       .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2));

    conv_3x3_ci C00(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w00_0),.w1(w00_1),.w2(w00_2),.w3(w00_3),.w4(w00_4),.w5(w00_5),.w6(w00_6),.w7(w00_7),.w8(w00_8), .partial_sum(p00), .valid(v00));
    conv_3x3_ci C01(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w01_0),.w1(w01_1),.w2(w01_2),.w3(w01_3),.w4(w01_4),.w5(w01_5),.w6(w01_6),.w7(w01_7),.w8(w01_8), .partial_sum(p01), .valid(v01));
    conv_3x3_ci C02(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w02_0),.w1(w02_1),.w2(w02_2),.w3(w02_3),.w4(w02_4),.w5(w02_5),.w6(w02_6),.w7(w02_7),.w8(w02_8), .partial_sum(p02), .valid(v02));

    conv_3x3_ci C10(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w10_0),.w1(w10_1),.w2(w10_2),.w3(w10_3),.w4(w10_4),.w5(w10_5),.w6(w10_6),.w7(w10_7),.w8(w10_8), .partial_sum(p10), .valid(v10));
    conv_3x3_ci C11(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w11_0),.w1(w11_1),.w2(w11_2),.w3(w11_3),.w4(w11_4),.w5(w11_5),.w6(w11_6),.w7(w11_7),.w8(w11_8), .partial_sum(p11), .valid(v11));
    conv_3x3_ci C12(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w12_0),.w1(w12_1),.w2(w12_2),.w3(w12_3),.w4(w12_4),.w5(w12_5),.w6(w12_6),.w7(w12_7),.w8(w12_8), .partial_sum(p12), .valid(v12));

    conv_3x3_ci C20(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w20_0),.w1(w20_1),.w2(w20_2),.w3(w20_3),.w4(w20_4),.w5(w20_5),.w6(w20_6),.w7(w20_7),.w8(w20_8), .partial_sum(p20), .valid(v20));
    conv_3x3_ci C21(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w21_0),.w1(w21_1),.w2(w21_2),.w3(w21_3),.w4(w21_4),.w5(w21_5),.w6(w21_6),.w7(w21_7),.w8(w21_8), .partial_sum(p21), .valid(v21));
    conv_3x3_ci C22(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w22_0),.w1(w22_1),.w2(w22_2),.w3(w22_3),.w4(w22_4),.w5(w22_5),.w6(w22_6),.w7(w22_7),.w8(w22_8), .partial_sum(p22), .valid(v22));

    wire signed [35:0] sum_ch0 = p00 + p01 + p02 + b0;
    wire signed [35:0] sum_ch1 = p10 + p11 + p12 + b1;
    wire signed [35:0] sum_ch2 = p20 + p21 + p22 + b2;

    ReLU_l1 RELU0(.clk(clk), .rst(rst), .con_valid1(v00), .con_valid2(v01), .con_valid3(v02), .con_valid4(1'b1), .input_data(sum_ch0), .output_data(out_ch0));
    ReLU_l1 RELU1(.clk(clk), .rst(rst), .con_valid1(v10), .con_valid2(v11), .con_valid3(v12), .con_valid4(1'b1), .input_data(sum_ch1), .output_data(out_ch1));
    ReLU_l1 RELU2(.clk(clk), .rst(rst), .con_valid1(v20), .con_valid2(v21), .con_valid3(v22), .con_valid4(1'b1), .input_data(sum_ch2), .output_data(out_ch2));
endmodule

module vgg16_LAYER2
(
    input clk,
    input rst,
    input  signed [8:0] pixel_c0,
    input  signed [8:0] pixel_c1,
    input  signed [8:0] pixel_c2,
    input  signed [8:0] pixel_c3,
    input  signed [15:0] w00_0, w00_1, w00_2, w00_3, w00_4, w00_5, w00_6, w00_7, w00_8,
    input  signed [15:0] w01_0, w01_1, w01_2, w01_3, w01_4, w01_5, w01_6, w01_7, w01_8,
    input  signed [15:0] w02_0, w02_1, w02_2, w02_3, w02_4, w02_5, w02_6, w02_7, w02_8,
    input  signed [15:0] w03_0, w03_1, w03_2, w03_3, w03_4, w03_5, w03_6, w03_7, w03_8,
    input  signed [15:0] w10_0, w10_1, w10_2, w10_3, w10_4, w10_5, w10_6, w10_7, w10_8,
    input  signed [15:0] w11_0, w11_1, w11_2, w11_3, w11_4, w11_5, w11_6, w11_7, w11_8,
    input  signed [15:0] w12_0, w12_1, w12_2, w12_3, w12_4, w12_5, w12_6, w12_7, w12_8,
    input  signed [15:0] w13_0, w13_1, w13_2, w13_3, w13_4, w13_5, w13_6, w13_7, w13_8,
    input  signed [15:0] w20_0, w20_1, w20_2, w20_3, w20_4, w20_5, w20_6, w20_7, w20_8,
    input  signed [15:0] w21_0, w21_1, w21_2, w21_3, w21_4, w21_5, w21_6, w21_7, w21_8,
    input  signed [15:0] w22_0, w22_1, w22_2, w22_3, w22_4, w22_5, w22_6, w22_7, w22_8,
    input  signed [15:0] w23_0, w23_1, w23_2, w23_3, w23_4, w23_5, w23_6, w23_7, w23_8,
    input  signed [15:0] w30_0, w30_1, w30_2, w30_3, w30_4, w30_5, w30_6, w30_7, w30_8,
    input  signed [15:0] w31_0, w31_1, w31_2, w31_3, w31_4, w31_5, w31_6, w31_7, w31_8,
    input  signed [15:0] w32_0, w32_1, w32_2, w32_3, w32_4, w32_5, w32_6, w32_7, w32_8,
    input  signed [15:0] w33_0, w33_1, w33_2, w33_3, w33_4, w33_5, w33_6, w33_7, w33_8,
    input  signed [15:0] b0, b1, b2, b3,
    input is_last_group,
    input signed [35:0] psum_in_ch0, psum_in_ch1, psum_in_ch2, psum_in_ch3,
    output signed [35:0] psum_out_ch0, psum_out_ch1, psum_out_ch2, psum_out_ch3,
    output [7:0] out_ch0, out_ch1, out_ch2, out_ch3,
    output enable, partial_valid, final_pixel_valid
);
    wire signed[8:0] r0_c0,r1_c0,r2_c0,r3_c0,r4_c0,r5_c0,r6_c0,r7_c0,r8_c0;
    wire signed[8:0] r0_c1,r1_c1,r2_c1,r3_c1,r4_c1,r5_c1,r6_c1,r7_c1,r8_c1;
    wire signed[8:0] r0_c2,r1_c2,r2_c2,r3_c2,r4_c2,r5_c2,r6_c2,r7_c2,r8_c2;
    wire signed[8:0] r0_c3,r1_c3,r2_c3,r3_c3,r4_c3,r5_c3,r6_c3,r7_c3,r8_c3;

    Line_buffer LB0(.clk(clk), .rst(rst), .input_data(pixel_c0), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0));
    Line_buffer LB1(.clk(clk), .rst(rst), .input_data(pixel_c1), .enable(),       .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1));
    Line_buffer LB2(.clk(clk), .rst(rst), .input_data(pixel_c2), .enable(),       .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2));
    Line_buffer LB3(.clk(clk), .rst(rst), .input_data(pixel_c3), .enable(),       .r0(r0_c3),.r1(r1_c3),.r2(r2_c3),.r3(r3_c3),.r4(r4_c3),.r5(r5_c3),.r6(r6_c3),.r7(r7_c3),.r8(r8_c3));

    wire signed [35:0] p00, p01, p02, p03, p10, p11, p12, p13, p20, p21, p22, p23, p30, p31, p32, p33;
    wire v00,v01,v02,v03, v10,v11,v12,v13, v20,v21,v22,v23, v30,v31,v32,v33;

    conv_3x3_ci C00(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w00_0),.w1(w00_1),.w2(w00_2),.w3(w00_3),.w4(w00_4),.w5(w00_5),.w6(w00_6),.w7(w00_7),.w8(w00_8), .partial_sum(p00), .valid(v00));
    conv_3x3_ci C01(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w01_0),.w1(w01_1),.w2(w01_2),.w3(w01_3),.w4(w01_4),.w5(w01_5),.w6(w01_6),.w7(w01_7),.w8(w01_8), .partial_sum(p01), .valid(v01));
    conv_3x3_ci C02(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w02_0),.w1(w02_1),.w2(w02_2),.w3(w02_3),.w4(w02_4),.w5(w02_5),.w6(w02_6),.w7(w02_7),.w8(w02_8), .partial_sum(p02), .valid(v02));
    conv_3x3_ci C03(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c3),.r1(r1_c3),.r2(r2_c3),.r3(r3_c3),.r4(r4_c3),.r5(r5_c3),.r6(r6_c3),.r7(r7_c3),.r8(r8_c3), .w0(w03_0),.w1(w03_1),.w2(w03_2),.w3(w03_3),.w4(w03_4),.w5(w03_5),.w6(w03_6),.w7(w03_7),.w8(w03_8), .partial_sum(p03), .valid(v03));

    conv_3x3_ci C10(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w10_0),.w1(w10_1),.w2(w10_2),.w3(w10_3),.w4(w10_4),.w5(w10_5),.w6(w10_6),.w7(w10_7),.w8(w10_8), .partial_sum(p10), .valid(v10));
    conv_3x3_ci C11(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w11_0),.w1(w11_1),.w2(w11_2),.w3(w11_3),.w4(w11_4),.w5(w11_5),.w6(w11_6),.w7(w11_7),.w8(w11_8), .partial_sum(p11), .valid(v11));
    conv_3x3_ci C12(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w12_0),.w1(w12_1),.w2(w12_2),.w3(w12_3),.w4(w12_4),.w5(w12_5),.w6(w12_6),.w7(w12_7),.w8(w12_8), .partial_sum(p12), .valid(v12));
    conv_3x3_ci C13(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c3),.r1(r1_c3),.r2(r2_c3),.r3(r3_c3),.r4(r4_c3),.r5(r5_c3),.r6(r6_c3),.r7(r7_c3),.r8(r8_c3), .w0(w13_0),.w1(w13_1),.w2(w13_2),.w3(w13_3),.w4(w13_4),.w5(w13_5),.w6(w13_6),.w7(w13_7),.w8(w13_8), .partial_sum(p13), .valid(v13));

    conv_3x3_ci C20(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w20_0),.w1(w20_1),.w2(w20_2),.w3(w20_3),.w4(w20_4),.w5(w20_5),.w6(w20_6),.w7(w20_7),.w8(w20_8), .partial_sum(p20), .valid(v20));
    conv_3x3_ci C21(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w21_0),.w1(w21_1),.w2(w21_2),.w3(w21_3),.w4(w21_4),.w5(w21_5),.w6(w21_6),.w7(w21_7),.w8(w21_8), .partial_sum(p21), .valid(v21));
    conv_3x3_ci C22(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w22_0),.w1(w22_1),.w2(w22_2),.w3(w22_3),.w4(w22_4),.w5(w22_5),.w6(w22_6),.w7(w22_7),.w8(w22_8), .partial_sum(p22), .valid(v22));
    conv_3x3_ci C23(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c3),.r1(r1_c3),.r2(r2_c3),.r3(r3_c3),.r4(r4_c3),.r5(r5_c3),.r6(r6_c3),.r7(r7_c3),.r8(r8_c3), .w0(w23_0),.w1(w23_1),.w2(w23_2),.w3(w23_3),.w4(w23_4),.w5(w23_5),.w6(w23_6),.w7(w23_7),.w8(w23_8), .partial_sum(p23), .valid(v23));

    conv_3x3_ci C30(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c0),.r1(r1_c0),.r2(r2_c0),.r3(r3_c0),.r4(r4_c0),.r5(r5_c0),.r6(r6_c0),.r7(r7_c0),.r8(r8_c0), .w0(w30_0),.w1(w30_1),.w2(w30_2),.w3(w30_3),.w4(w30_4),.w5(w30_5),.w6(w30_6),.w7(w30_7),.w8(w30_8), .partial_sum(p30), .valid(v30));
    conv_3x3_ci C31(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c1),.r1(r1_c1),.r2(r2_c1),.r3(r3_c1),.r4(r4_c1),.r5(r5_c1),.r6(r6_c1),.r7(r7_c1),.r8(r8_c1), .w0(w31_0),.w1(w31_1),.w2(w31_2),.w3(w31_3),.w4(w31_4),.w5(w31_5),.w6(w31_6),.w7(w31_7),.w8(w31_8), .partial_sum(p31), .valid(v31));
    conv_3x3_ci C32(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c2),.r1(r1_c2),.r2(r2_c2),.r3(r3_c2),.r4(r4_c2),.r5(r5_c2),.r6(r6_c2),.r7(r7_c2),.r8(r8_c2), .w0(w32_0),.w1(w32_1),.w2(w32_2),.w3(w32_3),.w4(w32_4),.w5(w32_5),.w6(w32_6),.w7(w32_7),.w8(w32_8), .partial_sum(p32), .valid(v32));
    conv_3x3_ci C33(.clk(clk), .rst(rst), .enable(enable), .r0(r0_c3),.r1(r1_c3),.r2(r2_c3),.r3(r3_c3),.r4(r4_c3),.r5(r5_c3),.r6(r6_c3),.r7(r7_c3),.r8(r8_c3), .w0(w33_0),.w1(w33_1),.w2(w33_2),.w3(w33_3),.w4(w33_4),.w5(w33_5),.w6(w33_6),.w7(w33_7),.w8(w33_8), .partial_sum(p33), .valid(v33));

    wire signed [35:0] conv_sum_ch0 = p00 + p01 + p02 + p03;
    wire signed [35:0] conv_sum_ch1 = p10 + p11 + p12 + p13;
    wire signed [35:0] conv_sum_ch2 = p20 + p21 + p22 + p23;
    wire signed [35:0] conv_sum_ch3 = p30 + p31 + p32 + p33;

    wire conv_valid_all = (v00 && v01 && v02 && v03) && (v10 && v11 && v12 && v13) && (v20 && v21 && v22 && v23) && (v30 && v31 && v32 && v33);

    wire signed [35:0] current_total_ch0 = conv_sum_ch0 + psum_in_ch0;
    wire signed [35:0] current_total_ch1 = conv_sum_ch1 + psum_in_ch1;
    wire signed [35:0] current_total_ch2 = conv_sum_ch2 + psum_in_ch2;
    wire signed [35:0] current_total_ch3 = conv_sum_ch3 + psum_in_ch3;

    assign psum_out_ch0 = current_total_ch0;
    assign psum_out_ch1 = current_total_ch1;
    assign psum_out_ch2 = current_total_ch2;
    assign psum_out_ch3 = current_total_ch3;
    assign partial_valid = conv_valid_all;

    wire signed [35:0] bias0_ext = {{20{b0[15]}}, b0};
    wire signed [35:0] bias1_ext = {{20{b1[15]}}, b1};
    wire signed [35:0] bias2_ext = {{20{b2[15]}}, b2};
    wire signed [35:0] bias3_ext = {{20{b3[15]}}, b3};

    wire signed [35:0] final_sum_ch0 = is_last_group ? (current_total_ch0 + bias0_ext) : 36'd0;
    wire signed [35:0] final_sum_ch1 = is_last_group ? (current_total_ch1 + bias1_ext) : 36'd0;
    wire signed [35:0] final_sum_ch2 = is_last_group ? (current_total_ch2 + bias2_ext) : 36'd0;
    wire signed [35:0] final_sum_ch3 = is_last_group ? (current_total_ch3 + bias3_ext) : 36'd0;

    wire final_valid_comb = is_last_group && conv_valid_all;
    reg final_valid_d1;
    always @(posedge clk) begin
        if (rst) final_valid_d1 <= 1'b0;
        else     final_valid_d1 <= final_valid_comb;
    end
    assign final_pixel_valid = final_valid_d1;

    ReLU_l2 RELU0(.clk(clk), .rst(rst), .con_valid1(final_valid_comb), .input_data(final_sum_ch0), .output_data(out_ch0));
    ReLU_l2 RELU1(.clk(clk), .rst(rst), .con_valid1(final_valid_comb), .input_data(final_sum_ch1), .output_data(out_ch1));
    ReLU_l2 RELU2(.clk(clk), .rst(rst), .con_valid1(final_valid_comb), .input_data(final_sum_ch2), .output_data(out_ch2));
    ReLU_l2 RELU3(.clk(clk), .rst(rst), .con_valid1(final_valid_comb), .input_data(final_sum_ch3), .output_data(out_ch3));
endmodule

module Line_buffer(
    input clk, rst,
    input signed [8:0] input_data,
    output reg enable,
    output signed [8:0] r0,r1,r2,r3,r4,r5,r6,r7,r8
    );
    integer i;
    reg [8:0]  Line_buffers [`buffer_size-1:0];
    reg [31:0] counter;

    assign r0 = Line_buffers[0];
    assign r1 = Line_buffers[1];
    assign r2 = Line_buffers[2];
    assign r3 = Line_buffers[`HW_IMG_W];
    assign r4 = Line_buffers[`HW_IMG_W+1];
    assign r5 = Line_buffers[`HW_IMG_W+2];
    assign r6 = Line_buffers[`HW_IMG_W*2];
    assign r7 = Line_buffers[`HW_IMG_W*2+1];
    assign r8 = Line_buffers[`HW_IMG_W*2+2];

    always@( posedge clk ) begin
        if ( rst ) begin
            for( i=0;i<`buffer_size;i=i+1 ) Line_buffers[i] <= 9'b0;
        end
        else begin
            for( i=1;i<`buffer_size;i=i+1 ) Line_buffers[i-1] <= Line_buffers[i];
            Line_buffers[`buffer_size-1] <= input_data;
        end   
    end

    always@( posedge clk ) begin
        if ( rst ) counter <= 32'b0;
        else counter <= counter+1;
    end

    always @(*) begin
        if (rst) enable = 1'b0;
        else if (counter < (`HW_IMG_W*2 + 2)) enable = 1'b0;
        else if (counter >= (`HW_IMG_W*`HW_IMG_W)) enable = 1'b0;
        else if ((counter % `HW_IMG_W) == 0 || (counter % `HW_IMG_W) == 1) enable = 1'b0;
        else enable = 1'b1;
    end
endmodule

//adder tree for 3x3 convolution + pegroup
module conv_3x3_ci(
    input clk, rst, enable,
    input signed [8:0] r0,r1,r2,r3,r4,r5,r6,r7,r8,
    input signed [15:0] w0,w1,w2,w3,w4,w5,w6,w7,w8,
    output reg signed [35:0] partial_sum,
    output reg valid
    );
    reg signed [35:0] sum;
    reg signed [35:0] temp1 , temp2, temp3, temp4, temp5, temp6, temp7;
    always@( posedge clk ) begin
        if ( rst ) begin
            partial_sum <= 36'b0;
            valid <= 1'b0;
        end else if ( enable ) begin
            temp1 = r0 * w0 + r1 * w1;
            temp2 = r2 * w2 + r3 * w3;
            temp3 = r4 * w4 + r5 * w5;
            temp4 = r6 * w6 + r7 * w7;
            temp5 = temp1 + temp2;
            temp6 = temp3 + temp4;
            temp7 = temp5 + temp6;
            sum = temp7 + r8 * w8;
            partial_sum <= sum;
            valid <= 1'b1;
        end else begin
            partial_sum <= 36'b0;
            valid <= 1'b0;
        end
    end
endmodule

module ReLU_l1(
    input clk,rst,
    input con_valid1,con_valid2,con_valid3,con_valid4,
    input signed [35:0] input_data,
    output reg [7:0] output_data
    );
    always@( posedge clk ) begin
        if ( rst ) output_data <= 8'b0;
        else if (!(con_valid1&&con_valid2&&con_valid3&&con_valid4)) output_data <= 8'b0;
        else if (input_data[35]) output_data <= 8'b0;
        else begin
            if (|input_data[35:12]) output_data <= 8'hFF;
            else output_data <= input_data[11:4];
        end
    end
endmodule

module ReLU_l2(
    input clk,rst,
    input con_valid1,
    input signed [35:0] input_data,
    output reg [7:0] output_data
    );
    always@( posedge clk ) begin
        if ( rst ) output_data <= 8'b0;
        else if (!(con_valid1)) output_data <= 8'b0;
        else if (input_data[35]) output_data <= 8'b0;
        else begin
            if (|input_data[35:15]) output_data <= 8'hFF;
            else output_data <= input_data[14:7];
        end
    end
endmodule