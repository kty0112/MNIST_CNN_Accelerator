//------------------------------------------------------------------------
// CNN Row Buffer (SystemVerilog)
// Converted from VHDL: cnn_row_buffer.vhd
//------------------------------------------------------------------------
module cnn_row_buffer #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 1,
    parameter FILTER_COLUMNS = 3,
    parameter FILTER_ROWS    = 3,
    parameter INPUT_CYCLES   = 1,
    parameter VALUE_CYCLES   = 1,
    parameter CALC_CYCLES    = 1,
    parameter STRIDES        = 1,
    parameter PADDING        = 0,       // 0=valid, 1=same
    parameter VALUE_BITS     = 10       // CNN_VALUE_RESOLUTION
)(
    // Input stream
    input  logic        i_data_clk,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic [3:0]  i_filter,
    input  logic        i_data_valid,
    input  logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] i_data,

    // Output stream
    output logic        o_data_clk,
    output logic [9:0]  o_column,
    output logic [8:0]  o_row,
    output logic [3:0]  o_filter,
    output logic        o_data_valid,
    output logic [VALUE_BITS*(INPUT_VALUES/VALUE_CYCLES)-1:0] o_data,

    // Matrix position indices (VHDL buffer ports)
    output logic [$clog2(FILTER_ROWS)-1:0]    o_mat_row,
    output logic [$clog2(FILTER_COLUMNS)-1:0] o_mat_column,
    output logic [$clog2(VALUE_CYCLES)-1:0]   o_mat_input
);

    //------------------------------------------------------------------
    // Constants & RAM Configuration
    //------------------------------------------------------------------
    // RAM 행 수 계산: INPUT_COLUMNS가 2일 때 추가 행 필요 로직 반영 [cite: 494-496]
    localparam RAM_ROWS  = (INPUT_COLUMNS == 2) ? FILTER_ROWS + 1 : FILTER_ROWS;
    localparam RAM_BITS  = VALUE_BITS * (INPUT_VALUES / VALUE_CYCLES);
    localparam RAM_WIDTH = INPUT_COLUMNS * RAM_ROWS * VALUE_CYCLES;

    assign o_data_clk = i_data_clk;

    // RAM 정의 및 접근 [cite: 500-501]
    logic [RAM_BITS-1:0] buffer_ram [0:RAM_WIDTH-1];
    logic [$clog2(RAM_WIDTH)-1:0] ram_addr_in, ram_addr_out;
    logic [RAM_BITS-1:0] ram_data_in, ram_data_out;
    logic ram_enable;

    // RAM Write (Rising Edge) [cite: 508-509]
    always_ff @(posedge i_data_clk) begin
        if (ram_enable)
            buffer_ram[ram_addr_in] <= ram_data_in;
    end

    // RAM Read (Falling Edge) [cite: 509-510]
    always_ff @(negedge i_data_clk) begin
        ram_data_out <= buffer_ram[ram_addr_out];
    end

    //------------------------------------------------------------------
    // Internal Registers (VHDL variables mapping) [cite: 510-520]
    //------------------------------------------------------------------
    logic [$clog2(RAM_ROWS)-1:0]      i_row_ram = 0;
    logic [8:0]                       i_row_reg = 0;
    logic [9:0]                       i_col_reg = 0;
    logic [3:0]                       i_val_reg = 0;
    logic [$clog2(VALUE_CYCLES)-1:0]  i_val_ram = 0;
    integer                           i_val_cnt = 0;

    logic [9:0] o_col_reg = 0, o_col_calc;
    logic [8:0] o_row_reg = 0;
    logic [$clog2(RAM_ROWS)-1:0] o_row_ram_reg;

    // Window Counters (3x3 또는 2x2 매트릭스 순회용)
    integer row_cntr = -(FILTER_ROWS/2);
    integer col_cntr = -(FILTER_COLUMNS/2);
    integer val_cntr = 0;
    integer calc_cntr = 0;
    logic   valid_reg_int = 0;

    logic [9:0] os_column;
    logic [8:0] os_row;
    logic       os_valid_reg;
    logic       o_data_en_reg;

    //------------------------------------------------------------------
    // Main Logic Block [cite: 521-576]
    //------------------------------------------------------------------
    always_ff @(posedge i_data_clk) begin
        // 1. 행 변경 추적 (순환 버퍼 관리) 
        if (i_row_reg != i_row) begin
            i_row_ram <= (i_row_ram < RAM_ROWS - 1) ? i_row_ram + 1 : 0;
        end

        // 2. 입력 데이터 채널(Value) 인덱싱 [cite: 523-528]
        if (INPUT_CYCLES == 1) begin
            if ((INPUT_COLUMNS > 1 && i_col_reg != i_column) || (INPUT_COLUMNS <= 1 && i_row_reg != i_row))
                i_val_ram <= 0;
            else if (i_val_ram < VALUE_CYCLES - 1)
                i_val_ram <= i_val_ram + 1;
            i_val_cnt <= i_val_ram;
        end
        // ... (Input_Cycles != 1 케이스 생략 가능하나 원본 로직 유지 권장)

        // 3. RAM 주소 및 데이터 쓰기 [cite: 529-533]
        ram_addr_in <= i_val_ram + (i_column + i_row_ram * INPUT_COLUMNS) * VALUE_CYCLES;
        ram_enable  <= i_data_valid;
        ram_data_in <= i_data; // Packed 데이터 할당

        // 4. 출력 좌표 계산 [cite: 533-537]
        if (INPUT_COLUMNS > 1) begin
            o_col_calc = (i_column - (FILTER_COLUMNS-1)/2) % INPUT_COLUMNS;
            if (o_col_reg > o_col_calc) begin
                o_row_reg     <= (i_row - (FILTER_ROWS-1)/2) % INPUT_ROWS;
                o_row_ram_reg <= (i_row_ram - (FILTER_ROWS-1)/2) % RAM_ROWS;
            end
            o_col_reg <= o_col_calc;
        end else begin
            o_col_reg <= 0;
            o_row_reg <= (i_row - (FILTER_ROWS-1)/2) % INPUT_ROWS;
        end

        // 5. 윈도우 스캔 카운터 (핵심 제어 로직) 
        if ((INPUT_COLUMNS > 1 && o_col_reg != os_column) || (INPUT_COLUMNS <= 1 && o_row_reg != os_row)) begin
            row_cntr  <= -(FILTER_ROWS/2);
            col_cntr  <= -(FILTER_COLUMNS/2);
            val_cntr  <= 0;
            calc_cntr <= 0;
            valid_reg_int <= 1'b1;
        end else if (calc_cntr < CALC_CYCLES - 1) begin
            calc_cntr <= calc_cntr + 1;
        end else begin
            calc_cntr <= 0;
            if (val_cntr < VALUE_CYCLES - 1) begin
                val_cntr <= val_cntr + 1;
            end else begin
                val_cntr <= 0;
                if (col_cntr < (FILTER_COLUMNS-1)/2) begin
                    col_cntr <= col_cntr + 1;
                end else if (row_cntr < (FILTER_ROWS-1)/2) begin
                    col_cntr <= -(FILTER_COLUMNS/2);
                    row_cntr <= row_cntr + 1;
                end else begin
                    valid_reg_int <= 1'b0;
                end
            end
        end

        // 6. RAM 읽기 주소 생성 [cite: 547]
        ram_addr_out <= (((o_row_ram_reg + row_cntr) % RAM_ROWS) * INPUT_COLUMNS + 
                         (o_col_reg + col_cntr) % INPUT_COLUMNS) * VALUE_CYCLES + val_cntr;

        // 7. 유효 영역 및 패딩 체크 [cite: 552-556]
        if (o_col_reg + col_cntr < 0 || o_col_reg + col_cntr > INPUT_COLUMNS - 1 ||
            o_row_reg + row_cntr < 0 || o_row_reg + row_cntr > INPUT_ROWS - 1)
            o_data_en_reg <= 1'b0;
        else
            o_data_en_reg <= 1'b1;

        // 8. 최종 출력 스트림 생성 (Padding 모드 적용) 
        if (PADDING == 0) begin // VALID Padding
            if (valid_reg_int && 
                o_col_reg >= FILTER_COLUMNS/2 && o_col_reg < INPUT_COLUMNS - (FILTER_COLUMNS-1)/2 &&
                o_row_reg >= FILTER_ROWS/2    && o_row_reg < INPUT_ROWS - (FILTER_ROWS-1)/2 &&
                (o_col_reg - FILTER_COLUMNS/2) % STRIDES == 0 &&
                (o_row_reg - FILTER_ROWS/2)    % STRIDES == 0) begin
                
                os_valid_reg <= 1'b1;
                o_column     <= (o_col_reg - FILTER_COLUMNS/2) / STRIDES;
                o_row        <= (o_row_reg - FILTER_ROWS/2) / STRIDES;
                o_data_valid <= 1'b1;
                o_data       <= ram_data_out;
            end else begin
                o_data_valid <= 1'b0;
                os_valid_reg <= 1'b0;
            end
        end else begin // SAME Padding
            if (valid_reg_int && o_col_reg % STRIDES == 0 && o_row_reg % STRIDES == 0) begin
                o_column     <= o_col_reg / STRIDES;
                o_row        <= o_row_reg / STRIDES;
                o_data_valid <= 1'b1;
                o_data       <= (o_data_en_reg) ? ram_data_out : '0;
            end else begin
                o_data_valid <= 1'b0;
            end
        end

        // 인덱스 정보 업데이트
        o_mat_row    <= row_cntr + FILTER_ROWS/2;
        o_mat_column <= col_cntr + FILTER_COLUMNS/2;
        o_mat_input  <= val_cntr;
        os_column    <= o_col_reg;
        os_row       <= o_row_reg;
        i_row_reg    <= i_row;
        i_col_reg    <= i_column;
    end

endmodule
