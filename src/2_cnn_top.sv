//------------------------------------------------------------------------
// CNN Top Level - MNIST Digit Recognition (Verilog)
// Converted from VHDL: cnn_top.vhd
//
// [기능]
//   448x448 RGB 스트림을 입력받아 MNIST 숫자(0~9)를 실시간 인식
//
// [파이프라인 구조]
//   1. RGB → Grayscale (BT.601: 0.299R + 0.587G + 0.114B)
//   2. 영역 크롭 (448x448에서 중앙 영역 추출)
//   3. Max Pooling 전처리 (448x448 → 28x28, 16:1 다운스케일)
//   4. RGB to CNN 스트림 변환
//   5. Conv1 (28x28x1 → 28x28x4, 3x3 필터, ReLU)
//   6. Pool1 (28x28x4 → 14x14x4, 2x2 Max Pool)
//   7. Conv2 (14x14x4 → 14x14x6, 3x3 필터, ReLU)
//   8. Pool2 (14x14x6 → 7x7x6, 2x2 Max Pool)
//   9. Conv3 (7x7x6 → 7x7x8, 3x3 필터, ReLU)
//  10. Pool3 (7x7x8 → 3x3x8, 2x2 Max Pool)
//  11. Flatten (3x3x8 = 72 요소)
//  12. FC Layer (72 → 10, ReLU)
//  13. Argmax → Prediction(0~9) + Probability(0~1023)
//
// [아키텍처 - LeNet 스타일]
//   Input(28x28x1) → [Conv→Pool]x3 → FC → Argmax
//   총 가중치: 1,438개 (8-bit 고정소수점)
//   FPGA 리소스: LUT 3.44%, BRAM 2.14%, DSP 1.82%
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// CNN Top Level - MNIST Digit Recognition (SystemVerilog)
//------------------------------------------------------------------------
`include "../include/image_data_pkg.vh"
`include "../include/cnn_config_pkg.vh"
`include "../include/cnn_data_pkg.vh"

module cnn_top #(
    parameter INPUT_COLUMNS = 448,
    parameter INPUT_ROWS    = 448,
    //parameter COLUMN_OFFSET = 80,   // 크롭 오프셋
    parameter COLUMN_OFFSET = 416,   // 정중앙 가로 시작점 (1280-448)/2
    parameter ROW_OFFSET    = 136,   // 정중앙 세로 시작점 (720-448)/2
    parameter CNN_COLUMNS   = 28,   // CNN 입력 크기
    parameter CNN_ROWS      = 28
)(
    // rgb_stream input
    input  logic [7:0]  i_r,
    input  logic [7:0]  i_g,
    input  logic [7:0]  i_b,
    // [중요] 비트 폭 수정: 1280과 720을 수용할 수 있어야 함
    //input  logic [9:0]  i_column,
    input  logic [10:0] i_column, // 10비트 -> 11비트
    //input  logic [8:0]  i_row,
    input  logic [9:0]  i_row,    // 9비트 -> 10비트
    input  logic        i_new_pixel,

    // CNN outputs
    output logic [3:0]  prediction,    // 인식된 숫자 0~9
    output logic [9:0]  probability    // 신뢰도 0~1023
);

    //==================================================================
    // Stage 1: RGB → Grayscale (BT.601)
    //==================================================================
    logic [7:0] gray_val;
    
    always_ff @(posedge i_new_pixel) begin
        gray_val <= (77 * i_r + 150 * i_g + 29 * i_b) >> 8;
    end

    //==================================================================
    // Stage 2: 영역 크롭 + 전달
    //==================================================================
    logic [7:0]  pool_r;
    logic [9:0]  pool_column;
    logic [8:0]  pool_row;

    /*always_ff @(posedge i_new_pixel) begin
       pool_row <= (i_row < INPUT_ROWS) ? i_row : INPUT_ROWS - 1;

        if (i_row < INPUT_ROWS &&
            i_column >= COLUMN_OFFSET &&
            i_column < INPUT_COLUMNS + COLUMN_OFFSET)
            pool_column <= i_column - COLUMN_OFFSET;
        else
            pool_column <= INPUT_COLUMNS - 1;

        pool_r <= gray_val; // Grayscale 값 사용
    end*/
    always_ff @(posedge i_new_pixel) begin
        // 1. 중앙 영역(448x448) 안에 들어왔는지 확인
        if (i_row >= ROW_OFFSET && i_row < (INPUT_ROWS + ROW_OFFSET) &&
            i_column >= COLUMN_OFFSET && i_column < (INPUT_COLUMNS + COLUMN_OFFSET)) begin
            
            // 영역 안이면: 0~447 사이의 상대 좌표로 변환 
            pool_column <= i_column - COLUMN_OFFSET;
            pool_row    <= i_row - ROW_OFFSET;
            pool_r      <= gray_val; // 실제 영상 데이터 전달 
            
        end else begin
            // 영역 밖이면: 좌표를 끝점에 고정하고 데이터는 0(검은색) 처리 [cite: 127]
            pool_column <= INPUT_COLUMNS - 1;
            pool_row    <= INPUT_ROWS - 1;
            pool_r      <= 8'd0; 
        end
    end



    //==================================================================
    // Stage 3: Max Pooling 전처리 (448x448 → 28x28)
    //==================================================================
    logic [7:0]  pool_out_r;
    logic [9:0]  pool_out_column;
    logic [8:0]  pool_out_row;

    max_pooling_pre #(
        .INPUT_COLUMNS  (INPUT_COLUMNS),
        .INPUT_ROWS     (INPUT_ROWS),
        .INPUT_VALUES   (1),
        .FILTER_COLUMNS (INPUT_COLUMNS / CNN_COLUMNS),  // 16
        .FILTER_ROWS    (INPUT_ROWS / CNN_ROWS)          // 16
    ) u_max_pooling (
        .i_r         (pool_r),
        .i_g         (8'd0),
        .i_b         (8'd0),
        .i_column    (pool_column),
        .i_row       (pool_row),
        .i_new_pixel (i_new_pixel),
        .o_r         (pool_out_r),
        .o_g         (),
        .o_b         (),
        .o_column    (pool_out_column),
        .o_row       (pool_out_row),
        .o_new_pixel ()
    );

    //==================================================================
    // Stage 4: RGB to CNN Stream 변환
    //==================================================================
    logic        cnn_data_clk;
    logic [9:0]  cnn_column;
    logic [8:0]  cnn_row;
    logic        cnn_data_valid;
    logic [9:0]  cnn_data;

    rgb_to_cnn #(
        .INPUT_VALUES (1)
    ) u_rgb_to_cnn (
        .i_r         (pool_out_r),
        .i_g         (8'd0),
        .i_b         (8'd0),
        .i_column    (pool_out_column),
        .i_row       (pool_out_row),
        .i_new_pixel (i_new_pixel),
        .o_data_clk  (cnn_data_clk),
        .o_column    (cnn_column),
        .o_row       (cnn_row),
        .o_filter    (),
        .o_data_valid(cnn_data_valid),
        .o_data_0    (cnn_data),
        .o_data_1    (),
        .o_data_2    ()
    );

    //==================================================================
    // Stage 5~10: CNN Layers (Conv → Pool × 3)
    //==================================================================
    
    logic        conv1_data_clk;
    logic [9:0]  conv1_column;
    logic [8:0]  conv1_row;
    logic [3:0]  conv1_filter;
    logic        conv1_data_valid;
    logic [9:0]  conv1_data;

    cnn_convolution #(
        .INPUT_COLUMNS  (L1_COLUMNS),    // 28
        .INPUT_ROWS     (L1_ROWS),       // 28
        .INPUT_VALUES   (L1_VALUES),     // 1
        .FILTER_COLUMNS (L1_FILTER_X),   // 3
        .FILTER_ROWS    (L1_FILTER_Y),   // 3
        .FILTERS        (L1_FILTERS),    // 4
        .STRIDES        (L1_STRIDES),    // 1
        .ACTIVATION     (ACT_RELU),
        .PADDING        (PAD_SAME),
        .CALC_CYCLES    (4),
        .FILTER_CYCLES  (4),
        .EXPAND_CYCLES  (240),
        .OFFSET_IN      (0),
        .OFFSET_OUT     (L1_OUT_OFFSET - 3),
        .OFFSET         (L1_OFFSET)
    ) u_conv1 (
        .i_data_clk  (cnn_data_clk),
        .i_column    (cnn_column),
        .i_row       (cnn_row),
        .i_filter    (4'd0),
        .i_data_valid(cnn_data_valid),
        .i_data      (cnn_data),
        .o_data_clk  (conv1_data_clk),
        .o_column    (conv1_column),
        .o_row       (conv1_row),
        .o_filter    (conv1_filter),
        .o_data_valid(conv1_data_valid),
        .o_data      (conv1_data)
    );

    // ... Pool1, Conv2, Pool2, Conv3, Pool3 인스턴스들
    // (VHDL 원본과 동일한 generic/parameter 매핑)

    //==================================================================
    // Stage 11: Flatten (3x3x8 → 72)
    // Stage 12: FC Layer (72 → 10)
    // Stage 13: Argmax
    //==================================================================
    logic [9:0]  max_val;
    logic [3:0]  max_idx;

    // 간략화된 Argmax (FC 출력 연결 시 활성화)
    always_comb begin
        prediction  = max_idx;
        probability = max_val;
    end

endmodule