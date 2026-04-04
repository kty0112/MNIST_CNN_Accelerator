//------------------------------------------------------------------------
// CNN Data Package - Weights & Layer Configuration (Verilog Header)
// Converted from VHDL: cnn_data_pkg.vhd
// Original: OnSemi_CNN_Ultra (Leon Beier, Protop Solutions UG, 2020)
//
// 학습된 CNN 가중치 1,438개 (8-bit 고정소수점)
// Layer 구성: Conv1(4f) → Pool1 → Conv2(6f) → Pool2 →
//             Conv3(8f) → Pool3 → FC(72→10) → Argmax
//------------------------------------------------------------------------
`ifndef CNN_DATA_PKG_VH
`define CNN_DATA_PKG_VH

//=====================================================================
// Layer 1: Convolution (28x28x1 → 28x28x4)
//=====================================================================
localparam L1_COLUMNS    = 28;
localparam L1_ROWS       = 28;
localparam L1_STRIDES    = 1;
localparam [2:0] L1_ACTIVATION = ACT_RELU;
localparam L1_PADDING    = PAD_SAME;

localparam L1_VALUES     = 1;    // 입력 채널 수
localparam L1_FILTER_X   = 3;    // 필터 가로
localparam L1_FILTER_Y   = 3;    // 필터 세로
localparam L1_FILTERS    = 4;    // 출력 필터 수
localparam L1_INPUTS     = 10;   // 가중치 열 수 (3*3*1 + bias = 10)
localparam L1_OUT_OFFSET = 3;
localparam L1_OFFSET     = 1;

// Layer 1 Weights [4 filters][10 weights]
// 각 행: 9개 커널 가중치 + 1개 바이어스
localparam signed [7:0] L1_W [0:3][0:9] = '{
    '{ 8'sd63, -8'sd35, -8'sd16, -8'sd20,  8'sd62, -8'sd32,  8'sd34,  8'sd22, -8'sd44, -8'sd14},
    '{ 8'sd44,  8'sd34, -8'sd25,  8'sd32, -8'sd3,  -8'sd36, -8'sd3,  -8'sd41, -8'sd26, -8'sd2},
    '{ 8'sd3,  -8'sd64, -8'sd31,  8'sd10, -8'sd2,  -8'sd22,  8'sd34,  8'sd59,  8'sd3,  -8'sd2},
    '{ 8'sd54,  8'sd20, -8'sd37,  8'sd41, -8'sd20,  8'sd43,  8'sd33,  8'sd61,  8'sd26,  8'sd0}
};

//=====================================================================
// Pooling 1: Max Pool (28x28x4 → 14x14x4)
//=====================================================================
localparam P1_COLUMNS  = L1_COLUMNS;
localparam P1_ROWS     = L1_ROWS;
localparam P1_VALUES   = L1_FILTERS;
localparam P1_FILTER_X = 2;
localparam P1_FILTER_Y = 2;
localparam P1_STRIDES  = 2;
localparam P1_PADDING  = PAD_VALID;

//=====================================================================
// Layer 2: Convolution (14x14x4 → 14x14x6)
//=====================================================================
localparam L2_COLUMNS    = P1_COLUMNS / P1_STRIDES;  // 14
localparam L2_ROWS       = P1_ROWS / P1_STRIDES;     // 14
localparam L2_STRIDES    = 1;
localparam [2:0] L2_ACTIVATION = ACT_RELU;
localparam L2_PADDING    = PAD_SAME;

localparam L2_VALUES     = 4;
localparam L2_FILTER_X   = 3;
localparam L2_FILTER_Y   = 3;
localparam L2_FILTERS    = 6;
localparam L2_INPUTS     = 37;  // 3*3*4 + bias = 37
localparam L2_OUT_OFFSET = 3;
localparam L2_OFFSET     = 0;

