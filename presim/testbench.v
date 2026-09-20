`timescale 1ns / 1ns
`define period 10
`define IMG_W 224
`define IMG_H 224
`define PAD_W 226
`define PAD_H 226
`define img_max_size     (`IMG_W*`IMG_H*3 + 54)
`define padding_img_size (`PAD_W*`PAD_H)
`define OUT_CH_PER_BATCH 3
`define TOTAL_OUT_CH 64

// Layer 1 相關路徑
`define path_img_in       "data/cat224.bmp"
`define path_weights      "data/conv1_kernel_hex.txt"
`define path_bias         "data/conv1_bias_hex.txt"
`define path_img_out_fmt  "build/layer1/cat_layer1_ch%0d.bmp"

// Layer 2 相關路徑
`define path_layer1_img_in    "build/layer1/cat_layer1_ch0.bmp"
`define layer2_img_in_fmt     "build/layer1/cat_layer1_ch%0d.bmp"
`define layer2_weights        "data/conv2_kernel_hex.txt"
`define layer2_bias           "data/conv2_bias_hex.txt"
`define layer2_img_out_fmt    "build/layer2/cat_layer2_ch%0d.bmp"

`define LAYER2_IN_CH 64
`define LAYER2_OUT_CH 64
`define LAYER2_IN_PER_BATCH 4
`define LAYER2_OUT_PER_BATCH 4

module HDL_HW5_TB;
    integer img_in;
    integer wf_weights;
    integer wf_bias;
    integer header;
    integer idx, h, w;
    integer img_h, img_w, offset;
    
    reg [8*128-1:0] out_path;

    // 分批處理變數
    integer batch;
    integer global_ch;
    integer ch_in_batch;
    integer input_group;
    integer output_batch;

    reg [7:0] img_data [0:`img_max_size-1];

    reg [7:0] padding_img [0:3][0:`padding_img_size-1];

    reg clk;
    reg rst;
    reg layer_sel; // 0: Layer 1, 1: Layer 2

    // Layer 1 權重與 Bias
    integer fout[0:`OUT_CH_PER_BATCH-1];
    
    // 輸入給 Top Module 的像素 (8-bit)
    reg [7:0] pixel_in_0;
    reg [7:0] pixel_in_1;
    reg [7:0] pixel_in_2;
    reg [7:0] pixel_in_3;

    reg signed [15:0] w00 [0:8];
    reg signed [15:0] w01 [0:8];
    reg signed [15:0] w02 [0:8];
    reg signed [15:0] w10 [0:8];
    reg signed [15:0] w11 [0:8];
    reg signed [15:0] w12 [0:8];
    reg signed [15:0] w20 [0:8];
    reg signed [15:0] w21 [0:8];
    reg signed [15:0] w22 [0:8];
    reg signed [15:0] b0,b1,b2;

    // 輸出信號
    wire [7:0] out_ch0, out_ch1, out_ch2, out_ch3;
    wire [7:0] out_ch[0:3];
    assign out_ch[0]=out_ch0;
    assign out_ch[1]=out_ch1;
    assign out_ch[2]=out_ch2;
    assign out_ch[3]=out_ch3;
    wire enable;

    // Layer 2 信號
    integer layer2_img_files[0:`LAYER2_IN_PER_BATCH-1];
    integer layer2_fout[0:`LAYER2_OUT_PER_BATCH-1];
    
    // Layer 2 讀圖暫存
    reg [7:0] layer2_img_data_0 [0:`img_max_size-1];
    reg [7:0] layer2_img_data_1 [0:`img_max_size-1];
    reg [7:0] layer2_img_data_2 [0:`img_max_size-1];
    reg [7:0] layer2_img_data_3 [0:`img_max_size-1];
    reg [7:0] pixel_val;
    
    // Layer 2 權重 (4 output x 4 input x 9 weights)
    reg signed [15:0] w2_00[0:8], w2_01[0:8], w2_02[0:8], w2_03[0:8];
    reg signed [15:0] w2_10[0:8], w2_11[0:8], w2_12[0:8], w2_13[0:8];
    reg signed [15:0] w2_20[0:8], w2_21[0:8], w2_22[0:8], w2_23[0:8];
    reg signed [15:0] w2_30[0:8], w2_31[0:8], w2_32[0:8], w2_33[0:8];
    reg signed [15:0] b2_0, b2_1, b2_2, b2_3;

    wire is_last_group;
    wire layer2_partial_valid;
    wire layer2_final_pixel_valid;

    assign is_last_group = (input_group == 15);

    // Layer 2 Psum Memory
    reg signed [35:0] tb_psum_mem [0:3][0:52000];
    reg signed [35:0] tb_psum_in_ch0, tb_psum_in_ch1, tb_psum_in_ch2, tb_psum_in_ch3;
    wire signed [35:0] tb_psum_out_ch0, tb_psum_out_ch1, tb_psum_out_ch2, tb_psum_out_ch3;
    
    integer out_idx;
    integer flush_guard;
    integer psum_read_idx;
    integer latency;
    integer effective_cnt;

    vgg16 top_dut(
        .clk(clk), .rst(rst), .layer_sel(layer_sel),
        
        // 統一輸入介面 (8-bit unsigned)
        .din_0(pixel_in_0), .din_1(pixel_in_1), .din_2(pixel_in_2), .din_3(pixel_in_3),

        // --- 權重映射 (利用 MUX 切換 L1/L2 權重) ---
        // Output Ch 0
        .w00_0(layer_sel ? w2_00[0] : w00[0]), .w00_1(layer_sel ? w2_00[1] : w00[1]), .w00_2(layer_sel ? w2_00[2] : w00[2]), .w00_3(layer_sel ? w2_00[3] : w00[3]), .w00_4(layer_sel ? w2_00[4] : w00[4]), .w00_5(layer_sel ? w2_00[5] : w00[5]), .w00_6(layer_sel ? w2_00[6] : w00[6]), .w00_7(layer_sel ? w2_00[7] : w00[7]), .w00_8(layer_sel ? w2_00[8] : w00[8]),
        .w01_0(layer_sel ? w2_01[0] : w01[0]), .w01_1(layer_sel ? w2_01[1] : w01[1]), .w01_2(layer_sel ? w2_01[2] : w01[2]), .w01_3(layer_sel ? w2_01[3] : w01[3]), .w01_4(layer_sel ? w2_01[4] : w01[4]), .w01_5(layer_sel ? w2_01[5] : w01[5]), .w01_6(layer_sel ? w2_01[6] : w01[6]), .w01_7(layer_sel ? w2_01[7] : w01[7]), .w01_8(layer_sel ? w2_01[8] : w01[8]),
        .w02_0(layer_sel ? w2_02[0] : w02[0]), .w02_1(layer_sel ? w2_02[1] : w02[1]), .w02_2(layer_sel ? w2_02[2] : w02[2]), .w02_3(layer_sel ? w2_02[3] : w02[3]), .w02_4(layer_sel ? w2_02[4] : w02[4]), .w02_5(layer_sel ? w2_02[5] : w02[5]), .w02_6(layer_sel ? w2_02[6] : w02[6]), .w02_7(layer_sel ? w2_02[7] : w02[7]), .w02_8(layer_sel ? w2_02[8] : w02[8]),
        .w03_0(layer_sel ? w2_03[0] : 16'd0),  .w03_1(layer_sel ? w2_03[1] : 16'd0),  .w03_2(layer_sel ? w2_03[2] : 16'd0),  .w03_3(layer_sel ? w2_03[3] : 16'd0),  .w03_4(layer_sel ? w2_03[4] : 16'd0),  .w03_5(layer_sel ? w2_03[5] : 16'd0),  .w03_6(layer_sel ? w2_03[6] : 16'd0),  .w03_7(layer_sel ? w2_03[7] : 16'd0),  .w03_8(layer_sel ? w2_03[8] : 16'd0),
        
        // Output Ch 1
        .w10_0(layer_sel ? w2_10[0] : w10[0]), .w10_1(layer_sel ? w2_10[1] : w10[1]), .w10_2(layer_sel ? w2_10[2] : w10[2]), .w10_3(layer_sel ? w2_10[3] : w10[3]), .w10_4(layer_sel ? w2_10[4] : w10[4]), .w10_5(layer_sel ? w2_10[5] : w10[5]), .w10_6(layer_sel ? w2_10[6] : w10[6]), .w10_7(layer_sel ? w2_10[7] : w10[7]), .w10_8(layer_sel ? w2_10[8] : w10[8]),
        .w11_0(layer_sel ? w2_11[0] : w11[0]), .w11_1(layer_sel ? w2_11[1] : w11[1]), .w11_2(layer_sel ? w2_11[2] : w11[2]), .w11_3(layer_sel ? w2_11[3] : w11[3]), .w11_4(layer_sel ? w2_11[4] : w11[4]), .w11_5(layer_sel ? w2_11[5] : w11[5]), .w11_6(layer_sel ? w2_11[6] : w11[6]), .w11_7(layer_sel ? w2_11[7] : w11[7]), .w11_8(layer_sel ? w2_11[8] : w11[8]),
        .w12_0(layer_sel ? w2_12[0] : w12[0]), .w12_1(layer_sel ? w2_12[1] : w12[1]), .w12_2(layer_sel ? w2_12[2] : w12[2]), .w12_3(layer_sel ? w2_12[3] : w12[3]), .w12_4(layer_sel ? w2_12[4] : w12[4]), .w12_5(layer_sel ? w2_12[5] : w12[5]), .w12_6(layer_sel ? w2_12[6] : w12[6]), .w12_7(layer_sel ? w2_12[7] : w12[7]), .w12_8(layer_sel ? w2_12[8] : w12[8]),
        .w13_0(layer_sel ? w2_13[0] : 16'd0),  .w13_1(layer_sel ? w2_13[1] : 16'd0),  .w13_2(layer_sel ? w2_13[2] : 16'd0),  .w13_3(layer_sel ? w2_13[3] : 16'd0),  .w13_4(layer_sel ? w2_13[4] : 16'd0),  .w13_5(layer_sel ? w2_13[5] : 16'd0),  .w13_6(layer_sel ? w2_13[6] : 16'd0),  .w13_7(layer_sel ? w2_13[7] : 16'd0),  .w13_8(layer_sel ? w2_13[8] : 16'd0),
        
        // Output Ch 2
        .w20_0(layer_sel ? w2_20[0] : w20[0]), .w20_1(layer_sel ? w2_20[1] : w20[1]), .w20_2(layer_sel ? w2_20[2] : w20[2]), .w20_3(layer_sel ? w2_20[3] : w20[3]), .w20_4(layer_sel ? w2_20[4] : w20[4]), .w20_5(layer_sel ? w2_20[5] : w20[5]), .w20_6(layer_sel ? w2_20[6] : w20[6]), .w20_7(layer_sel ? w2_20[7] : w20[7]), .w20_8(layer_sel ? w2_20[8] : w20[8]),
        .w21_0(layer_sel ? w2_21[0] : w21[0]), .w21_1(layer_sel ? w2_21[1] : w21[1]), .w21_2(layer_sel ? w2_21[2] : w21[2]), .w21_3(layer_sel ? w2_21[3] : w21[3]), .w21_4(layer_sel ? w2_21[4] : w21[4]), .w21_5(layer_sel ? w2_21[5] : w21[5]), .w21_6(layer_sel ? w2_21[6] : w21[6]), .w21_7(layer_sel ? w2_21[7] : w21[7]), .w21_8(layer_sel ? w2_21[8] : w21[8]),
        .w22_0(layer_sel ? w2_22[0] : w22[0]), .w22_1(layer_sel ? w2_22[1] : w22[1]), .w22_2(layer_sel ? w2_22[2] : w22[2]), .w22_3(layer_sel ? w2_22[3] : w22[3]), .w22_4(layer_sel ? w2_22[4] : w22[4]), .w22_5(layer_sel ? w2_22[5] : w22[5]), .w22_6(layer_sel ? w2_22[6] : w22[6]), .w22_7(layer_sel ? w2_22[7] : w22[7]), .w22_8(layer_sel ? w2_22[8] : w22[8]),
        .w23_0(layer_sel ? w2_23[0] : 16'd0),  .w23_1(layer_sel ? w2_23[1] : 16'd0),  .w23_2(layer_sel ? w2_23[2] : 16'd0),  .w23_3(layer_sel ? w2_23[3] : 16'd0),  .w23_4(layer_sel ? w2_23[4] : 16'd0),  .w23_5(layer_sel ? w2_23[5] : 16'd0),  .w23_6(layer_sel ? w2_23[6] : 16'd0),  .w23_7(layer_sel ? w2_23[7] : 16'd0),  .w23_8(layer_sel ? w2_23[8] : 16'd0),
        
        // Output Ch 3 (L1 時輸入0)
        .w30_0(layer_sel ? w2_30[0] : 16'd0), .w30_1(layer_sel ? w2_30[1] : 16'd0), .w30_2(layer_sel ? w2_30[2] : 16'd0), .w30_3(layer_sel ? w2_30[3] : 16'd0), .w30_4(layer_sel ? w2_30[4] : 16'd0), .w30_5(layer_sel ? w2_30[5] : 16'd0), .w30_6(layer_sel ? w2_30[6] : 16'd0), .w30_7(layer_sel ? w2_30[7] : 16'd0), .w30_8(layer_sel ? w2_30[8] : 16'd0),
        .w31_0(layer_sel ? w2_31[0] : 16'd0), .w31_1(layer_sel ? w2_31[1] : 16'd0), .w31_2(layer_sel ? w2_31[2] : 16'd0), .w31_3(layer_sel ? w2_31[3] : 16'd0), .w31_4(layer_sel ? w2_31[4] : 16'd0), .w31_5(layer_sel ? w2_31[5] : 16'd0), .w31_6(layer_sel ? w2_31[6] : 16'd0), .w31_7(layer_sel ? w2_31[7] : 16'd0), .w31_8(layer_sel ? w2_31[8] : 16'd0),
        .w32_0(layer_sel ? w2_32[0] : 16'd0), .w32_1(layer_sel ? w2_32[1] : 16'd0), .w32_2(layer_sel ? w2_32[2] : 16'd0), .w32_3(layer_sel ? w2_32[3] : 16'd0), .w32_4(layer_sel ? w2_32[4] : 16'd0), .w32_5(layer_sel ? w2_32[5] : 16'd0), .w32_6(layer_sel ? w2_32[6] : 16'd0), .w32_7(layer_sel ? w2_32[7] : 16'd0), .w32_8(layer_sel ? w2_32[8] : 16'd0),
        .w33_0(layer_sel ? w2_33[0] : 16'd0), .w33_1(layer_sel ? w2_33[1] : 16'd0), .w33_2(layer_sel ? w2_33[2] : 16'd0), .w33_3(layer_sel ? w2_33[3] : 16'd0), .w33_4(layer_sel ? w2_33[4] : 16'd0), .w33_5(layer_sel ? w2_33[5] : 16'd0), .w33_6(layer_sel ? w2_33[6] : 16'd0), .w33_7(layer_sel ? w2_33[7] : 16'd0), .w33_8(layer_sel ? w2_33[8] : 16'd0),

        .b0(layer_sel ? b2_0 : b0), 
        .b1(layer_sel ? b2_1 : b1), 
        .b2(layer_sel ? b2_2 : b2), 
        .b3(layer_sel ? b2_3 : 16'd0),

        .is_last_group(is_last_group),
        
        // Psum
        .psum_in_ch0(tb_psum_in_ch0), .psum_in_ch1(tb_psum_in_ch1), .psum_in_ch2(tb_psum_in_ch2), .psum_in_ch3(tb_psum_in_ch3),
        .psum_out_ch0(tb_psum_out_ch0), .psum_out_ch1(tb_psum_out_ch1), .psum_out_ch2(tb_psum_out_ch2), .psum_out_ch3(tb_psum_out_ch3),
        
        // Output
        .out_ch0(out_ch0), .out_ch1(out_ch1), .out_ch2(out_ch2), .out_ch3(out_ch3),
        .enable(enable), .partial_valid(layer2_partial_valid), .final_pixel_valid(layer2_final_pixel_valid)
    );

    always #(`period/2) clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        layer_sel = 0; // 開始為 Layer 1
        #50;
        rst = 0;
        @(negedge clk);
        
        // ==================== LAYER 1 處理 ====================
        $display("=== Starting Layer 1 Processing ===");
       
        img_in = $fopen(`path_img_in,"rb");
        if(img_in==0) begin $display("Open image fail"); $finish; end
        $fread(img_data,img_in);
        img_w = {img_data[21],img_data[20],img_data[19],img_data[18]};
        img_h = {img_data[25],img_data[24],img_data[23],img_data[22]};
        offset = {img_data[13],img_data[12],img_data[11],img_data[10]};
       
        // 初始化 padding_img (8-bit)
        for(idx=0; idx<`padding_img_size; idx=idx+1) begin
            padding_img[0][idx]=8'd0;
            padding_img[1][idx]=8'd0;
            padding_img[2][idx]=8'd0;
        end
       
        // 填充圖片 (注意：這裡不再做 -128，Top Module 會做)
        for(h=0; h<img_h; h=h+1)
            for(w=0; w<img_w; w=w+1) begin
                padding_img[0][h*`PAD_W+w+(`PAD_W+1)] = img_data[(h*img_w+w)*3+offset+2];
                padding_img[1][h*`PAD_W+w+(`PAD_W+1)] = img_data[(h*img_w+w)*3+offset+1];
                padding_img[2][h*`PAD_W+w+(`PAD_W+1)] = img_data[(h*img_w+w)*3+offset+0];
            end
        $fclose(img_in);

        wf_weights = $fopen(`path_weights,"r");
        if(wf_weights==0) begin $display("Open weights fail"); $finish; end
        wf_bias = $fopen(`path_bias,"r");
        if(wf_bias==0) begin $display("Open bias fail"); $finish; end

        for (batch = 0; batch < 22; batch = batch + 1) begin
            $display("Layer 1: Processing Batch %0d / 21 ...", batch);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w00[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w01[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w02[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w10[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w11[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w12[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w20[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w21[idx]);
            for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w22[idx]);
            $fscanf(wf_bias,"%h", b0);
            $fscanf(wf_bias,"%h", b1);
            $fscanf(wf_bias,"%h", b2);
            
            rst = 1; #50; rst = 0; @(negedge clk);
            
            for(ch_in_batch=0; ch_in_batch<`OUT_CH_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                global_ch = batch * `OUT_CH_PER_BATCH + ch_in_batch;
                if (global_ch < `TOTAL_OUT_CH) begin
                    $sformat(out_path, `path_img_out_fmt, global_ch);
                    fout[ch_in_batch] = $fopen(out_path,"wb");
                    for(header=0; header<54; header=header+1)
                        $fwrite(fout[ch_in_batch], "%c", img_data[header]);
                end else begin
                    fout[ch_in_batch] = 0;
                end
            end

            for(idx=0; idx<`padding_img_size; idx=idx+1) begin
                pixel_in_0 <= padding_img[0][idx];
                pixel_in_1 <= padding_img[1][idx];
                pixel_in_2 <= padding_img[2][idx];
                pixel_in_3 <= 8'd0; // L1 不用 Ch3
                
                @(posedge clk);
                // Top module 內部 Line buffer 有延遲，這裡假設邏輯與原設計相同
                // 使用原設計的 enable_d1 邏輯推算 (簡化：若 enable 為真則寫入)
                if(enable) begin
                    for(ch_in_batch=0; ch_in_batch<`OUT_CH_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                       if (fout[ch_in_batch] != 0) begin
                           $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                           $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                           $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                       end
                    end
                end
            end
            
            // Flush pipeline
            repeat(2) begin
                @(posedge clk);
                if(enable) begin
                    for(ch_in_batch=0; ch_in_batch<`OUT_CH_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                        if (fout[ch_in_batch] != 0) begin
                            $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                            $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                            $fwrite(fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                        end
                    end
                end
            end

            for(ch_in_batch=0; ch_in_batch<`OUT_CH_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
               if (fout[ch_in_batch] != 0) $fclose(fout[ch_in_batch]);
            end
            #100;
        end
        $fclose(wf_weights);
        $fclose(wf_bias);
        $display("=== Layer 1 Completed ===\n");

       // ==================== LAYER 2 處理 ====================
        $display("=== Starting Layer 2 Processing ===");
        layer_sel = 1; // 切換 Top Module 到 Layer 2 模式

        img_in = $fopen(`path_layer1_img_in, "rb");
        if(img_in == 0) begin
            $display("Error: Cannot open %s", `path_layer1_img_in);
            $finish;
        end
        $fread(img_data, img_in);
        img_w = {img_data[21],img_data[20],img_data[19],img_data[18]};
        img_h = {img_data[25],img_data[24],img_data[23],img_data[22]};
        offset = {img_data[13],img_data[12],img_data[11],img_data[10]};
        $fclose(img_in);

        wf_weights = $fopen(`layer2_weights,"r");
        if(wf_weights==0) begin $display("Open layer2 weights fail"); $finish; end
        
        wf_bias = $fopen(`layer2_bias,"r");
        if(wf_bias==0) begin $display("Open layer2 bias fail"); $finish; end

        // Layer 2: 處理 16 個 output batch
        for (output_batch = 0; output_batch < 4; output_batch = output_batch + 1) begin
            $display("Layer 2: Processing Output Batch %0d / 15 ...", output_batch);
            latency = 454;
            // Clear Psum memory
            for(idx=0; idx<52000; idx=idx+1) begin
                tb_psum_mem[0][idx] = 0;
                tb_psum_mem[1][idx] = 0;
                tb_psum_mem[2][idx] = 0;
                tb_psum_mem[3][idx] = 0;
            end

            for (input_group = 0; input_group < 16; input_group = input_group + 1) begin
                $display("  Input Group %0d / 15", input_group);
                flush_guard = 0;
                psum_read_idx = 0;
                rst = 1; #50; rst = 0; @(negedge clk);

                // 讀取 4 張 Layer 1 的輸出圖片
                for (ch_in_batch = 0; ch_in_batch < `LAYER2_IN_PER_BATCH; ch_in_batch = ch_in_batch + 1) begin
                    global_ch = input_group * `LAYER2_IN_PER_BATCH + ch_in_batch;
                    $sformat(out_path, `layer2_img_in_fmt, global_ch);
                    
                    layer2_img_files[ch_in_batch] = $fopen(out_path, "rb");
                    if (layer2_img_files[ch_in_batch] == 0) begin
                        $display("Error: Cannot open %s", out_path); $finish;
                    end
                    case(ch_in_batch)
                        0: $fread(layer2_img_data_0, layer2_img_files[ch_in_batch]);
                        1: $fread(layer2_img_data_1, layer2_img_files[ch_in_batch]);
                        2: $fread(layer2_img_data_2, layer2_img_files[ch_in_batch]);
                        3: $fread(layer2_img_data_3, layer2_img_files[ch_in_batch]);
                    endcase
                    $fclose(layer2_img_files[ch_in_batch]);
                    
                    // 初始化 padding buffer
                    for(idx=0; idx<`padding_img_size; idx=idx+1) padding_img[ch_in_batch][idx] = 8'd0;
                    
                    // 填入資料 (直接填 8-bit, Top Module L2 模式會處理)
                    for(h=0; h<img_h; h=h+1)
                        for(w=0; w<img_w; w=w+1) begin
                            case(ch_in_batch)
                                0: pixel_val = layer2_img_data_0[(h*img_w+w)*3+offset];
                                1: pixel_val = layer2_img_data_1[(h*img_w+w)*3+offset];
                                2: pixel_val = layer2_img_data_2[(h*img_w+w)*3+offset];
                                3: pixel_val = layer2_img_data_3[(h*img_w+w)*3+offset];
                            endcase
                            padding_img[ch_in_batch][h*`PAD_W+w+(`PAD_W+1)] = pixel_val;
                        end
                end 

                // 讀取權重 (填入 w2_xx 變數)
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_00[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_01[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_02[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_03[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_10[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_11[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_12[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_13[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_20[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_21[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_22[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_23[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_30[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_31[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_32[idx]);
                for(idx=0; idx<9; idx=idx+1) $fscanf(wf_weights,"%h", w2_33[idx]);

                if (input_group == 0) begin
                    $fscanf(wf_bias,"%h", b2_0);
                    $fscanf(wf_bias,"%h", b2_1);
                    $fscanf(wf_bias,"%h", b2_2);
                    $fscanf(wf_bias,"%h", b2_3);
                    
                    // 開啟輸出檔案
                    for(ch_in_batch=0; ch_in_batch<`LAYER2_OUT_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                        global_ch = output_batch * `LAYER2_OUT_PER_BATCH + ch_in_batch;
                        $sformat(out_path, `layer2_img_out_fmt, global_ch);
                        layer2_fout[ch_in_batch] = $fopen(out_path,"wb");
                        for(header=0; header<54; header=header+1)
                            $fwrite(layer2_fout[ch_in_batch], "%c", img_data[header]);
                    end
                end
                
                out_idx = 0;
                
                for(idx=0; idx<`padding_img_size; idx=idx+1) begin
                    pixel_in_0 <= padding_img[0][idx];
                    pixel_in_1 <= padding_img[1][idx];
                    pixel_in_2 <= padding_img[2][idx];
                    pixel_in_3 <= padding_img[3][idx];
                    
                    effective_cnt = idx - latency;
                    if (idx >= latency && psum_read_idx < 50176) begin
                        if(effective_cnt >= 0 && (effective_cnt % 226) < 224) begin
                            tb_psum_in_ch0 <= tb_psum_mem[0][psum_read_idx];
                            tb_psum_in_ch1 <= tb_psum_mem[1][psum_read_idx];
                            tb_psum_in_ch2 <= tb_psum_mem[2][psum_read_idx];
                            tb_psum_in_ch3 <= tb_psum_mem[3][psum_read_idx];
                            psum_read_idx = psum_read_idx + 1;
                        end else begin
                            tb_psum_in_ch0 <= 0; tb_psum_in_ch1 <= 0; tb_psum_in_ch2 <= 0; tb_psum_in_ch3 <= 0;
                        end
                    end else begin
                        tb_psum_in_ch0 <= 0; tb_psum_in_ch1 <= 0; tb_psum_in_ch2 <= 0; tb_psum_in_ch3 <= 0;
                    end
                    
                    @(posedge clk);
                    if (input_group != 15) begin
                        if (layer2_partial_valid) begin
                            if (out_idx < 52000) begin
                                tb_psum_mem[0][out_idx] = tb_psum_out_ch0;
                                tb_psum_mem[1][out_idx] = tb_psum_out_ch1;
                                tb_psum_mem[2][out_idx] = tb_psum_out_ch2;
                                tb_psum_mem[3][out_idx] = tb_psum_out_ch3;
                            end
                            out_idx = out_idx + 1;
                        end
                    end else begin
                        if (layer2_final_pixel_valid) begin
                            for(ch_in_batch=0; ch_in_batch<`LAYER2_OUT_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                            end
                            out_idx = out_idx + 1;
                        end
                    end
                end
                
                // Flush
                while((out_idx < 50176 || psum_read_idx < 50176) && flush_guard < 7000)begin
                    pixel_in_0 <= 8'd0; pixel_in_1 <= 8'd0; pixel_in_2 <= 8'd0; pixel_in_3 <= 8'd0;

                    if (psum_read_idx < 50176) begin
                        tb_psum_in_ch0 <= tb_psum_mem[0][psum_read_idx];
                        tb_psum_in_ch1 <= tb_psum_mem[1][psum_read_idx];
                        tb_psum_in_ch2 <= tb_psum_mem[2][psum_read_idx];
                        tb_psum_in_ch3 <= tb_psum_mem[3][psum_read_idx];
                        psum_read_idx = psum_read_idx + 1;
                    end else begin
                        tb_psum_in_ch0 <= 0; tb_psum_in_ch1 <= 0; tb_psum_in_ch2 <= 0; tb_psum_in_ch3 <= 0;
                    end

                    @(posedge clk);
                    if(input_group == 15) begin
                        if (layer2_final_pixel_valid) begin
                            for(ch_in_batch=0; ch_in_batch<`LAYER2_OUT_PER_BATCH; ch_in_batch=ch_in_batch+1) begin
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                                $fwrite(layer2_fout[ch_in_batch], "%c", out_ch[ch_in_batch]);
                            end
                            out_idx = out_idx + 1;
                        end
                    end else begin
                        if (layer2_partial_valid) begin
                            if (out_idx < 52000) begin
                                tb_psum_mem[0][out_idx] = tb_psum_out_ch0;
                                tb_psum_mem[1][out_idx] = tb_psum_out_ch1;
                                tb_psum_mem[2][out_idx] = tb_psum_out_ch2;
                                tb_psum_mem[3][out_idx] = tb_psum_out_ch3;
                            end
                            out_idx = out_idx + 1;
                        end
                    end
                    flush_guard = flush_guard + 1;
                end
            end
            for(ch_in_batch=0; ch_in_batch<`LAYER2_OUT_PER_BATCH; ch_in_batch=ch_in_batch+1) $fclose(layer2_fout[ch_in_batch]);
        end
        $fclose(wf_weights);
        $fclose(wf_bias);
        $display("=== Layer 2 Completed ===");
        $finish;
    end     
endmodule