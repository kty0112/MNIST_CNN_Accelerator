//------------------------------------------------------------------------
// CNN Pcam Wrapper - Top-Level System Wrapper (SystemVerilog)

//Camera -> AXI Stream ->axi_stream_to_rgb_stream -> Raw RGB ->cnn_top (Pre-process -> Conv/Pool -> FC) -> 숫자 판별(0~9) ->cnn_result_axilite -> AXI-Lite -> ARM Processor (C code)
//------------------------------------------------------------------------
module cnn_pcam_wrapper #(
    parameter INPUT_WIDTH  = 1280,   // Pcam 해상도 폭
    parameter INPUT_HEIGHT = 720,    // Pcam 해상도 높이
    parameter CNN_IMG_SIZE = 448,    // CNN 입력 이미지 크기
    parameter CNN_OFFSET   = 80,     // 크롭 오프셋
    parameter CNN_SIZE     = 28      // CNN 내부 처리 크기
)(
    // Clock and Reset
    input  logic        aclk,
    input  logic        aresetn,

    // AXI Stream input (T-tap from GammaCorrection)
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    input  logic        s_axis_tuser,

    // Direct outputs (LED/debug)
    output logic [3:0]  prediction_out,
    output logic [9:0]  probability_out,

    // AXI-Lite Slave (PS reads CNN results)
    input  logic [3:0]  S_AXI_ARADDR,
    input  logic        S_AXI_ARVALID,
    output logic        S_AXI_ARREADY,
    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  logic        S_AXI_RREADY,
    input  logic [3:0]  S_AXI_AWADDR,
    input  logic        S_AXI_AWVALID,
    output logic        S_AXI_AWREADY,
    input  logic [31:0] S_AXI_WDATA,
    input  logic [3:0]  S_AXI_WSTRB,
    input  logic        S_AXI_WVALID,
    output logic        S_AXI_WREADY,
    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  logic        S_AXI_BREADY
);

    //------------------------------------------------------------------
    // Internal signals
    //------------------------------------------------------------------
    logic [7:0]  bridge_r, bridge_g, bridge_b;
    logic [10:0] bridge_column;
    logic [9:0]  bridge_row;
    logic        bridge_new_pixel;

    logic [3:0]  prediction_int;
    logic [9:0]  probability_int;

    // Direct outputs
    assign prediction_out  = prediction_int;
    assign probability_out = probability_int;

    //------------------------------------------------------------------
    // Sub-module 1: AXI Stream → rgb_stream Bridge
    //------------------------------------------------------------------
    axi_stream_to_rgb_stream #(
        .INPUT_WIDTH  (INPUT_WIDTH),
        .INPUT_HEIGHT (INPUT_HEIGHT)
    ) u_bridge (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (s_axis_tuser),
        .o_r           (bridge_r),
        .o_g           (bridge_g),
        .o_b           (bridge_b),
        .o_column      (bridge_column),
        .o_row         (bridge_row),
        .o_new_pixel   (bridge_new_pixel)
    );

    //------------------------------------------------------------------
    // Sub-module 2: CNN Core
    //------------------------------------------------------------------
    cnn_top #(
        .INPUT_COLUMNS (CNN_IMG_SIZE),
        .INPUT_ROWS    (CNN_IMG_SIZE),
        .COLUMN_OFFSET (CNN_OFFSET),
        .CNN_COLUMNS   (CNN_SIZE),
        .CNN_ROWS      (CNN_SIZE)
    ) u_cnn (
        .i_r         (bridge_r),
        .i_g         (bridge_g),
        .i_b         (bridge_b),
        .i_column    (bridge_column[9:0]),
        .i_row       (bridge_row[8:0]),
        .i_new_pixel (bridge_new_pixel),
        .prediction  (prediction_int),
        .probability (probability_int)
    );

    //------------------------------------------------------------------
    // Sub-module 3: AXI-Lite Result Register
    //------------------------------------------------------------------
    cnn_result_axilite u_result (
        .prediction    (prediction_int),
        .probability   (probability_int),
        .S_AXI_ACLK    (aclk),
        .S_AXI_ARESETN (aresetn),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY)
    );

endmodule