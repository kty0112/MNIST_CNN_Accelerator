//------------------------------------------------------------------------
// RGB to CNN Stream Converter (Verilog)
// Converted from VHDL: rgb_to_cnn.vhd
//
// [기능]
//   rgb_stream(R/G/B + Column/Row + New_Pixel)을
//   CNN_Stream_T(Column/Row/Filter/Data_Valid/Data_CLK) +
//   CNN_Values_T(data)로 변환
//
//   New_Pixel의 라이징 에지를 감지하여 Column이 변할 때마다
//   Data_Valid를 1로 설정하고, 픽셀 데이터를 CNN 값으로 전달
//
// [VHDL과의 차이]
//   VHDL record → 개별 포트
//   VHDL natural → 비트 벡터
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// RGB to CNN Stream Converter (SystemVerilog)
//------------------------------------------------------------------------
module rgb_to_cnn #(
    parameter INPUT_VALUES = 1   // 1=R only, 2=RG, 3=RGB
)(
    // rgb_stream input (flattened)
    input  logic [7:0]  i_r,
    input  logic [7:0]  i_g,
    input  logic [7:0]  i_b,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic        i_new_pixel,

    // CNN_Stream output (flattened)
    output logic        o_data_clk,
    output logic [9:0]  o_column,
    output logic [8:0]  o_row,
    output logic [3:0]  o_filter,
    output logic        o_data_valid,

    // CNN_Values output (up to 3 values, 10-bit each)
    output logic [9:0]  o_data_0,
    output logic [9:0]  o_data_1,
    output logic [9:0]  o_data_2
);

    assign o_data_clk = i_new_pixel;

    logic [9:0]  col_reg;
    logic [9:0]  column_buf;
    logic [8:0]  row_buf;
    logic        valid_buf;
    logic [9:0]  data_buf_0, data_buf_1, data_buf_2;

    always_ff @(posedge i_new_pixel) begin
        // Column이 변했으면 새로운 유효 픽셀
        valid_buf <= (i_column != col_reg) ? 1'b1 : 1'b0;

        column_buf <= i_column;
        row_buf    <= i_row;
        data_buf_0 <= {2'b0, i_r};
        
        if (INPUT_VALUES > 1)
            data_buf_1 <= {2'b0, i_g};
        if (INPUT_VALUES > 2)
            data_buf_2 <= {2'b0, i_b};
            
        // 1 클럭 지연 출력 (파이프라인)
        o_column     <= column_buf;
        o_row        <= row_buf;
        o_data_valid <= valid_buf;
        o_filter     <= 4'd0;
        o_data_0     <= data_buf_0;
        o_data_1     <= data_buf_1;
        o_data_2     <= data_buf_2;

        col_reg <= i_column;
    end

endmodule