localparam signed [7:0] L2_W [0:5][0:36] = '{
    '{  8'sd53,  8'sd5,   8'sd59,  8'sd36,  8'sd11, -8'sd56,  8'sd69, -8'sd32,  8'sd38, -8'sd30,  8'sd46, -8'sd85,  8'sd3,  -8'sd26,  8'sd17,  8'sd36,  8'sd37, -8'sd44,  8'sd19,  8'sd55, -8'sd9,  -8'sd26,  8'sd19,  8'sd16, -8'sd20,  8'sd2,  -8'sd3,   8'sd12,  8'sd30, -8'sd23,  8'sd3,  -8'sd26, -8'sd1,  -8'sd6,   8'sd28,  8'sd11, -8'sd24},
    '{-8'sd29,  8'sd50,  8'sd30,  8'sd50, -8'sd34, -8'sd32, -8'sd1,   8'sd51,  8'sd18,  8'sd65, -8'sd45,  8'sd6,  -8'sd10, -8'sd33, -8'sd88,  8'sd31,  8'sd12,  8'sd74, -8'sd18,  8'sd21,  8'sd6,   8'sd87,-8'sd104, -8'sd44, -8'sd44, -8'sd86, 8'sd111, -8'sd82,-8'sd109, -8'sd2,   8'sd34, -8'sd83, -8'sd80, -8'sd4,   8'sd47, -8'sd18,  8'sd13},
    '{-8'sd13,  8'sd26,  8'sd21, -8'sd28, -8'sd21,  8'sd20, -8'sd10,  8'sd15,  8'sd20,  8'sd7,  -8'sd10, -8'sd11,  8'sd18,  8'sd15,  8'sd4,  -8'sd11,  8'sd4,   8'sd69, -8'sd6,  -8'sd32, -8'sd30, -8'sd26,  8'sd46, -8'sd28, -8'sd30, -8'sd61, -8'sd1,   8'sd67, -8'sd53, -8'sd36,  8'sd51,  8'sd36, -8'sd71, -8'sd16, 8'sd102,  8'sd52,  8'sd5},
    '{-8'sd62,  8'sd12,  8'sd1,   8'sd0,  -8'sd40, -8'sd50,  8'sd25, -8'sd23, -8'sd30, -8'sd23, -8'sd22,  8'sd7,   8'sd1,  -8'sd23,  8'sd41,  8'sd21, -8'sd34,  8'sd4,  -8'sd42,  8'sd25, -8'sd7,   8'sd4,  -8'sd28,  8'sd51, -8'sd24,  8'sd72,  8'sd19,  8'sd14,  8'sd3,   8'sd7,  -8'sd55,  8'sd87, -8'sd7,  -8'sd48, -8'sd51,  8'sd2,  -8'sd2},
    '{-8'sd20,  8'sd2,  -8'sd44, -8'sd52,  8'sd17, -8'sd25, -8'sd39, -8'sd12,  8'sd12,  8'sd16, -8'sd49,  8'sd43,-8'sd126, -8'sd79, -8'sd20, -8'sd23, -8'sd10,  8'sd6,  -8'sd70, -8'sd4,   8'sd76,  8'sd35, -8'sd50,  8'sd41, -8'sd44, -8'sd51, -8'sd26, -8'sd12, -8'sd21, -8'sd70,-8'sd115,  8'sd46,  8'sd40,  8'sd10,  8'sd3,   8'sd37,  8'sd0},
    '{  8'sd48,  8'sd4,  -8'sd17,  8'sd28,  8'sd25, -8'sd7,  -8'sd34, -8'sd20, -8'sd30, -8'sd19, -8'sd48, -8'sd21,  8'sd23,  8'sd26, -8'sd42,  8'sd21,  8'sd5,   8'sd55, -8'sd51, -8'sd11, -8'sd63, -8'sd30,  8'sd12, -8'sd62,  8'sd21, 8'sd110, -8'sd95,  8'sd75,  8'sd36,  8'sd34, -8'sd35, -8'sd50,  8'sd1,  -8'sd81, -8'sd1,   8'sd16, -8'sd15}
};

