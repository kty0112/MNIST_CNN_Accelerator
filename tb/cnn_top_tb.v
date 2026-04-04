//------------------------------------------------------------------------
// CNN Top Testbench (Verilog)
// Converted from VHDL: cnn_top_tb.vhd
//
// [기능]
//   28x28 테스트 이미지(숫자 "1" 패턴)를 CNN에 입력하고
//   Prediction/Probability 출력을 확인하는 기능 검증 테스트벤치
//
// [테스트 방법]
//   1. 448x448 크기의 프레임 2장 전송
//   2. 각 픽셀은 28x28 "1" 패턴을 16배 확대한 것
//   3. CNN이 숫자 "1"을 인식하는지 확인
//
// [사용법]
//   iverilog -o sim cnn_top_tb.v ../src/*.v
//   vvp sim
//   또는 Vivado Simulator에서 실행
//------------------------------------------------------------------------
`timescale 1ns / 1ps

module cnn_top_tb;

    // DUT signals
    reg  [7:0]  i_r, i_g, i_b;
    reg  [9:0]  i_column;
    reg  [8:0]  i_row;
    reg         i_new_pixel;
    wire [3:0]  prediction;
    wire [9:0]  probability;

    // Testbench control
    reg clk = 0;
    localparam CLK_PERIOD = 40;  // 25 MHz pixel clock

    localparam IMG_W = 448;
    localparam IMG_H = 448;

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    assign i_new_pixel_wire = clk;

    // DUT
    cnn_top #(
        .INPUT_COLUMNS (IMG_W),
        .INPUT_ROWS    (IMG_H),
        .COLUMN_OFFSET (80),
        .CNN_COLUMNS   (28),
        .CNN_ROWS      (28)
    ) u_dut (
        .i_r         (i_r),
        .i_g         (i_g),
        .i_b         (i_b),
        .i_column    (i_column),
        .i_row       (i_row),
        .i_new_pixel (clk),
        .prediction  (prediction),
        .probability (probability)
    );

    //------------------------------------------------------------------
    // 테스트 패턴: 숫자 "1"
    //------------------------------------------------------------------
    // 28x28 좌표에서의 밝기를 반환
    // 세로 막대(col 13~15, row 4~23) + 위 세리프 + 아래 밑줄
    function [7:0] digit_one_pixel;
        input [4:0] row;
        input [4:0] col;
        begin
            if (row >= 4 && row <= 6 && col >= 10 && col <= 15)
                digit_one_pixel = 8'd220;   // top serif
            else if (row >= 4 && row <= 23 && col >= 13 && col <= 15)
                digit_one_pixel = 8'd240;   // vertical stroke
            else if (row >= 22 && row <= 24 && col >= 10 && col <= 18)
                digit_one_pixel = 8'd220;   // bottom base
            else
                digit_one_pixel = 8'd10;    // background
        end
    endfunction

    //------------------------------------------------------------------
    // Stimulus: 448x448 프레임 2장 전송
    //------------------------------------------------------------------
    integer frame, r, c;
    reg [4:0] cnn_row_idx, cnn_col_idx;
    reg [7:0] gray;

    initial begin
        i_r = 0; i_g = 0; i_b = 0;
        i_column = 0; i_row = 0;
        #(CLK_PERIOD * 5);

        for (frame = 0; frame < 2; frame = frame + 1) begin
            $display("=== Frame %0d start ===", frame);

            for (r = 0; r < IMG_H; r = r + 1) begin
                for (c = 0; c < IMG_W; c = c + 1) begin
                    // 448→28 매핑 (16:1)
                    cnn_row_idx = r / 16;
                    cnn_col_idx = c / 16;

                    if (cnn_row_idx < 28 && cnn_col_idx < 28)
                        gray = digit_one_pixel(cnn_row_idx, cnn_col_idx);
                    else
                        gray = 0;

                    // Grayscale → R=G=B
                    i_r = gray;
                    i_g = gray;
                    i_b = gray;

                    // 좌표 (Column_Offset=80 적용)
                    i_column = (c + 80) % 646;
                    i_row    = r % 483;

                    @(posedge clk);
                end
            end

            $display("=== Frame %0d end === Prediction=%0d Probability=%0d",
                     frame, prediction, probability);
        end

        // 파이프라인 플러시
        repeat (10000) begin
            i_r = 0; i_g = 0; i_b = 0;
            i_column = 0; i_row = 0;
            @(posedge clk);
        end

        $display("=== FINAL === Prediction=%0d Probability=%0d",
                 prediction, probability);
        $finish;
    end

    //------------------------------------------------------------------
    // Monitor: Prediction 변화 감지
    //------------------------------------------------------------------
    reg [3:0] prev_pred = 4'hF;

    always @(posedge clk) begin
        if (prediction != prev_pred && probability > 0) begin
            $display(">> Prediction changed: %0d (prob=%0d)",
                     prediction, probability);
            prev_pred <= prediction;
        end
    end

endmodule
