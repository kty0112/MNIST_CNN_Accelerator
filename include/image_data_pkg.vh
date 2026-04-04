//------------------------------------------------------------------------
// Image Data Package (Verilog Header)
// Converted from VHDL: image_data_pkg.vhd
// Original: OnSemi_CNN_Ultra (Leon Beier, Protop Solutions UG, 2020)
//
// VHDL의 package를 Verilog `include 헤더로 변환.
// VHDL record 타입(rgb_stream, rgb_data)은 Verilog에서
// 개별 신호(wire/reg)로 평탄화하여 사용.
//------------------------------------------------------------------------
`ifndef IMAGE_DATA_PKG_VH
`define IMAGE_DATA_PKG_VH

// Image sensor parameters
localparam IMAGE_WIDTH    = 646;
localparam IMAGE_HEIGHT   = 483;
localparam IMAGE_FPS      = 30;
localparam IMAGE_EXPOSURE = 100;

// HDMI Timing
localparam HDMI_WIDTH  = 640;
localparam HDMI_HEIGHT = 480;

localparam HBP_LEN   = 47;
localparam HFP_LEN   = 16;
localparam HSLEN_LEN = 96;

localparam VBP_LEN   = 33;
localparam VFP_LEN   = 10;
localparam VSLEN_LEN = 2;

// Column/Row bit widths (derived from IMAGE_WIDTH/HEIGHT)
localparam COL_BITS = $clog2(IMAGE_WIDTH);   // 10 bits for 646
localparam ROW_BITS = $clog2(IMAGE_HEIGHT);  //  9 bits for 483

//------------------------------------------------------------------------
// VHDL record → Verilog 신호 매핑 가이드
//------------------------------------------------------------------------
// VHDL rgb_data record:
//   R : std_logic_vector(7 downto 0)   → [7:0] r
//   G : std_logic_vector(7 downto 0)   → [7:0] g
//   B : std_logic_vector(7 downto 0)   → [7:0] b
//
// VHDL rgb_stream record:
//   R         : std_logic_vector(7 downto 0)       → [7:0] r
//   G         : std_logic_vector(7 downto 0)       → [7:0] g
//   B         : std_logic_vector(7 downto 0)       → [7:0] b
//   Column    : natural range 0 to Image_Width-1   → [COL_BITS-1:0] column
//   Row       : natural range 0 to Image_Height-1  → [ROW_BITS-1:0] row
//   New_Pixel : std_logic                           → new_pixel
//------------------------------------------------------------------------

`endif