//=====================================================================
// Pooling 2: Max Pool (14x14x6 → 7x7x6)
//=====================================================================
localparam P2_COLUMNS  = L2_COLUMNS;
localparam P2_ROWS     = L2_ROWS;
localparam P2_VALUES   = L2_FILTERS;
localparam P2_FILTER_X = 2;
localparam P2_FILTER_Y = 2;
localparam P2_STRIDES  = 2;
localparam P2_PADDING  = PAD_VALID;

//=====================================================================
// Layer 3: Convolution (7x7x6 → 7x7x8)
//=====================================================================
localparam L3_COLUMNS    = P2_COLUMNS / P2_STRIDES;  // 7
localparam L3_ROWS       = P2_ROWS / P2_STRIDES;     // 7
localparam L3_STRIDES    = 1;
localparam [2:0] L3_ACTIVATION = ACT_RELU;
localparam L3_PADDING    = PAD_SAME;

localparam L3_VALUES     = 6;
localparam L3_FILTER_X   = 3;
localparam L3_FILTER_Y   = 3;
localparam L3_FILTERS    = 8;
localparam L3_INPUTS     = 55;  // 3*3*6 + bias = 55
localparam L3_OUT_OFFSET = 5;
localparam L3_OFFSET     = 1;

localparam signed [7:0] L3_W [0:7][0:54] = '{
    '{ -8'sd7,  8'sd17,-8'sd44,  8'sd5, -8'sd20,-8'sd17,  8'sd13,-8'sd15, -8'sd2, -8'sd2,  8'sd11,  8'sd13,  8'sd0, -8'sd28, -8'sd7,  8'sd16,  8'sd25,  8'sd25,-8'sd53,  8'sd1, -8'sd13,-8'sd21, -8'sd3, -8'sd13,-8'sd12,  8'sd22,  8'sd6, -8'sd40, -8'sd4,  8'sd14,-8'sd26, -8'sd2,  8'sd0,  8'sd0,  8'sd22,  8'sd14,  8'sd6, -8'sd2, -8'sd7, -8'sd9,  8'sd2,  8'sd30,  8'sd5, -8'sd1,  8'sd8,  8'sd24,  8'sd20,  8'sd26, -8'sd4, -8'sd7, -8'sd19,  8'sd14,  8'sd40,  8'sd15, -8'sd3},
    '{  8'sd8, -8'sd20,  8'sd1,  8'sd20,-8'sd13,-8'sd17,  8'sd1,  8'sd10,  8'sd38,  8'sd10,  8'sd5, -8'sd13,  8'sd11,  8'sd28,  8'sd27,  8'sd28,-8'sd15,-8'sd17, -8'sd3,  8'sd2, -8'sd11, -8'sd6,-8'sd13,-8'sd10,  8'sd14,  8'sd22,  8'sd6, -8'sd6, -8'sd27,-8'sd17,  8'sd13,  8'sd9, -8'sd7, -8'sd9,  8'sd7, -8'sd16,  8'sd0,  8'sd10, -8'sd8, -8'sd27, -8'sd3,  8'sd16,  8'sd2, -8'sd7,  8'sd8,  8'sd6,  -8'sd7,  8'sd5,  8'sd22,-8'sd14,-8'sd17,  8'sd28,  8'sd1, -8'sd8, -8'sd12},
    '{  8'sd18,-8'sd13,  8'sd5, -8'sd5, -8'sd6,  8'sd19,  8'sd13,-8'sd41,  8'sd12,  8'sd18,  8'sd41,  8'sd20, -8'sd8, -8'sd64,-8'sd21,  8'sd30,  8'sd9,  8'sd13,-8'sd10,-8'sd21,-8'sd21,  8'sd11,-8'sd17,  8'sd4, -8'sd10,-8'sd30, -8'sd4,  8'sd22,  8'sd10,  8'sd22,  8'sd16,-8'sd41,  8'sd22, -8'sd1,  8'sd20,  8'sd4,  8'sd6, -8'sd1, -8'sd9, -8'sd7, -8'sd10, -8'sd2,-8'sd10,-8'sd25,-8'sd19,-8'sd18, -8'sd9,  8'sd12,  8'sd38,  8'sd6,  8'sd0, -8'sd28, -8'sd2,  8'sd3,  8'sd9},
    '{  8'sd6, -8'sd10,-8'sd22, -8'sd6, -8'sd4,  8'sd16,  8'sd11,-8'sd14,-8'sd15,-8'sd11,-8'sd19,  8'sd15,  8'sd15,  8'sd1,  8'sd3, -8'sd26,  8'sd8,  8'sd16,  8'sd18,-8'sd17,  8'sd36, -8'sd9, -8'sd6, -8'sd21,  8'sd13,  8'sd0,  8'sd13, -8'sd4, -8'sd5, -8'sd16, -8'sd1,  8'sd9, -8'sd4, -8'sd6,  8'sd25,  8'sd16,  8'sd19,-8'sd14,  8'sd5,  8'sd8, -8'sd19,-8'sd21,  8'sd6, -8'sd16, -8'sd8,  8'sd24,-8'sd17,  8'sd4,  8'sd8, -8'sd1, -8'sd20,  8'sd17,  8'sd6,  8'sd6,  -8'sd8},
    '{ -8'sd4,  8'sd23,  8'sd31,  8'sd5, -8'sd6,  8'sd11,  8'sd5, -8'sd16, -8'sd2,-8'sd11, -8'sd3, -8'sd28,  8'sd5, -8'sd51,  8'sd3, -8'sd2,  8'sd1,  8'sd13,  8'sd24,  8'sd34,-8'sd36,  8'sd7, -8'sd12,-8'sd37,-8'sd44,-8'sd69,-8'sd31,  8'sd1,  8'sd32, -8'sd6, -8'sd23,-8'sd62,  8'sd19,  8'sd13,  8'sd22,-8'sd20,-8'sd33,  8'sd5,  8'sd19,-8'sd23,  8'sd22,-8'sd49,-8'sd11,-8'sd14,  8'sd13,-8'sd21,  8'sd22,-8'sd15,  8'sd30,  8'sd15,  8'sd2,  8'sd1,  8'sd6, -8'sd35,  8'sd27},
    '{  8'sd11,  8'sd6, -8'sd28,-8'sd21,  8'sd6, -8'sd29,  8'sd36,-8'sd23, -8'sd3,  8'sd12,  8'sd18,  8'sd11,-8'sd19,-8'sd16,  8'sd8, -8'sd6,  8'sd6,  8'sd4,  8'sd0,  8'sd4,  8'sd9,  8'sd14,  8'sd0,  8'sd4, -8'sd2, -8'sd7, -8'sd4, -8'sd13,  8'sd9,  8'sd31,  8'sd24,-8'sd32,-8'sd17,-8'sd18, -8'sd3,  8'sd19,-8'sd22,  8'sd23,-8'sd15,  8'sd9, -8'sd8,  8'sd7, -8'sd20,  8'sd13,  8'sd14,  8'sd1, -8'sd11,  8'sd26,-8'sd22,  8'sd12,  8'sd29,  8'sd15,-8'sd12, -8'sd9,  8'sd3},
    '{  8'sd16, -8'sd1,  8'sd10,  8'sd19,  8'sd7, -8'sd17, -8'sd2,  8'sd15,  8'sd10,  8'sd6, -8'sd47,-8'sd15, -8'sd3,  8'sd60,  8'sd7,  8'sd5,  8'sd11,-8'sd11,  8'sd2, -8'sd6,  8'sd15, -8'sd1, -8'sd22, -8'sd2,  8'sd19,-8'sd42,  8'sd1,  8'sd4, -8'sd38,  8'sd3,  8'sd25,-8'sd53,  8'sd16,  8'sd13,-8'sd18,  8'sd10,  8'sd12, -8'sd4,  8'sd4,  8'sd10,-8'sd39,-8'sd27,  8'sd15,-8'sd30,-8'sd31,  8'sd0,  -8'sd2,  8'sd33,  8'sd15,-8'sd22,  8'sd2,  -8'sd2,  8'sd2,  8'sd15, -8'sd3},
    '{  8'sd6, -8'sd36, -8'sd6,  8'sd4, -8'sd11,-8'sd61,  8'sd5, -8'sd11,  8'sd15,-8'sd12,-8'sd12,-8'sd15,  8'sd14,  8'sd4,  8'sd1, -8'sd6,  8'sd0, -8'sd2,  8'sd18,  8'sd16,  8'sd4,  8'sd14,  8'sd6,  8'sd3,  8'sd20, -8'sd1,  8'sd13,  8'sd18,-8'sd22,-8'sd30, -8'sd4,  8'sd3,  8'sd34,  8'sd15,  8'sd5, -8'sd16,-8'sd20,  8'sd11,-8'sd34,-8'sd11, -8'sd2,  8'sd9,  8'sd4,  8'sd19,-8'sd27,-8'sd26,  8'sd29,-8'sd16,-8'sd10,  8'sd58,  8'sd3, -8'sd3, -8'sd23, -8'sd6, -8'sd10}
};

