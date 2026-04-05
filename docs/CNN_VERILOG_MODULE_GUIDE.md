# CNN MNIST Verilog Module Guide

> **대상 독자**: SystemVerilog/Verilog를 학습하는 학생 및 FPGA 엔지니어  
> **원본**: OnSemi CNN Ultra (VHDP → VHDL → Verilog 변환)  
> **플랫폼**: Zybo Z7-20 (Xilinx Zynq-7020) + Pcam-5C (OV5640 MIPI)

---

## 목차

1. [시스템 개요](#1-시스템-개요)
2. [파일 구조](#2-파일-구조)
3. [VHDL → Verilog 변환 가이드](#3-vhdl--verilog-변환-가이드)
4. [모듈 상세 설명](#4-모듈-상세-설명)
   - 4.1 [image_data_pkg.vh — 이미지 타입 정의](#41-image_data_pkgvh--이미지-타입-정의)
   - 4.2 [cnn_config_pkg.vh — CNN 설정/활성화 함수](#42-cnn_config_pkgvh--cnn-설정활성화-함수)
   - 4.3 [cnn_data_pkg.vh — 학습된 가중치 데이터](#43-cnn_data_pkgvh--학습된-가중치-데이터)
   - 4.4 [axi_stream_to_rgb_stream — AXI → RGB 브릿지](#44-axi_stream_to_rgb_stream--axi--rgb-브릿지)
   - 4.5 [max_pooling_pre — 전처리 다운스케일](#45-max_pooling_pre--전처리-다운스케일)
   - 4.6 [rgb_to_cnn — RGB → CNN 스트림 변환](#46-rgb_to_cnn--rgb--cnn-스트림-변환)
   - 4.7 [cnn_row_expander — 행 시간 확장기](#47-cnn_row_expander--행-시간-확장기)
   - 4.8 [cnn_row_buffer — 컨볼루션 매트릭스 버퍼](#48-cnn_row_buffer--컨볼루션-매트릭스-버퍼)
   - 4.9 [cnn_convolution — 2D 컨볼루션 레이어](#49-cnn_convolution--2d-컨볼루션-레이어)
   - 4.10 [cnn_pooling — Max Pooling 레이어](#410-cnn_pooling--max-pooling-레이어)
   - 4.11 [nn_layer — Fully Connected 레이어](#411-nn_layer--fully-connected-레이어)
   - 4.12 [cnn_top — CNN 최상위 모듈](#412-cnn_top--cnn-최상위-모듈)
   - 4.13 [cnn_result_axilite — AXI-Lite 레지스터](#413-cnn_result_axilite--axi-lite-레지스터)
   - 4.14 [cnn_pcam_wrapper — 시스템 래퍼](#414-cnn_pcam_wrapper--시스템-래퍼)
5. [데이터 흐름 다이어그램](#5-데이터-흐름-다이어그램)
6. [CNN 아키텍처 상세](#6-cnn-아키텍처-상세)
7. [고정소수점 연산 이해하기](#7-고정소수점-연산-이해하기)
8. [FPGA 리소스 사용량](#8-fpga-리소스-사용량)
9. [시뮬레이션 방법](#9-시뮬레이션-방법)

---

## 1. 시스템 개요

이 프로젝트는 **Zybo Z7-20 FPGA**에서 **MNIST 손글씨 숫자(0~9)를 실시간 인식**하는 CNN(Convolutional Neural Network)을 하드웨어로 구현한 것입니다.

```
Pcam-5C 카메라 (720p@60fps)
    │
    ▼
[MIPI D-PHY] → [CSI-2] → [BayerToRGB] → [Gamma]
                                              │
                                     [AXI Stream Broadcaster]
                                        │              │
                                        ▼              ▼
                                     [VDMA]     [CNN Wrapper]
                                        │              │
                                        ▼              ▼
                                   HDMI 출력     AXI-Lite 레지스터
                                  (원본 영상)         │
                                                      ▼
                                               Zynq PS (ARM)
                                                      │
                                                      ▼
                                              UART: "Digit: 3 (87%)"
```

### 핵심 특징
- **LeNet 스타일 3-layer CNN**: Conv1(4f) → Pool1 → Conv2(6f) → Pool2 → Conv3(8f) → Pool3 → FC(72→10)
- **8-bit 고정소수점**: 학습된 가중치 1,438개
- **초저지연**: 프레임 단위 실시간 추론 (클럭 당 1 픽셀 처리)
- **초경량**: LUT 3.44%, BRAM 2.14%, DSP 1.82% (xc7z020)

---

## 2. 파일 구조

```
verilog/
├── include/                          ← 헤더 파일 (VHDL package 대응)
│   ├── image_data_pkg.vh             ← 이미지 해상도, 타이밍 상수
│   ├── cnn_config_pkg.vh             ← CNN 설정, 활성화 함수 인코딩
│   └── cnn_data_pkg.vh              ← 가중치 1,438개, 레이어 설정
│
├── src/                              ← 모듈 소스 (VHDL entity 대응)
│   ├── axi_stream_to_rgb_stream.v    ← AXI Stream → RGB 변환
│   ├── max_pooling_pre.v             ← 전처리 다운스케일 (448→28)
│   ├── rgb_to_cnn.v                  ← RGB → CNN 스트림 변환
│   ├── cnn_row_expander.v            ← 행 시간 확장기
│   ├── cnn_row_buffer.v              ← 2D 매트릭스 버퍼
│   ├── cnn_convolution.v             ← 2D 컨볼루션 레이어
│   ├── cnn_pooling.v                 ← Max Pooling 레이어
│   ├── nn_layer.v                    ← Fully Connected 레이어
│   ├── cnn_top.v                     ← CNN 최상위 (전체 파이프라인)
│   ├── cnn_result_axilite.v          ← AXI-Lite 결과 레지스터
│   └── cnn_pcam_wrapper.v            ← 시스템 래퍼 (Vivado IP)
│
└── tb/                               ← 테스트벤치
    └── cnn_top_tb.v                  ← 숫자 "1" 패턴 검증
```

**원본 VHDL** (비교용):
```
src/
├── image_data_pkg.vhd
├── cnn_config_pkg.vhd
├── cnn_data_pkg.vhd
├── cnn_row_expander.vhd
├── cnn_row_buffer.vhd
├── cnn_convolution.vhd
├── cnn_pooling.vhd
├── nn_layer.vhd
├── max_pooling_pre.vhd
├── rgb_to_cnn.vhd
├── cnn_top.vhd
├── axi_stream_to_rgb_stream.vhd
├── cnn_result_axilite.vhd
└── cnn_pcam_wrapper.vhd
```

---

## 3. VHDL → Verilog 변환 가이드

이 섹션은 VHDL과 Verilog 양쪽을 이해하고 싶은 학생을 위한 것입니다.

### 3.1 Package → Include Header

| VHDL | Verilog |
|------|---------|
| `package cnn_config_package is` | `cnn_config_pkg.vh` (`ifndef` 가드) |
| `use work.cnn_config_package.all;` | `` `include "cnn_config_pkg.vh" `` |
| `constant X : natural := 10;` | `localparam X = 10;` |

### 3.2 Record → Flattened Ports

VHDL의 record 타입은 여러 신호를 하나로 묶는 구조체입니다. Verilog에는 이에 해당하는 기능이 없으므로(SystemVerilog의 struct 제외) 개별 포트로 평탄화합니다.

```vhdl
-- VHDL: record로 묶인 포트
port (
    iStream : in  rgb_stream;  -- R, G, B, Column, Row, New_Pixel
);
```

```verilog
// Verilog: 개별 포트로 평탄화
input  wire [7:0]  i_r,
input  wire [7:0]  i_g,
input  wire [7:0]  i_b,
input  wire [9:0]  i_column,
input  wire [8:0]  i_row,
input  wire        i_new_pixel
```

### 3.3 Generic → Parameter

```vhdl
-- VHDL
entity cnn_convolution is
    generic (
        Input_Columns : natural := 28;
        Activation    : Activation_T := relu
    );
```

```verilog
// Verilog
module cnn_convolution #(
    parameter INPUT_COLUMNS  = 28,
    parameter [2:0] ACTIVATION = 3'd0  // 0=relu
)(
```

### 3.4 Enum → Localparam

```vhdl
-- VHDL
type Activation_T is (relu, linear, leaky_relu, step_func, sign_func);
```

```verilog
// Verilog
localparam [2:0] ACT_RELU       = 3'd0;
localparam [2:0] ACT_LINEAR     = 3'd1;
localparam [2:0] ACT_LEAKY_RELU = 3'd2;
localparam [2:0] ACT_STEP       = 3'd3;
localparam [2:0] ACT_SIGN       = 3'd4;
```

### 3.5 Process → Always Block

```vhdl
-- VHDL: process with rising_edge
process(clk)
begin
    if rising_edge(clk) then
        if condition then
            signal_a <= data;
        end if;
    end if;
end process;
```

```verilog
// Verilog: always block
always @(posedge clk) begin
    if (condition)
        signal_a <= data;
end
```

### 3.6 Generate → Generate

```vhdl
-- VHDL
gen_expand: if Expand generate
    u_exp: entity work.cnn_row_expander
        generic map (...) port map (...);
end generate;
```

```verilog
// Verilog
generate
    if (EXPAND) begin : gen_expand
        cnn_row_expander #(...) u_exp (...);
    end
endgenerate
```

### 3.7 Signed Arithmetic

```vhdl
-- VHDL: shift_right, to_signed
sum := shift_right(to_signed(a * b, WIDTH), SHIFT);
```

```verilog
// Verilog: $signed, >>>
sum = ($signed(a) * $signed(b)) >>> SHIFT;
```

### 3.8 Array Types

```vhdl
-- VHDL: unconstrained array
type CNN_Values_T is array (natural range <>) of CNN_Value_T;
signal oData : CNN_Values_T(3 downto 0);  -- 4 elements, 10-bit each
```

```verilog
// Verilog: packed bit vector
wire [10*4-1:0] o_data;  // 40 bits = 4 × 10-bit values
// 또는
wire [9:0] o_data [0:3];  // unpacked array (SystemVerilog)
```

---

## 4. 모듈 상세 설명

### 4.1 image_data_pkg.vh — 이미지 타입 정의

**파일**: `verilog/include/image_data_pkg.vh`  
**VHDL 대응**: `src/image_data_pkg.vhd`

카메라 입력 이미지와 HDMI 출력에 관한 상수를 정의합니다.

| 상수 | 값 | 설명 |
|------|-----|------|
| `IMAGE_WIDTH` | 646 | 센서 이미지 폭 (blanking 포함) |
| `IMAGE_HEIGHT` | 483 | 센서 이미지 높이 |
| `HDMI_WIDTH` | 640 | HDMI 출력 폭 |
| `HDMI_HEIGHT` | 480 | HDMI 출력 높이 |

**핵심 개념**: VHDL의 `rgb_stream` record는 R/G/B(각 8-bit) + Column + Row + New_Pixel을 하나로 묶은 타입입니다. Verilog에서는 이를 개별 신호로 분리하여 사용합니다.

---

### 4.2 cnn_config_pkg.vh — CNN 설정/활성화 함수

**파일**: `verilog/include/cnn_config_pkg.vh`  
**VHDL 대응**: `src/cnn_config_pkg.vhd`

CNN의 핵심 파라미터와 활성화 함수 인코딩을 정의합니다.

| 파라미터 | 값 | 설명 |
|----------|-----|------|
| `CNN_VALUE_RESOLUTION` | 10 | 데이터 값 비트 수 (0~1023) |
| `CNN_WEIGHT_RESOLUTION` | 8 | 가중치 비트 수 (-127~+127) |
| `CNN_INPUT_COLUMNS` | 448 | CNN 입력 이미지 폭 |
| `CNN_INPUT_ROWS` | 448 | CNN 입력 이미지 높이 |

**활성화 함수**: ReLU가 기본. VHDL에서는 overloaded function으로 구현되어 있었으나, Verilog에서는 `function` 또는 조건 연산자로 변환합니다.

```
ReLU(x) = max(0, min(x, 1023))
```

---

### 4.3 cnn_data_pkg.vh — 학습된 가중치 데이터

**파일**: `verilog/include/cnn_data_pkg.vh`  
**VHDL 대응**: `src/cnn_data_pkg.vhd`

TensorFlow로 학습된 **1,438개의 8-bit 고정소수점 가중치**를 ROM 상수로 저장합니다.

| 레이어 | 가중치 수 | 구조 |
|--------|-----------|------|
| Conv1 | 4×10 = 40 | 4 필터 × (3×3×1 커널 + 1 바이어스) |
| Conv2 | 6×37 = 222 | 6 필터 × (3×3×4 커널 + 1 바이어스) |
| Conv3 | 8×55 = 440 | 8 필터 × (3×3×6 커널 + 1 바이어스) |
| FC | 10×73 = 730 | 10 출력 × (72 입력 + 1 바이어스) |
| **합계** | **1,438** | |

**VHDL→Verilog 변환 포인트**: VHDL에서는 `CNN_Weights_T` 2D 배열 상수로 선언했으나, Verilog에서는 SystemVerilog의 2D parameter 배열(`localparam signed [7:0] L1_W [0:3][0:9]`)을 사용합니다.

---

### 4.4 axi_stream_to_rgb_stream — AXI → RGB 브릿지

**파일**: `verilog/src/axi_stream_to_rgb_stream.v`  
**VHDL 대응**: `src/axi_stream_to_rgb_stream.vhd`

```
AXI Stream (24-bit tdata)  →  RGB Stream (R/G/B + Column/Row + pixel_clk)
```

**역할**: Pcam 카메라 파이프라인의 GammaCorrection IP가 출력하는 AXI Stream(AMBA AXI4-Stream 프로토콜)을 CNN이 이해하는 간단한 RGB 스트림으로 변환합니다.

**핵심 동작**:
1. `tdata[23:16]` → R, `tdata[15:8]` → G, `tdata[7:0]` → B
2. `tuser` = SOF(Start of Frame) → 카운터 리셋
3. `tlast` = EOL(End of Line) → Column 리셋, Row 증가
4. `tready` = 항상 1 (T-tap이므로 백프레셔 없음)
5. 매 유효 픽셀마다 `pixel_clk` 토글 → CNN의 구동 클럭

**중요**: 이 모듈은 AXI Stream의 **T-tap**(분기 탭)에 연결됩니다. 메인 파이프라인(VDMA→HDMI)을 차단하지 않도록 `tready`를 항상 1로 유지합니다.

---

### 4.5 max_pooling_pre — 전처리 다운스케일

**파일**: `verilog/src/max_pooling_pre.v`  
**VHDL 대응**: `src/max_pooling_pre.vhd`

```
448×448 RGB → 28×28 RGB (16:1 Max Pooling)
```

**역할**: 카메라의 고해상도 이미지를 CNN 입력 크기(28×28)로 줄이면서, Max Pooling으로 중요한 특징(밝은 에지)을 보존합니다.

**동작 원리**:
1. **열 방향 Max**: 16 픽셀씩 묶어서 최대값 선택
2. **행 방향 Max**: RAM에 중간 행의 max를 저장하고, 16행 완료 시 최종 max 출력
3. 결과: 16×16 = 256 픽셀당 1 픽셀 출력

```
입력: □□□□□□□□□□□□□□□□  (16 pixels)
       ↓ max ↓
출력:        ■               (1 pixel = max of 16)
```

**RAM 구조**: `RAM_WIDTH = INPUT_COLUMNS / FILTER_COLUMNS = 448/16 = 28`개 엔트리. 각 엔트리에 중간 행의 max 값 저장.

---

### 4.6 rgb_to_cnn — RGB → CNN 스트림 변환

**파일**: `verilog/src/rgb_to_cnn.v`  
**VHDL 대응**: `src/rgb_to_cnn.vhd`

```
rgb_stream (R/G/B/Column/Row/New_Pixel)
    ↓
CNN_Stream (Column/Row/Filter/Data_Valid/Data_CLK) + CNN_Values (data)
```

**역할**: RGB 도메인의 스트림을 CNN 내부 도메인의 스트림으로 변환합니다. 핵심은 `New_Pixel` → `Data_CLK`, Column 변화 감지 → `Data_Valid` 생성입니다.

---

### 4.7 cnn_row_expander — 행 시간 확장기

**파일**: `verilog/src/cnn_row_expander.v`  
**VHDL 대응**: `src/cnn_row_expander.vhd`

```
입력: -_-_-_-_________  (데이터가 연속으로 밀집)
출력: -___-___-___-___  (데이터 사이에 빈 사이클 삽입)
```

**역할**: 후단의 Convolution/Pooling이 각 데이터를 처리하는 데 여러 클럭 사이클이 필요하므로, 입력 데이터 사이에 "빈 시간"을 삽입하여 처리 시간을 확보합니다.

**비유**: 컨베이어 벨트 위의 물건 간격을 벌리는 것. 빠르게 들어오는 데이터를 RAM에 한 줄 저장한 후, 느린 속도로 다시 내보냅니다.

**핵심 메커니즘**:
1. Falling edge에서 RAM read/write (양 에지 활용으로 처리량 2배)
2. Rising edge에서 카운터 관리 및 출력 제어
3. `OUTPUT_CYCLES` 파라미터로 간격 조절 (클수록 느리게 출력)

---

### 4.8 cnn_row_buffer — 컨볼루션 매트릭스 버퍼

**파일**: `verilog/src/cnn_row_buffer.v`  
**VHDL 대응**: `src/cnn_row_buffer.vhd`

```
입력: 한 번에 1 픽셀씩 순차 입력
출력: Filter_Rows × Filter_Columns 크기의 2D 매트릭스를 순차 출력
```

**역할**: Convolution과 Pooling 연산에 필요한 **2D 윈도우(커널) 데이터**를 RAM에서 구성합니다. 3×3 컨볼루션이면 3행을 버퍼링하여 매 출력 위치에서 9개 값을 순서대로 내보냅니다.

**비유**: 망원경으로 이미지를 스캔하는 것. 한 위치에서 3×3 = 9픽셀을 보고, 다음 위치로 이동하여 다시 9픽셀을 봅니다.

**핵심 구조**:
- **순환 행 버퍼(Circular Row Buffer)**: `RAM_ROWS`개 행을 원형으로 관리
- **Same/Valid 패딩**: `same`은 입력 크기 유지(경계 0 패딩), `valid`는 경계 제거
- **Strides**: 스트라이드 > 1이면 출력 위치를 건너뜀

```
RAM (3행 저장):
  Row 0: [p00 p01 p02 ... p27]
  Row 1: [p10 p11 p12 ... p27]
  Row 2: [p20 p21 p22 ... p27]  ← 현재 입력 행

출력 (위치 (1,1)에서):
  [p00 p01 p02]
  [p10 p11 p12]   ← 3×3 매트릭스
  [p20 p21 p22]
```

---

### 4.9 cnn_convolution — 2D 컨볼루션 레이어

**파일**: `verilog/src/cnn_convolution.v`  
**VHDL 대응**: `src/cnn_convolution.vhd`

```
입력: Width × Height × In_Channels
출력: Width × Height × Filters  (same padding)
      또는 더 작은 크기 (valid padding)
```

**역할**: CNN의 핵심 연산인 2D 컨볼루션을 수행합니다.

**내부 구조 (서브모듈 포함)**:
```
Input → [Row Expander] → [Row Buffer] → [MAC + Bias + ReLU] → Output
                                              ↑
                                         [Weight ROM]
```

**연산 과정**:

1. **Row Expander**: 입력 데이터 간격 확보
2. **Row Buffer**: 3×3 매트릭스 구성
3. **MAC(Multiply-Accumulate)**:
   ```
   sum[filter] = Σ (input[i] × weight[filter][i] + rounding) >> shift
   ```
4. **바이어스 가산**: `sum += bias[filter] << offset`
5. **오프셋 스케일링**: 고정소수점 자릿수 조정
6. **ReLU 활성화**: `output = max(0, min(sum, 1023))`

**시분할(Time-Multiplexing)**:
- `CALC_CYCLES`: 필터가 많을 때 여러 사이클에 걸쳐 계산
- `FILTER_CYCLES`: 출력을 여러 사이클에 걸쳐 내보냄
- SUM_RAM: 시분할 계산 중간 결과 저장
- OUT_RAM: 활성화 적용 후 결과 저장

**이 프로젝트의 인스턴스**:
| 인스턴스 | 입력 | 출력 | 필터 | Calc/Filter Cycles |
|----------|------|------|------|--------------------|
| u_conv1 | 28×28×1 | 28×28×4 | 3×3 | 4/4 |
| u_conv2 | 14×14×4 | 14×14×6 | 3×3 | 6/6 |
| u_conv3 | 7×7×6 | 7×7×8 | 3×3 | 8/8 |

---

### 4.10 cnn_pooling — Max Pooling 레이어

**파일**: `verilog/src/cnn_pooling.v`  
**VHDL 대응**: `src/cnn_pooling.vhd`

```
입력: W × H × C
출력: (W/2) × (H/2) × C  (2×2 pooling, stride 2)
```

**역할**: Feature Map의 공간 해상도를 줄이면서 중요한 특징(최대값)만 보존합니다.

**Convolution과의 차이**:
| | Convolution | Max Pooling |
|---|---|---|
| 연산 | 곱셈 + 덧셈 (MAC) | 비교 (max) |
| 가중치 | 있음 (학습됨) | 없음 |
| DSP 사용 | 있음 | 없음 |
| 채널 변환 | In → Out (다를 수 있음) | In → In (동일) |

**동작**:
1. Row Buffer로 2×2 윈도우 구성
2. 4개 값 중 최대값 선택
3. MAX_RAM에 중간 결과 저장 (다채널 시분할)
4. OUT_RAM → Filter_Cycles에 걸쳐 출력

```
입력 2×2 윈도우:        출력:
  [ 3   7 ]
  [ 1   5 ]    →    7  (최대값)
```

---

### 4.11 nn_layer — Fully Connected 레이어

**파일**: `verilog/src/nn_layer.v`  
**VHDL 대응**: `src/nn_layer.vhd`

```
입력: 72개 값 (Flatten된 3×3×8)
출력: 10개 값 (숫자 0~9 각 클래스 점수)
```

**역할**: CNN의 마지막 분류 단계. 모든 입력 뉴런과 모든 출력 뉴런 사이의 가중합을 계산합니다.

**연산**:
```
output[j] = ReLU(Σ_i (input[i] × weight[j][i]) + bias[j])

j = 0~9 (숫자 클래스)
i = 0~71 (입력 특징)
```

**Convolution과의 차이**:
- Row Buffer 불필요 (공간 구조 없음, 1D→1D)
- `iCycle`로 시분할 입력 위치 지정
- 가중치 수가 많음 (72×10 = 720 + 10 bias = 730)

**시분할 처리**:
- 72개 입력이 1개씩 순차 도착 (`CALC_CYCLES_IN = 72`)
- 10개 출력도 1개씩 순차 출력 (`OUT_CYCLES = 10`)
- SUM_RAM에 10개 누적합 저장

---

### 4.12 cnn_top — CNN 최상위 모듈

**파일**: `verilog/src/cnn_top.v`  
**VHDL 대응**: `src/cnn_top.vhd`

전체 CNN 파이프라인을 조립하는 최상위 모듈입니다.

**파이프라인 스테이지**:

```
Stage 1: RGB → Grayscale (BT.601)
         Gray = (77×R + 150×G + 29×B) >> 8

Stage 2: 영역 크롭 (Column_Offset=80부터 448 픽셀)

Stage 3: Max Pooling 전처리 (448×448 → 28×28)
         ├── max_pooling_pre

Stage 4: RGB → CNN 스트림 변환
         ├── rgb_to_cnn

Stage 5: Conv1 (28×28×1 → 28×28×4)
         ├── cnn_convolution (L1_W, 40 weights)

Stage 6: Pool1 (28×28×4 → 14×14×4)
         ├── cnn_pooling

Stage 7: Conv2 (14×14×4 → 14×14×6)
         ├── cnn_convolution (L2_W, 222 weights)

Stage 8: Pool2 (14×14×6 → 7×7×6)
         ├── cnn_pooling

Stage 9: Conv3 (7×7×6 → 7×7×8)
         ├── cnn_convolution (L3_W, 440 weights)

Stage 10: Pool3 (7×7×8 → 3×3×8)
          ├── cnn_pooling

Stage 11: Flatten (3×3×8 = 72 elements)
          index = Row × 3 × 8 + Column × 8 + Filter

Stage 12: FC (72 → 10)
          ├── nn_layer (NN1_W, 730 weights)

Stage 13: Argmax
          Prediction = argmax(FC_output)
          Probability = max(FC_output)
```

---

### 4.13 cnn_result_axilite — AXI-Lite 레지스터

**파일**: `verilog/src/cnn_result_axilite.v`  
**VHDL 대응**: `src/cnn_result_axilite.vhd`

**역할**: CNN 결과를 Zynq PS(ARM Cortex-A9)에서 읽을 수 있도록 AXI-Lite 슬레이브 인터페이스를 제공합니다.

**레지스터 맵**:
| 오프셋 | 이름 | 비트 | 접근 | 설명 |
|--------|------|------|------|------|
| 0x00 | Prediction | [3:0] | R/O | 인식된 숫자 (0~9) |
| 0x04 | Probability | [9:0] | R/O | 신뢰도 (0~1023) |
| 0x08 | Status | [0] | R/O | 결과 유효 (항상 1) |

**AXI-Lite 프로토콜**:
```
PS(ARM) → ARADDR/ARVALID → 이 모듈 → ARREADY
                                        ↓
PS(ARM) ← RDATA/RVALID  ← 이 모듈
```

**주의**: Write 채널은 수락하고 무시합니다 (읽기 전용 레지스터).

---

### 4.14 cnn_pcam_wrapper — 시스템 래퍼

**파일**: `verilog/src/cnn_pcam_wrapper.v`  
**VHDL 대응**: `src/cnn_pcam_wrapper.vhd`

**역할**: Vivado Block Design에서 하나의 IP로 사용할 수 있도록 모든 서브모듈을 래핑합니다.

**내부 구조**:
```
┌─────────────────────────────────────────┐
│              cnn_pcam_wrapper            │
│                                         │
│  s_axis_* ──→ [axi_stream_to_rgb]       │
│                       │                 │
│                       ▼                 │
│               [cnn_top]                 │
│                 │     │                 │
│                 ▼     ▼                 │
│  S_AXI_* ←─ [cnn_result_axilite]       │
│                                         │
│  prediction_out ←─ (4-bit)              │
│  probability_out ←─ (10-bit)            │
└─────────────────────────────────────────┘
```

**Block Design 연결**:
- `s_axis_*`: AXI Stream Broadcaster의 M01 (CNN 경로)
- `S_AXI_*`: PS M_AXI_GP0 (주소 0x40000000)
- `prediction_out`: GPIO/LED 연결 (선택)
- `probability_out`: 디버그 (선택)

---

## 5. 데이터 흐름 다이어그램

### 픽셀 데이터 흐름

```
카메라 (1280×720 RGB, 60fps)
    │
    │  24-bit AXI Stream
    ▼
[axi_stream_to_rgb_stream]  ← pixel_clk 생성
    │
    │  8-bit R/G/B + Column/Row
    ▼
[Grayscale 변환]  ← Gray = 0.299R + 0.587G + 0.114B
    │
    │  8-bit Gray + Column/Row
    ▼
[영역 크롭]  ← 448×448 영역 추출
    │
    ▼
[max_pooling_pre]  ← 448×448 → 28×28 (16:1)
    │
    │  8-bit Gray + Column(0~27)/Row(0~27)
    ▼
[rgb_to_cnn]  ← 10-bit CNN 값으로 변환
    │
    │  10-bit Data + CNN_Stream 제어신호
    ▼
[Conv1] → [Pool1] → [Conv2] → [Pool2] → [Conv3] → [Pool3]
 28×28×1   28×28×4   14×14×4   14×14×6   7×7×6    7×7×8    3×3×8
    │
    ▼
[Flatten]  ← 3×3×8 = 72개 1D 배열로
    │
    ▼
[FC Layer]  ← 72 → 10 (가중합 + ReLU)
    │
    ▼
[Argmax]  ← 10개 중 최대값의 인덱스
    │
    ▼
Prediction: 3   Probability: 891
```

### 제어 신호 흐름

```
Data_CLK: 전체 파이프라인의 기준 클럭
          (pixel_clk에서 파생, ~37.5 MHz)

Data_Valid: 유효 데이터 표시
            ┌─┐   ┌─┐   ┌─┐
            │ │   │ │   │ │
        ────┘ └───┘ └───┘ └────

Column/Row: 현재 처리 위치
Filter: 현재 채널/필터 인덱스 (시분할 시 변경)
```

---

## 6. CNN 아키텍처 상세

### LeNet 스타일 3-Layer CNN

```
Input (28×28×1)
    │
    ├── Conv1: 3×3 커널, 4 필터, same padding, stride 1
    │   └── 출력: 28×28×4, 활성화: ReLU
    │
    ├── Pool1: 2×2 Max Pooling, stride 2
    │   └── 출력: 14×14×4
    │
    ├── Conv2: 3×3 커널, 6 필터, same padding, stride 1
    │   └── 출력: 14×14×6, 활성화: ReLU
    │
    ├── Pool2: 2×2 Max Pooling, stride 2
    │   └── 출력: 7×7×6
    │
    ├── Conv3: 3×3 커널, 8 필터, same padding, stride 1
    │   └── 출력: 7×7×8, 활성화: ReLU
    │
    ├── Pool3: 2×2 Max Pooling, stride 2
    │   └── 출력: 3×3×8
    │
    ├── Flatten: 3×3×8 = 72
    │
    ├── FC: 72 → 10, 활성화: ReLU
    │
    └── Argmax → Prediction(0~9) + Probability(0~1023)
```

### 각 레이어별 텐서 크기

| 레이어 | 입력 크기 | 출력 크기 | 파라미터 수 |
|--------|-----------|-----------|------------|
| 전처리 | 448×448×1 | 28×28×1 | 0 |
| Conv1 | 28×28×1 | 28×28×4 | 40 |
| Pool1 | 28×28×4 | 14×14×4 | 0 |
| Conv2 | 14×14×4 | 14×14×6 | 222 |
| Pool2 | 14×14×6 | 7×7×6 | 0 |
| Conv3 | 7×7×6 | 7×7×8 | 440 |
| Pool3 | 7×7×8 | 3×3×8 | 0 |
| FC | 72 | 10 | 730 |
| **합계** | | | **1,438** |

---

## 7. 고정소수점 연산 이해하기

이 CNN은 **8-bit 고정소수점** 가중치와 **10-bit 고정소수점** 활성화 값을 사용합니다.

### Offset 파라미터의 의미

각 레이어의 `Offset` 파라미터는 곱셈 결과의 소수점 위치를 조정합니다.

```
실제 가중치 = ROM 값 × 2^(-Offset)
```

예: `Offset = 1`이면 ROM의 64는 실제로 32.0을 의미

### MAC 연산의 고정소수점 처리

```verilog
// VHDL 원본:
// sum := sum + shift_right(
//     to_signed(data * weight + 2^(WR-Offset-2), VR+WR),
//     WR-Offset-1);

// Verilog 변환:
sum <= sum + (($signed(data) * $signed(weight)
             + (1 << (WEIGHT_BITS - OFFSET - 2)))
            >>> (WEIGHT_BITS - OFFSET - 1));
```

여기서 `+ (1 << (WEIGHT_BITS - OFFSET - 2))`는 **반올림(rounding)** 항으로, 단순 버림(truncation) 대신 정확도를 높입니다.

### Out_Offset의 역할

레이어 간 소수점 자릿수가 다를 수 있으므로, `Offset_Diff = Offset_Out - Offset_In`으로 조정합니다:
- `Offset_Diff > 0`: 오른쪽 시프트 (축소)
- `Offset_Diff < 0`: 왼쪽 시프트 (확대)

---

## 8. FPGA 리소스 사용량

### Xilinx xc7z020clg400-1 (Zybo Z7-20)

| 리소스 | 사용 | 가용 | 사용률 |
|--------|------|------|--------|
| Slice LUTs | 1,832 | 53,200 | **3.44%** |
| Slice Registers | 2,486 | 106,400 | 2.34% |
| Block RAM (36Kb) | 3 tiles | 140 tiles | **2.14%** |
| DSP48E1 | 4 | 220 | **1.82%** |

**리소스가 매우 적은 이유**:
1. **시분할 처리**: 하나의 MAC 유닛을 여러 필터에 재사용
2. **8-bit 가중치**: 작은 곱셈기
3. **ROM 기반 가중치**: LUT로 매핑 (BRAM 3개만 사용)
4. **순차 처리**: 병렬 연산 최소화

---

## 9. 시뮬레이션 방법

### Icarus Verilog (오픈소스)

```bash
cd verilog
iverilog -I include -o sim tb/cnn_top_tb.v src/*.v
vvp sim
```

### Vivado Simulator

1. Vivado에서 프로젝트 생성
2. `verilog/src/*.v`를 Design Sources로 추가
3. `verilog/tb/cnn_top_tb.v`를 Simulation Sources로 추가
4. `verilog/include/`를 Include 경로에 추가
5. Run Simulation → Run Behavioral Simulation

### 기대 출력

```
=== Frame 0 start ===
=== Frame 0 end === Prediction=1 Probability=XXX
=== Frame 1 start ===
>> Prediction changed: 1 (prob=XXX)
=== Frame 1 end === Prediction=1 Probability=XXX
=== FINAL === Prediction=1 Probability=XXX
```

숫자 "1" 패턴을 입력했으므로 `Prediction=1`이 기대됩니다.

---

## 참고 자료

- **원본 프로젝트**: [OnSemi CNN Ultra](https://github.com/leonbeier/OnSemi_CNN_Ultra) (Leon Beier, VHDP)
- **VHDL 변환**: [CNN-VHDL-MNIST](https://github.com/squid55/CNN-VHDL-MNIST)
- **통합 프로젝트**: [Zybo-Z7-Pcam-MNIST-CNN](https://github.com/squid55/Zybo-Z7-Pcam-MNIST-CNN)
- **Pcam 데모**: [Digilent Zybo-Z7 Pcam-5C](https://github.com/Digilent/Zybo-Z7/releases)

---

*Generated: 2026-03-31 — VHDL to Verilog conversion with module documentation*
