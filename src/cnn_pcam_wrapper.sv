//------------------------------------------------------------------------
// CNN Pcam Wrapper - Top-Level System Wrapper (SystemVerilog)
// Converted from VHDL: cnn_pcam_wrapper.vhd
//
// [데이터 흐름]
// Pcam Camera (AXI Stream) 
//   -> axi_stream_to_rgb_stream (RAW RGB 추출 & 클럭 동기화)
//   -> cnn_top (이미지 크롭, 전처리, Conv/Pool 연산, FC, Argmax)
//   -> cnn_result_axilite (Zynq PS/ARM용 AXI-Lite 레지스터로 결과 전송)
//------------------------------------------------------------------------
`include "cnn_config_pkg.vh"
`include "image_data_pkg.vh"

module cnn_pcam_wrapper #(
    parameter INPUT_WIDTH  = 1280,   // Pcam 해상도 폭
    parameter INPUT_HEIGHT = 720,    // Pcam 해상도 높이
    parameter CNN_IMG_SIZE = 448,    // CNN 입력 이미지 크기
    parameter CNN_OFFSET   = 80,     // 크롭 오프셋 (X 좌표 시작점)
    parameter CNN_SIZE     = 28      // CNN 내부 처리 크기
)(
    // Clock and Reset (150MHz)
    input  logic        aclk,
    input  logic        aresetn,

    // AXI Stream Input (From Camera/GammaCorrection)
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    input  logic        s_axis_tuser,

    // Direct Outputs (외부 LED 모니터링 또는 디버깅용)
    output logic [3:0]  prediction_out,
    output logic [9:0]  probability_out,

    // AXI-Lite Slave Interface (Zynq PS / ARM Processor 접근용)
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
    // 내부 연결 신호 (Internal Signals)
    //------------------------------------------------------------------
    // Bridge -> CNN 통신용 신호
    logic [7:0]  bridge_r, bridge_g, bridge_b;
    logic [10:0] bridge_column;
    logic [9:0]  bridge_row;
    logic        bridge_new_pixel;

    // CNN -> AXI-Lite & Debug 통신용 신호
    logic [3:0]  prediction_int;
    logic [9:0]  probability_int;

    // 내부 결과를 외부 출력 포트로 연결
    assign prediction_out  = prediction_int;
    assign probability_out = probability_int;

    //------------------------------------------------------------------
    // 1. 영상 스트림 브릿지 (AXI Stream -> Raw RGB)
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
    // 2. CNN 코어 (MNIST 숫자 인식 엔진)
    //------------------------------------------------------------------
    cnn_top #(
        .INPUT_COLUMNS (CNN_IMG_SIZE),
        .INPUT_ROWS    (CNN_IMG_SIZE),
        .COLUMN_OFFSET (CNN_OFFSET),
        .CNN_COLUMNS   (CNN_SIZE),
        .CNN_ROWS      (CNN_SIZE)
    ) u_cnn (
        // 입력 해상도(1280x720)의 비트 수(11bit/10bit)를 CNN 내부 스펙(10bit/9bit)에 맞게 잘라서(Truncate) 인가
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
    // 3. AXI-Lite 레지스터 인터페이스 (결과를 C언어에서 읽어갈 수 있도록 맵핑)
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