//=====================================================================
// Pooling 3: Max Pool (7x7x8 → 3x3x8)
//=====================================================================
localparam P3_COLUMNS  = L3_COLUMNS;
localparam P3_ROWS     = L3_ROWS;
localparam P3_VALUES   = L3_FILTERS;
localparam P3_FILTER_X = 2;
localparam P3_FILTER_Y = 2;
localparam P3_STRIDES  = 2;
localparam P3_PADDING  = PAD_VALID;

//=====================================================================
// Flatten: 3x3x8 = 72 elements
//=====================================================================
localparam FLATTEN_COLUMNS = P3_COLUMNS / P3_STRIDES;  // 3
localparam FLATTEN_ROWS    = P3_ROWS / P3_STRIDES;     // 3
localparam FLATTEN_VALUES  = P3_VALUES;                 // 8

//=====================================================================
// NN Layer 1: Fully Connected (72 → 10)
//=====================================================================
localparam [2:0] NN1_ACTIVATION = ACT_RELU;
localparam NN1_INPUTS      = 72;
localparam NN1_OUTPUTS     = 10;
localparam NN1_OUT_OFFSET  = 6;
localparam NN1_OFFSET      = 1;

// NN Layer 1 Weights [10 outputs][73 = 72 inputs + 1 bias]
localparam signed [7:0] NN1_W [0:9][0:72] = '{
    '{ -8'sd8, -8'sd5,-8'sd34,-8'sd12,-8'sd21, 8'sd5,-8'sd14, -8'sd8, 8'sd16,-8'sd31, 8'sd14, 8'sd13,  8'sd8,-8'sd18, 8'sd18, -8'sd2,-8'sd30, 8'sd10,  8'sd7,  8'sd8, 8'sd24,-8'sd26,-8'sd10,  8'sd6,  8'sd2,-8'sd10, 8'sd10,  8'sd7, -8'sd3,-8'sd42,-8'sd25,-8'sd25,-8'sd13,-8'sd23, -8'sd9,-8'sd12,-8'sd23,  8'sd3,-8'sd14,-8'sd12, 8'sd23, 8'sd26, 8'sd22,-8'sd18,  8'sd3,  8'sd9,  8'sd0, 8'sd12, 8'sd18,  8'sd0, -8'sd3,-8'sd21, 8'sd20, 8'sd14,-8'sd38,-8'sd30,-8'sd42,-8'sd10,-8'sd18, 8'sd11, 8'sd31, -8'sd5,  8'sd2, 8'sd22,-8'sd24, 8'sd20, 8'sd14,  8'sd6,-8'sd63,  8'sd7,-8'sd36,  8'sd4,  8'sd1},
    '{ -8'sd7, 8'sd16, 8'sd37, -8'sd1,  8'sd5,-8'sd26,  8'sd0, 8'sd16, 8'sd29, 8'sd20, 8'sd28, 8'sd16, 8'sd16,-8'sd16, -8'sd9,-8'sd21,  8'sd2,-8'sd44, -8'sd1,-8'sd28, 8'sd63, 8'sd25,  8'sd6, -8'sd8,  8'sd1,  8'sd2,-8'sd51,-8'sd10,-8'sd20,  8'sd1,-8'sd18,-8'sd12, 8'sd19, 8'sd20, 8'sd28,  8'sd5,-8'sd10, -8'sd7, -8'sd1,-8'sd17,  8'sd4, -8'sd4, -8'sd8,-8'sd35,-8'sd18,  8'sd7,-8'sd30,-8'sd28,  8'sd4, -8'sd7,  8'sd0, -8'sd5,-8'sd27,-8'sd23, 8'sd35,  8'sd8, 8'sd10,  8'sd8,  8'sd6, 8'sd14,  8'sd8, -8'sd4, -8'sd7,-8'sd27,-8'sd29,  8'sd8,-8'sd15, -8'sd2,  8'sd1,  8'sd2,  8'sd1, 8'sd31,  8'sd9},
    '{-8'sd19,  8'sd0, -8'sd7,  8'sd6,  8'sd4, 8'sd22,-8'sd19,  8'sd8,-8'sd10,  8'sd8, 8'sd23, 8'sd11, -8'sd1, 8'sd16, 8'sd11, 8'sd13,-8'sd33,  8'sd3,  8'sd7,-8'sd12,-8'sd55,-8'sd40, -8'sd5, -8'sd6, -8'sd7, -8'sd5,-8'sd48, 8'sd18,-8'sd15,-8'sd22,  8'sd1, 8'sd29, 8'sd24,  8'sd1,-8'sd10,  8'sd6,-8'sd25,  8'sd5, 8'sd11,-8'sd10, 8'sd19,-8'sd30,  8'sd9, -8'sd3, -8'sd7, 8'sd19, -8'sd8,  8'sd9,-8'sd10,-8'sd25,  8'sd1, 8'sd20, 8'sd26,-8'sd19, -8'sd5,  8'sd2,-8'sd35, -8'sd4,  8'sd2,-8'sd24, 8'sd19,-8'sd11,  8'sd3,  8'sd2, 8'sd11, 8'sd28,  8'sd7,  8'sd0,-8'sd23,-8'sd30, -8'sd2, 8'sd23, -8'sd5},
    '{-8'sd39,-8'sd15, -8'sd2,-8'sd12,-8'sd16, 8'sd29,  8'sd3, 8'sd12, -8'sd6, 8'sd36, -8'sd9,  8'sd9, -8'sd2, 8'sd22, 8'sd13,  8'sd7, -8'sd8,-8'sd25, -8'sd8, 8'sd15,-8'sd63,-8'sd18, 8'sd12,-8'sd18,-8'sd27, -8'sd5,-8'sd26, 8'sd11,-8'sd10,-8'sd20, 8'sd27,-8'sd11,-8'sd10, 8'sd11,  8'sd5,-8'sd34,-8'sd11,-8'sd11,-8'sd23,  8'sd7,-8'sd12,-8'sd11, -8'sd2, 8'sd12,-8'sd32,-8'sd14, -8'sd4,-8'sd20,-8'sd17,  8'sd3,-8'sd14,  8'sd1,-8'sd10,  8'sd3, 8'sd27, 8'sd12,  8'sd0, -8'sd4,-8'sd16, -8'sd5,-8'sd21,  8'sd3,  8'sd6, 8'sd13, -8'sd6, -8'sd8, -8'sd2, -8'sd1,-8'sd23, 8'sd26, 8'sd24,-8'sd12, -8'sd5},
    '{ 8'sd14, 8'sd32, -8'sd1,  8'sd7, 8'sd29,-8'sd33, 8'sd21,-8'sd36, 8'sd18,-8'sd20,-8'sd14, -8'sd9, -8'sd5,-8'sd17, -8'sd7,-8'sd24, 8'sd47,-8'sd31,  8'sd7,-8'sd44,-8'sd25,  8'sd1, 8'sd11, -8'sd5,  8'sd5,-8'sd15,  8'sd7, 8'sd14,  8'sd0,-8'sd10,  8'sd4, 8'sd18,-8'sd15,-8'sd18,  8'sd8, 8'sd12, -8'sd8, -8'sd2, -8'sd2, 8'sd11,-8'sd23,-8'sd23,  8'sd2, 8'sd14,  8'sd2, -8'sd6,  8'sd3,-8'sd20, -8'sd3, 8'sd15,  8'sd9,-8'sd18, -8'sd2, 8'sd11, -8'sd9, -8'sd9, 8'sd12, 8'sd19, 8'sd10, 8'sd14,-8'sd10,  8'sd2,  8'sd4,-8'sd26,  8'sd1, 8'sd26, -8'sd1,-8'sd14, 8'sd19, -8'sd3,-8'sd22,-8'sd11, -8'sd3},
    '{  8'sd8,  8'sd2, -8'sd3, -8'sd6, -8'sd9,-8'sd25,  8'sd8,-8'sd13, 8'sd22, -8'sd8,-8'sd14,  8'sd1,  8'sd8, -8'sd6,-8'sd22, 8'sd18,-8'sd25, -8'sd4, -8'sd8, -8'sd3, 8'sd21, 8'sd25,-8'sd21, 8'sd18,  8'sd3,  8'sd5,  8'sd7, 8'sd11, 8'sd17,-8'sd16,  8'sd2,-8'sd11, -8'sd9,  8'sd1,  8'sd9, -8'sd6,-8'sd10, -8'sd6, -8'sd1,  8'sd7,  8'sd3, 8'sd15,-8'sd38, -8'sd4,-8'sd21,-8'sd51,  8'sd4,  8'sd9,-8'sd22,  8'sd0,-8'sd10,  8'sd0,-8'sd13,-8'sd22, 8'sd35,  8'sd2, -8'sd8,-8'sd13, -8'sd9, 8'sd17,-8'sd18,  8'sd3, 8'sd14, 8'sd12, -8'sd1,-8'sd22, 8'sd10,  8'sd3, -8'sd4, 8'sd22, 8'sd15, -8'sd2, -8'sd6},
    '{ 8'sd12,  8'sd9, 8'sd18,  8'sd0,-8'sd18,-8'sd18,-8'sd16,-8'sd12, 8'sd15,-8'sd19,-8'sd15,-8'sd33,-8'sd16, 8'sd27,-8'sd18,-8'sd27,-8'sd19, 8'sd16, -8'sd2,-8'sd16, 8'sd21, 8'sd54,-8'sd33,  8'sd7, 8'sd10,-8'sd16, 8'sd12, 8'sd16, -8'sd5,-8'sd14,-8'sd20,-8'sd25,  8'sd5,-8'sd21,-8'sd12, -8'sd8, -8'sd4,-8'sd15,  8'sd3, -8'sd9,  8'sd1,  8'sd6,-8'sd16, 8'sd23, -8'sd7,-8'sd20, 8'sd25,  8'sd1,  8'sd9,  8'sd9, 8'sd25,-8'sd20, 8'sd20, -8'sd3,-8'sd69,-8'sd38,-8'sd33, -8'sd1, 8'sd10,-8'sd23, 8'sd17,-8'sd10,  8'sd3, 8'sd10,-8'sd18,  8'sd5, -8'sd2,  8'sd7,-8'sd44, 8'sd13, -8'sd6,  8'sd6, -8'sd3},
    '{ -8'sd3, 8'sd18, 8'sd23,  8'sd5, 8'sd10, -8'sd1, -8'sd2, 8'sd12,-8'sd30, -8'sd8,  8'sd2,  8'sd8, -8'sd2,  8'sd2, 8'sd15, 8'sd19, 8'sd14,-8'sd16, -8'sd1,  8'sd6,  8'sd9, -8'sd1,  8'sd4,  8'sd5,-8'sd15,  8'sd5,-8'sd19, -8'sd3,-8'sd15, 8'sd26, 8'sd43, 8'sd12, 8'sd24, 8'sd22, -8'sd5,  8'sd3,-8'sd32,  8'sd7,-8'sd18,  8'sd2,  8'sd7, -8'sd7,  8'sd8, -8'sd5,  8'sd7, 8'sd10,-8'sd17, 8'sd20, -8'sd9, -8'sd3,-8'sd14, 8'sd19,-8'sd22, 8'sd13, 8'sd30,-8'sd22, 8'sd10,-8'sd21, 8'sd11,-8'sd14,-8'sd16, -8'sd6, -8'sd2,-8'sd32,  8'sd2, 8'sd12, 8'sd10,-8'sd46, -8'sd7,-8'sd19,-8'sd31, -8'sd6, -8'sd1},
    '{  8'sd8,-8'sd35, -8'sd5,  8'sd5, -8'sd7,-8'sd16, 8'sd19, -8'sd3,-8'sd10,  8'sd3,-8'sd17,  8'sd6, 8'sd12,  8'sd3,  8'sd1,  8'sd3,-8'sd11, 8'sd11, -8'sd2, -8'sd4,-8'sd37, -8'sd6, 8'sd22,-8'sd14,  8'sd5, 8'sd17,  8'sd2,-8'sd31,-8'sd11, 8'sd23,-8'sd31,  8'sd3,-8'sd10, -8'sd7,  8'sd1, 8'sd15, 8'sd18,-8'sd11,  8'sd3, 8'sd10,-8'sd24,  8'sd5, -8'sd2, -8'sd6, -8'sd1,-8'sd12, -8'sd4, -8'sd6,-8'sd14,-8'sd10, 8'sd16, 8'sd16, 8'sd18,  8'sd2,-8'sd56, -8'sd6,-8'sd31,-8'sd19, -8'sd6,-8'sd22, 8'sd31, 8'sd20,  8'sd1,  8'sd0,-8'sd23, -8'sd9,-8'sd31, -8'sd1,-8'sd32,  8'sd7, 8'sd39,-8'sd11,  8'sd7},
    '{  8'sd8,-8'sd25,-8'sd74,-8'sd14, -8'sd4,-8'sd11,-8'sd14, 8'sd10,-8'sd21,  8'sd2,-8'sd37, -8'sd1, 8'sd14, 8'sd16, 8'sd14,  8'sd5,-8'sd22, -8'sd6,-8'sd18,  8'sd3,-8'sd54,-8'sd30, 8'sd14, -8'sd7,-8'sd20,-8'sd26, 8'sd41,-8'sd15,  8'sd1, 8'sd11,-8'sd29, -8'sd2, -8'sd9,  8'sd5, -8'sd3, -8'sd6, 8'sd19,-8'sd27,  8'sd1,  8'sd8,-8'sd21, -8'sd5, -8'sd2,-8'sd13,-8'sd27,  8'sd7, 8'sd15,-8'sd21, -8'sd4,  8'sd3, -8'sd5,-8'sd10,-8'sd10, -8'sd4,  8'sd1, -8'sd5,  8'sd7,  8'sd7,  8'sd3, 8'sd13,-8'sd26, -8'sd6,  8'sd7,-8'sd19, 8'sd31,-8'sd27, -8'sd5,-8'sd12, 8'sd42,  8'sd1,-8'sd22, -8'sd2,  8'sd5}
};

`endif
