//------------------------------------------------------------------------
// MAX Pooling Preprocessing (Verilog)
// Converted from VHDL: max_pooling_pre.vhd
//
// [기능]
//   RGB 도메인에서 입력 이미지를 Max Pooling으로 다운스케일
//   예: 448x448 → 28x28 (16:1 비율)
//
//   동작 원리:
//   1. Filter_Columns 열씩 묶어서 열 방향 max 계산
//   2. Filter_Rows 행씩 묶어서 행 방향 max 계산 (RAM 사용)
//   3. 양방향 max가 완료되면 출력
//
// [VHDL과의 차이]
//   VHDL rgb_stream record → 개별 입출력 포트
//   VHDL natural range → 비트 벡터
//   RAM은 reg 배열로 구현
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// MAX Pooling Preprocessing (SystemVerilog)
//------------------------------------------------------------------------
module max_pooling_pre #(
    parameter INPUT_COLUMNS  = 448,
    parameter INPUT_ROWS     = 448,
    parameter INPUT_VALUES   = 1,    // 1=Grayscale, 3=RGB
    parameter FILTER_COLUMNS = 16,
    parameter FILTER_ROWS    = 16
)(
    // rgb_stream input
    input  logic [7:0]  i_r,
    input  logic [7:0]  i_g,
    input  logic [7:0]  i_b,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic        i_new_pixel,

    // rgb_stream output
    output logic [7:0]  o_r,
    output logic [7:0]  o_g,
    output logic [7:0]  o_b,
    output logic [9:0]  o_column,
    output logic [8:0]  o_row,
    output logic        o_new_pixel
);

    localparam RAM_BITS  = 8 * INPUT_VALUES;
    localparam RAM_WIDTH = INPUT_COLUMNS / FILTER_COLUMNS; // RAM에 몇칸 만들지

    assign o_new_pixel = i_new_pixel;

    // RAM for row accumulation
    logic [RAM_BITS-1:0] buffer_ram [0:RAM_WIDTH-1]; //RAM 본체
    logic [$clog2(RAM_WIDTH)-1:0] ram_addr_in, ram_addr_out;
    logic [23:0] ram_data_in;
    logic [23:0] ram_data_out; //원래는 8비트인데 RGB가 들어와도 처리 할 수 있게

    // RAM write
    always_ff @(posedge i_new_pixel) begin
        // ram_enable 조건에서만 쓰기 (아래 메인 로직에서 제어)
    end

    assign ram_data_out[RAM_BITS-1:0] = buffer_ram[ram_addr_out];

    // Buffered input
    logic [7:0]  r_buf, g_buf, b_buf;
    logic [9:0]  col_buf;
    logic [8:0]  row_buf;
    logic [9:0]  col_reg; //col_buf 한 클럭 전 값

    // Output buffer
    logic [7:0]  r_out, g_out, b_out;
    logic [9:0]  col_out;
    logic [8:0]  row_out;

    // Column max accumulator
    logic [7:0] max_col_r, max_col_g, max_col_b;
    logic [$clog2(FILTER_COLUMNS)-1:0] max_col_cnt;

    always_ff @(posedge i_new_pixel) begin
        // Stage 1: 입력 버퍼링
        r_buf   <= i_r; // pool_r이라는 gray신호 하나만 여기에 들어감
        g_buf   <= (INPUT_VALUES > 1) ? i_g : 8'd0;
        b_buf   <= (INPUT_VALUES > 2) ? i_b : 8'd0;
        col_buf <= i_column;
        row_buf <= i_row;

        // Stage 2: 출력 전달
        o_r      <= r_out;
        o_g      <= g_out;
        o_b      <= b_out;
        o_column <= col_out;
        o_row    <= row_out;

        col_reg <= col_buf;
        // 메인 Max Pooling 로직
        if (col_buf != col_reg && col_buf < INPUT_COLUMNS && row_buf < INPUT_ROWS) begin
            // 열 카운터 관리 (현재 열과 이전 값이 다를때만 실행 왜냐면 cnn_top에서 제외 픽셀을 최대 픽셀 고정으로 저장)
            if (col_buf == 0)
                max_col_cnt <= 0;
            else if (max_col_cnt < FILTER_COLUMNS - 1)
                max_col_cnt <= max_col_cnt + 1;
            else
                max_col_cnt <= 0;// 16개씩 circular

            // 열 방향 max 계산 (첫번째는 비교 할 대상이 없어서 일단 저장)
            if (max_col_cnt == 0 || col_buf == 0) begin
                max_col_r <= r_buf;
                max_col_g <= g_buf;
                max_col_b <= b_buf;
            end else begin
                if (r_buf > max_col_r) max_col_r <= r_buf;
                if (INPUT_VALUES > 1 && g_buf > max_col_g) max_col_g <= g_buf;
                if (INPUT_VALUES > 2 && b_buf > max_col_b) max_col_b <= b_buf;
            end

            // 열 그룹 완료
            if (max_col_cnt == FILTER_COLUMNS - 1 || col_buf == 0 && FILTER_COLUMNS == 1) begin
                ram_addr_out <= col_buf / FILTER_COLUMNS;
                ram_addr_in  <= col_buf / FILTER_COLUMNS;

                // 행 방향 max (중간 행: RAM과 비교)
                if (row_buf % FILTER_ROWS > 0) begin
                    if (ram_data_out[7:0] > max_col_r) max_col_r <= ram_data_out[7:0];
                    if (INPUT_VALUES > 1 && ram_data_out[15:8]  > max_col_g) max_col_g <= ram_data_out[15:8];
                    if (INPUT_VALUES > 2 && ram_data_out[23:16] > max_col_b) max_col_b <= ram_data_out[23:16];
                end

                // 최종 행: 출력
                if (row_buf % FILTER_ROWS == FILTER_ROWS - 1) begin
                    r_out   <= max_col_r;
                    g_out   <= (INPUT_VALUES > 1) ? max_col_g : 8'd0;
                    b_out   <= (INPUT_VALUES > 2) ? max_col_b : 8'd0;
                    col_out <= col_buf / FILTER_COLUMNS;
                    row_out <= row_buf / FILTER_ROWS;
                end else begin
                    // 중간 행: RAM에 저장 (가장 첫번째 상황)
                    ram_data_in[7:0]   <= max_col_r;
                    ram_data_in[15:8]  <= (INPUT_VALUES > 1) ? max_col_g : 8'd0;
                    ram_data_in[23:16] <= (INPUT_VALUES > 2) ? max_col_b : 8'd0;
                    buffer_ram[ram_addr_in] <= ram_data_in[RAM_BITS-1:0];
                end
            end
        end

    end

endmodule