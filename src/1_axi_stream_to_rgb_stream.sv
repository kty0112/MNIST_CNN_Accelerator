//------------------------------------------------------------------------
// AXI Stream to RGB Stream Bridge (SystemVerilog)
/*
1. 데이터 평탄화 및 분리 -> 24비트 덩어리를 RGB로 나누기
2. CNN 구동용 스트로브 클럭 생성 -> s_axis_tvalid가 들어올 때마다 pixel_clk를 반전시켜 픽셀 데이터 하나마다 연산을 할 수 있게 박자 역할
3.공간 정보 부여 -> tuser와 tlast로 행과 열 카운팅
*/
//------------------------------------------------------------------------
module axi_stream_to_rgb_stream #(
    parameter INPUT_WIDTH  = 1280,  // Pcam 입력 해상도 폭
    parameter INPUT_HEIGHT = 720    // Pcam 입력 해상도 높이
)(
    // AXI Stream input
    input  logic        aclk,
    input  logic        aresetn,
    input  logic [23:0] s_axis_tdata,   // [23:16]=R, [15:8]=G, [7:0]=B
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,    // End of Line
    input  logic        s_axis_tuser,    // Start of Frame

    // rgb_stream output
    output logic  [7:0]  o_r,
    output logic  [7:0]  o_g,
    output logic  [7:0]  o_b,
    output logic  [10:0] o_column,       // max 1279
    output logic  [9:0]  o_row,          // max 719
    output logic         o_new_pixel      // pixel clock (CNN 구동 클럭)
);

    // T-tap: 메인 파이프라인을 차단하지 않도록 항상 ready
    assign s_axis_tready = 1'b1;

    logic [$clog2(INPUT_WIDTH)-1:0]  col_cnt;
    logic [$clog2(INPUT_HEIGHT)-1:0] row_cnt;
    logic pixel_clk;

    // pixel_clk을 출력으로 전달
    always_comb o_new_pixel = pixel_clk;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            col_cnt   <= 0;
            row_cnt   <= 0;
            pixel_clk <= 1'b0;
            o_r       <= 8'd0;
            o_g       <= 8'd0;
            o_b       <= 8'd0;
            o_column  <= 0;
            o_row     <= 0;
        end else begin
            if (s_axis_tvalid) begin
                // RGB888 추출
                o_r <= s_axis_tdata[23:16];
                o_g <= s_axis_tdata[15:8];
                o_b <= s_axis_tdata[7:0];

                // 좌표 설정 (image_data_package 범위로 클램프) 1번 수정 전
                //o_column <= (col_cnt < 646) ? col_cnt[10:0] : 11'd645;
                //o_row    <= (row_cnt < 483) ? row_cnt[9:0]  : 10'd482;

                // 1280x720 해상도 전체 좌표 허용 1번 수정 후(울타리를 넓게 열어두고 448x448때만 짜르기)
                o_column <= col_cnt[10:0]; 
                o_row    <= row_cnt[9:0];

                // 프레임/라인 동기화
                if (s_axis_tuser) begin
                    // SOF: 프레임 시작
                    col_cnt <= 0;
                    row_cnt <= 0;
                end else if (s_axis_tlast) begin
                    // EOL: 라인 끝
                    col_cnt <= 0;
                    if (row_cnt < INPUT_HEIGHT - 1)
                        row_cnt <= row_cnt + 1;
                end else begin
                    if (col_cnt < INPUT_WIDTH - 1)
                        col_cnt <= col_cnt + 1;
                end

                // CNN용 픽셀 클럭 토글 (매 유효 픽셀마다)
                pixel_clk <= ~pixel_clk;
            end
        end
    end

endmodule