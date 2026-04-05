# FPGA CNN 하드웨어 설계 가이드 

> Zybo Z7-20에서 카메라 영상을 받아 **FPGA 하드웨어만으로** 손글씨 숫자(0~9)를 인식하는 CNN을 구현합니다.
> 소프트웨어(Python/C)가 아닌 **VHDL 하드웨어 회로**로 동작하므로, 매 픽셀 클럭마다 연산이 수행됩니다.

---

## 목차

1. [왜 FPGA로 CNN을 만드나?](#1-왜-fpga로-cnn을-만드나)
2. [전체 시스템 한눈에 보기](#2-전체-시스템-한눈에-보기)
3. [소프트웨어 CNN vs 하드웨어 CNN 차이](#3-소프트웨어-cnn-vs-하드웨어-cnn-차이)
4. [데이터 흐름: 픽셀이 숫자가 되기까지](#4-데이터-흐름-픽셀이-숫자가-되기까지)
5. [모듈별 상세 설명](#5-모듈별-상세-설명)
   - 5.1 [패키지 파일들 (타입 정의)](#51-패키지-파일들-타입-정의)
   - 5.2 [max_pooling_pre — 이미지 축소기](#52-max_pooling_pre--이미지-축소기)
   - 5.3 [rgb_to_cnn — 형식 변환기](#53-rgb_to_cnn--형식-변환기)
   - 5.4 [cnn_row_expander — 시간 확장기](#54-cnn_row_expander--시간-확장기)
   - 5.5 [cnn_row_buffer — 매트릭스 윈도우 생성기](#55-cnn_row_buffer--매트릭스-윈도우-생성기)
   - 5.6 [cnn_convolution — 컨볼루션 레이어](#56-cnn_convolution--컨볼루션-레이어)
   - 5.7 [cnn_pooling — Max Pooling 레이어](#57-cnn_pooling--max-pooling-레이어)
   - 5.8 [nn_layer — Fully Connected 레이어](#58-nn_layer--fully-connected-레이어)
   - 5.9 [cnn_top — 최상위 모듈 (전체 조립)](#59-cnn_top--최상위-모듈-전체-조립)
   - 5.10 [브릿지 모듈들 (Pcam 연동)](#510-브릿지-모듈들-pcam-연동)
6. [고정소수점 연산 이해하기](#6-고정소수점-연산-이해하기)
7. [타이밍과 리소스 트레이드오프](#7-타이밍과-리소스-트레이드오프)
8. [자주 묻는 질문 (FAQ)](#8-자주-묻는-질문-faq)

---

## 1. 왜 FPGA로 CNN을 만드나?

| | GPU (Jetson 등) | FPGA (Zybo 등) |
|---|---|---|
| **지연시간** | 수 ms (배치 처리) | 수 us (클럭 단위) |
| **전력** | 5~15W | 1~3W |
| **병렬성** | CUDA 코어 공유 | 전용 회로 |
| **유연성** | 모델 교체 쉬움 | 재합성 필요 |
| **적합 분야** | 복잡한 대형 모델 | 경량 모델, 실시간 반응 |

**이 프로젝트의 의미**: CNN을 하드웨어 회로로 직접 설계함으로써, 딥러닝이 실제로 어떤 연산을 수행하는지 **게이트 레벨까지** 이해할 수 있습니다.

---

## 2. 전체 시스템 한눈에 보기

```
Camera (Pcam-5C, 448x448 RGB)
  |
  v
+---[ cnn_top.vhd ]----------------------------------------+
|                                                          |
|  [1] Grayscale (RGB -> Gray)                             |
|        Gray = (77*R + 150*G + 29*B) / 256                |
|                       |                                  |
|  [2] max_pooling_pre (448x448 -> 28x28)                  |
|        16x16 block max pooling                           |
|                       |                                  |
|  [3] rgb_to_cnn (format convert)                         |
|        8bit -> 10bit, pixel_clk -> data_clk              |
|                       |                                  |
|  [4] Conv1 (28x28x1 -> 28x28x4)  3x3, 4 filters, ReLU  |
|                       |                                  |
|  [5] MaxPool1 (28x28x4 -> 14x14x4)  2x2 max             |
|                       |                                  |
|  [6] Conv2 (14x14x4 -> 14x14x6)  3x3, 6 filters, ReLU  |
|                       |                                  |
|  [7] MaxPool2 (14x14x6 -> 7x7x6)  2x2 max               |
|                       |                                  |
|  [8] Conv3 (7x7x6 -> 7x7x8)  3x3, 8 filters, ReLU      |
|                       |                                  |
|  [9] MaxPool3 (7x7x8 -> 3x3x8)  2x2 max                 |
|                       |                                  |
| [10] Flatten (3x3x8 = 72 values)                        |
|                       |                                  |
| [11] FC Layer (72 -> 10, ReLU)                           |
|                       |                                  |
| [12] Argmax (pick max of 10)                             |
|                       |                                  |
|              Prediction = 3                              |
|              Probability = 891 (87%)                     |
+----------------------------------------------------------+
```

---

## 3. 소프트웨어 CNN vs 하드웨어 CNN 차이

소프트웨어에서 CNN을 돌리면 이렇게 합니다:

```python
# Python (PyTorch)
output = conv_layer(input_image)   # GPU가 행렬 곱셈을 수행
```

하드웨어 CNN은 완전히 다른 방식으로 동작합니다:

```
소프트웨어: 이미지 전체를 메모리에 올려놓고, 한꺼번에 계산
하드웨어:   픽셀이 한 개씩 클럭마다 흘러들어오고, 파이프라인으로 즉시 계산
```

### 핵심 차이: "스트리밍 처리"

```
Software CNN:
  +------------+     +------------+     +------------+
  | Full Image | --> | Full Conv  | --> | Full Pool  |
  | in memory  |     | at once    |     | at once    |
  +------------+     +------------+     +------------+

Hardware CNN (this project):
  pixel 1 --> [Conv pipeline] --> [Pool pipeline] --> ...
  pixel 2 --> [Conv pipeline] --> [Pool pipeline] --> ...
  pixel 3 --> [Conv pipeline] --> [Pool pipeline] --> ...
    (at camera speed, no frame buffer needed)
```

이 때문에 FPGA CNN은:
- 이미지 전체를 저장할 큰 메모리가 **필요 없음**
- 대신 **몇 행만 버퍼링** (Row Buffer)하면 됨
- 컨볼루션에 필요한 **3×3 윈도우 데이터만** 유지

---

## 4. 데이터 흐름: 픽셀이 숫자가 되기까지

### 4.1 데이터 타입의 변천

```
Camera output:  rgb_stream  (8bit R,G,B + Column + Row + New_Pixel)
                    |
                    v  Grayscale + MaxPool downscale
                    |
CNN input:      rgb_stream  (8bit Gray only, 28x28)
                    |
                    v  rgb_to_cnn conversion
                    |
CNN internal:   CNN_Stream_T  (10bit Data + Column + Row + Filter + Data_CLK)
                    |
                    v  Conv -> Pool -> Conv -> Pool -> Conv -> Pool -> FC -> Argmax
                    |
CNN output:     Prediction (0~9) + Probability (0~1023)
```

### 4.2 두 가지 "클럭"을 이해하기

이 시스템에는 두 가지 클럭 개념이 있습니다:

| 클럭 | 신호 | 속도 | 용도 |
|------|------|------|------|
| **픽셀 클럭** | `New_Pixel` | 카메라 출력 속도 | 전처리 (축소, 변환) |
| **데이터 클럭** | `Data_CLK` | 더 빠름 (Row Expander가 조절) | CNN 레이어 내부 연산 |

```
New_Pixel:  _-_-_-_-_-_-_-_-_-_-_-_-    (픽셀마다 1번)
Data_CLK:   _-_-_-_-_-_-_-_-_-_-_-_-    (같은 클럭이지만...)
Data_Valid:  _/---\______________/---\    (유효 데이터는 간헐적)
```

중요: `Data_CLK`는 항상 뛰지만, `Data_Valid = '1'`인 순간에만 실제 데이터가 유효합니다.

---

## 5. 모듈별 상세 설명

### 5.1 패키지 파일들 (타입 정의)

패키지 파일은 "공유 사전"입니다. 모든 모듈이 사용하는 타입과 상수를 정의합니다.

#### `image_data_pkg.vhd` — 카메라 데이터 타입

```vhdl
-- 픽셀 한 개의 색상
type rgb_data is record
    R : std_logic_vector(7 downto 0);   -- 빨강 (0~255)
    G : std_logic_vector(7 downto 0);   -- 초록 (0~255)
    B : std_logic_vector(7 downto 0);   -- 파랑 (0~255)
end record;

-- 카메라에서 흘러나오는 픽셀 스트림
type rgb_stream is record
    R, G, B   : std_logic_vector(7 downto 0);   -- 색상
    Column    : natural range 0 to 645;           -- X 좌표 (가로 위치)
    Row       : natural range 0 to 482;           -- Y 좌표 (세로 위치)
    New_Pixel : std_logic;                        -- ↑ 이 신호가 뛰면 새 픽셀!
end record;
```

**비유**: `rgb_stream`은 컨베이어 벨트 위의 택배 상자. 각 상자(픽셀)에는 색상 정보와 "몇 번째 줄 몇 번째 칸" 라벨이 붙어있습니다.

#### `cnn_config_pkg.vhd` — CNN 설정

```vhdl
-- 값의 비트폭
CNN_Value_Resolution  = 10   -- 활성화 출력: 0~1023 (10비트)
CNN_Weight_Resolution = 8    -- 가중치: -127~+127 (8비트)

-- CNN 내부 스트림 타입
type CNN_Stream_T is record
    Column     : natural;    -- X 좌표
    Row        : natural;    -- Y 좌표
    Filter     : natural;    -- 현재 필터/채널 번호
    Data_Valid : std_logic;  -- '1'이면 데이터 유효
    Data_CLK   : std_logic;  -- 데이터 클럭
end record;
```

왜 10비트인가?
- 8비트(0~255)로는 레이어를 거치면서 값이 너무 쉽게 포화됨
- 10비트(0~1023)로 하면 여유가 생겨 정밀도 유지

#### `cnn_data_pkg.vhd` — 학습된 가중치 저장소

이 파일이 CNN의 "뇌"입니다. TensorFlow로 학습한 가중치 1,438개가 상수로 저장되어 있습니다.

```vhdl
-- Conv1 가중치 예시 (4개 필터 × 10개 입력 = 40개)
constant Layer_1 : CNN_Weights_T := (
    (63, -35, -16, -20, 62, -32, 34, 22, -44, -14),  -- 필터 0
    (44, 34, -25, 32, -3, -36, -3, -41, -26, -2),    -- 필터 1
    (3, -64, -31, 10, -2, -22, 34, 59, 3, -2),       -- 필터 2
    (54, 20, -37, 41, -20, 43, 33, 61, 26, 0)        -- 필터 3
);
```

**가중치 배열 구조 (각 레이어)**:

```
Layer_1: [필터 수 4] × [커널 3×3=9 + 바이어스 1 = 10] = 40개
Layer_2: [필터 수 6] × [커널 3×3×4=36 + 바이어스 1 = 37] = 222개
Layer_3: [필터 수 8] × [커널 3×3×6=54 + 바이어스 1 = 55] = 440개
NN_Layer_1: [출력 10] × [입력 72 + 바이어스 1 = 73] = 730개
                                                    총합 = 1,438개
```

각 가중치는 **8비트 정수** (-127 ~ +127)로, `128 = 1.0`을 기준으로 한 고정소수점입니다.

---

### 5.2 `max_pooling_pre` — 이미지 축소기

**파일**: `max_pooling_pre.vhd`
**역할**: 카메라 원본(448×448)을 CNN 입력 크기(28×28)로 축소

```
448 ÷ 28 = 16  →  16×16 블록마다 최대값 1개 선택
```

**왜 Max인가?**
MNIST 손글씨는 흰 글씨/검은 배경이므로, 16×16 영역에서 **가장 밝은 픽셀**(=글씨일 확률 높음)을 선택하면 글자 특징이 보존됩니다.

**동작 원리 (2단계)**:

```
Step 1: horizontal max (16 cols -> 1)
  [p0, p1, p2, ..., p15] -> max(p0~p15) -> col_max

Step 2: vertical max (16 rows -> 1)
  Row 0:  col_max -> save to RAM
  Row 1:  col_max vs RAM -> keep larger
  ...
  Row 15: col_max vs RAM -> final max -> output!
```

**RAM 사용**: 28개 열의 중간 max 결과를 한 행분만 저장 (매우 적은 메모리)

**코드 핵심 부분** (`max_pooling_pre.vhd:100-108`):

```vhdl
-- 가로 방향: 16개 픽셀 중 max
if max_Col_Cnt = 0 then
    max_Col_Buf.R := iStream_Buf.R;         -- 첫 픽셀: 무조건 저장
else
    if unsigned(iStream_Buf.R) > unsigned(max_Col_Buf.R) then
        max_Col_Buf.R := iStream_Buf.R;     -- 더 밝으면 교체
    end if;
end if;
```

---

### 5.3 `rgb_to_cnn` — 형식 변환기

**파일**: `rgb_to_cnn.vhd`
**역할**: 카메라 형식(`rgb_stream`) → CNN 내부 형식(`CNN_Stream_T`)으로 변환

```
rgb_stream                        CNN_Stream_T + CNN_Values_T
+------------+                    +--------------------+
| R (8bit)   | -- extend 10bit -> | Data(0) (10bit)    |
| Column     | -- pass through -> | Column             |
| Row        | -- pass through -> | Row                |
| New_Pixel  | -----------------> | Data_CLK           |
|            |    col change    -> | Data_Valid          |
+------------+                    +--------------------+
```

**왜 필요한가?**
- 전처리(max_pooling_pre)는 카메라 타입(`rgb_stream`)으로 동작
- CNN 레이어들은 내부 타입(`CNN_Stream_T`)으로 동작
- 이 모듈이 둘을 연결하는 **어댑터** 역할

---

### 5.4 `cnn_row_expander` — 시간 확장기

**파일**: `cnn_row_expander.vhd`
**역할**: 빠르게 도착하는 픽셀 사이에 빈 시간을 삽입하여 컨볼루션 계산 시간 확보

**이것이 하드웨어 CNN의 핵심 트릭입니다!**

```
Problem: one convolution needs 3x3 x input_channels = many multiplications
         but only 1~2 DSP blocks available?
         -> stretch time, compute sequentially over many clocks!

Input:  [A][B][C][D]________________     (pixels arrive fast)
Output: [A]____[B]____[C]____[D]____     (gaps inserted between data)
               ^ convolution computes during this gap!
```

**각 레이어별 확장량**:

| 레이어 | 입력 크기 | Expand_Cycles | 의미 |
|--------|----------|---------------|------|
| Conv1 | 28×28 | 240 | 픽셀 간 240클럭 |
| Conv2 | 14×14 | 960 | 픽셀 간 960클럭 |
| Conv3 | 7×7 | 3840 | 픽셀 간 3840클럭 |

왜 점점 커지나? 레이어가 깊어질수록 입력 채널이 많아져서 계산량이 늘기 때문.

**내부 구조**:

```
Input pixel --> [RAM: store 1 row] --> [Timer: gap control] --> Output
                (falling edge write)   (Delay_Cnt counter)   (rising edge read)
```

---

### 5.5 `cnn_row_buffer` — 매트릭스 윈도우 생성기

**파일**: `cnn_row_buffer.vhd`
**역할**: 픽셀 스트림에서 3×3 윈도우 데이터를 순차적으로 출력

**이것이 "스트리밍 컨볼루션"의 핵심입니다!**

소프트웨어에서는 이미지 전체가 메모리에 있으므로 아무 위치나 접근 가능합니다.
하드웨어에서는 픽셀이 한 줄씩 순서대로 흘러오므로, **미래 행은 아직 없고 과거 행은 이미 지나갔습니다**.

해결법: **순환 버퍼(Ring Buffer)**로 최근 3개 행만 보관

```
Pixels streaming from camera:
  Row 0: [a b c d e f ...]
  Row 1: [g h i j k l ...]    <-- stored in ring buffer
  Row 2: [m n o p q r ...]    <-- currently writing

3x3 window output (at position 1,1):
  [a b c]
  [g h i]  -> these 9 values output sequentially
  [m n o]
```

**패딩 처리**:
- `same` 패딩: 가장자리 바깥은 0으로 채움 → 출력 크기 = 입력 크기
- `valid` 패딩: 가장자리 제외 → 출력 크기 < 입력 크기

**코드에서 패딩 처리** (`cnn_row_buffer.vhd`):

```vhdl
-- 범위 밖 좌표 체크
if oColumn_Reg + Column_Cntr < 0 or oColumn_Reg + Column_Cntr > Input_Columns - 1
   or oRow_Reg + Row_Cntr < 0 or oRow_Reg + Row_Cntr > Input_Rows - 1 then
    oData_En_Reg <= '0';   -- 범위 밖 → 0으로 패딩
else
    oData_En_Reg <= '1';   -- 범위 안 → 실제 데이터
end if;
```

---

### 5.6 `cnn_convolution` — 컨볼루션 레이어

**파일**: `cnn_convolution.vhd` (가장 복잡한 모듈, 428줄)
**역할**: 3×3 커널 × 가중치 곱셈-누적(MAC) → 바이어스 더하기 → ReLU 활성화

이 모듈 하나가 소프트웨어의 `nn.Conv2d()`와 같은 일을 합니다.

#### 전체 구조

```
Input Stream
    |
    v
[Row Expander] -- stretch time (make room for computation)
    |
    v
[Row Buffer] -- generate 3x3 window data
    |
    v
[ROM] -- read weights (synthesized as Block RAM)
    |
    v
[MAC Engine] -- sum += input * weight  (core operation!)
    |
    v
[SUM RAM] -- store partial sums across cycles
    |
    v
[+ Bias -> ReLU] -- add bias, clamp negatives to 0
    |
    v
[OUT RAM] -- store activation results
    |
    v
Output Stream
```

#### MAC 연산 (핵심 수식)

```vhdl
-- cnn_convolution.vhd:373
sum(o) := sum(o) + shift_right(
    to_signed(
        iData(i) * Weights_Buf_Var(o, i) + 2**(Weight_Res - Offset - 2),
        Value_Res + Weight_Res
    ),
    Weight_Res - Offset - 1
);
```

이게 무슨 뜻인지 단계별로:

```
① iData(i) × Weight(o,i)
   = 입력값(10bit) × 가중치(8bit)
   = 18bit 결과

② + 2^(Weight_Res - Offset - 2)
   = 반올림 바이어스 (0.5에 해당)
   예: Weight_Res=8, Offset=1 → +2^5 = +32

③ >> (Weight_Res - Offset - 1)
   = 고정소수점 스케일 정규화
   예: >>6 = ÷64

전체 의미:  sum += round(input × weight / scale)
```

#### 리소스 절약 트릭: "시분할"

DSP 블록(곱셈기)은 FPGA에서 가장 귀한 자원입니다.

```
Problem: Conv1 needs 4 filters -> need 4 multipliers?
Solution: set Calc_Cycles = 4 -> reuse 1 multiplier 4 times!

Clock 1: filter 0 multiply
Clock 2: filter 1 multiply   <-- same DSP reused!
Clock 3: filter 2 multiply
Clock 4: filter 3 multiply

Result: 1 DSP instead of 4! (4x smaller, but 4x slower)
```

#### 바이어스와 활성화 함수

```vhdl
-- 바이어스 더하기 (고정소수점 스케일링 적용)
sum_buf(o) := sum_buf(o) + shift_left(Bias, Offset);

-- Offset_Diff로 레이어 간 스케일 맞추기
sum_buf(o) := shift_right(sum_buf(o), Offset_Diff);

-- ReLU 활성화: 음수는 0, 양수는 그대로 (최대 1023)
Act_sum(o) := relu_f(sum_buf(o), 1023);
```

---

### 5.7 `cnn_pooling` — Max Pooling 레이어

**파일**: `cnn_pooling.vhd`
**역할**: 2×2 영역에서 최대값만 남기고 크기 절반으로 축소

```
Input (4x4):            Output (2x2):
+-----+-----+          +-----+-----+
| 3 7 | 2 1 |          |  7  |  4  |
| 5 4 | 4 3 |  ---->   +-----+-----+
+-----+-----+          |  9  |  8  |
| 9 2 | 8 6 |          +-----+-----+
| 1 3 | 5 2 |
+-----+-----+
```

**구조**: Convolution과 매우 비슷! (Row Buffer로 윈도우 생성)

```
Difference:
  Convolution: sum += input * weight   (multiply-accumulate, needs DSP)
  Pooling:     max = max(curr, prev)   (compare only, no DSP needed!)
```

**핵심 비교 로직** (`cnn_pooling.vhd:182-185`):

```vhdl
for in_offset in 0 to Calc_Outputs-1 loop
    MAX_ram_v := Matrix_Data(in_offset);
    if (Matrix_Row = 0 and Matrix_Column = 0)        -- 첫 번째: 무조건 저장
       or MAX_ram_v > to_integer(max_v(in_offset)) then  -- 더 크면 교체
        max_v(in_offset) := to_signed(MAX_ram_v, CNN_Value_Resolution+1);
    end if;
end loop;
```

---

### 5.8 `nn_layer` — Fully Connected 레이어

**파일**: `nn_layer.vhd`
**역할**: 72개 입력을 10개 출력(숫자 0~9)으로 변환

Convolution과의 차이:

```
Convolution (local connections):
  each output neuron sees only 3x3 = 9 inputs
  -> needs Row Buffer (store 3 rows)

Fully Connected (global connections):
  each output neuron sees all 72 inputs
  -> no Row Buffer needed! inputs arrive sequentially
```

**이 프로젝트의 FC 레이어**:

```
Inputs:  72  (3x3x8 flattened)
Outputs: 10  (score for each digit 0~9)
Weights: 10 x 73 = 730  (72 inputs + 1 bias)

Computation:
  out[0] = ReLU(w[0,0]*in[0] + w[0,1]*in[1] + ... + w[0,71]*in[71] + bias[0])
  out[1] = ReLU(w[1,0]*in[0] + w[1,1]*in[1] + ... + w[1,71]*in[71] + bias[1])
  ...
  out[9] = ReLU(w[9,0]*in[0] + w[9,1]*in[1] + ... + w[9,71]*in[71] + bias[9])
```

**시분할 처리**: `Out_Cycles = 10`이므로, 10개 출력을 1개씩 순차 계산 - 곱셈기 1개로 10개 뉴런 처리 가능

---

### 5.9 `cnn_top` — 최상위 모듈 (전체 조립)

**파일**: `cnn_top.vhd`
**역할**: 위의 모든 모듈을 연결하는 **조립도**

#### Grayscale 변환

```vhdl
-- BT.601 표준 근사: Y = 0.299R + 0.587G + 0.114B
-- 정수 연산으로: Y = (77R + 150G + 29B) >> 8
r_mult  := 77  * unsigned(R);     -- 0.301 ≈ 77/256
g_mult  := 150 * unsigned(G);     -- 0.586 ≈ 150/256
b_mult  := 29  * unsigned(B);     -- 0.113 ≈ 29/256
gray    := (r_mult + g_mult + b_mult) >> 8;
```

왜 나누기 대신 시프트? FPGA에서 나눗셈은 많은 자원을 소모하지만, 2의 거듭제곱 나눗셈은 **비트 시프트 한 번**이면 됩니다.

#### Flatten (3D -> 1D 변환)

```vhdl
-- 3x3x8 = 72 values mapped to 1D index
iCycle_1N <= (Row * 3 + Column) * 8 + Filter;

-- Example: Row=1, Column=2, Filter=3
-- (1*3 + 2)*8 + 3 = 43rd input
```

#### Argmax (최종 판단)

```vhdl
-- 10개 출력 중 가장 큰 값의 인덱스 = 인식된 숫자
if oCycle_1N = 0 then           -- 첫 출력(숫자 0의 점수)
    max_v := 0;
    max_number_v := 0;
end if;
if oData_1N(0) > max_v then    -- 더 높은 점수 발견
    max_v := oData_1N(0);       -- 최고 점수 갱신
    max_number_v := oCycle_1N;  -- 해당 숫자 기억
end if;
if oCycle_1N = 9 then           -- 마지막 출력(숫자 9의 점수)
    Prediction  <= max_number_v;  -- 최종 답: 어떤 숫자?
    Probability <= max_v;         -- 얼마나 확신? (0~1023)
end if;
```

---

### 5.10 브릿지 모듈들 (Pcam 연동)

CNN 코어는 독립적으로 동작하지만, Zybo의 Pcam 카메라 시스템(AXI 기반)과 연결하려면 **브릿지**가 필요합니다.

#### `axi_stream_to_rgb_stream.vhd`

```
Pcam AXI Stream --> rgb_stream (CNN input format)

AXI Stream (24bit):        rgb_stream:
  tdata[23:0]        --->    R = tdata[7:0]
  tvalid/tready      --->    G = tdata[15:8]
  tlast              --->    B = tdata[23:16]
  tuser              --->    Column (counter)
                             Row (increments on tlast)
                             New_Pixel (tvalid & tready)
```

#### `cnn_result_axilite.vhd`

```
CNN result --> AXI-Lite registers (ARM CPU reads these)

Prediction (0~9)  --->  Register 0x00 (Read-Only)
Probability       --->  Register 0x04 (Read-Only)
Status (valid)    --->  Register 0x08 (Read-Only)
```

#### `cnn_pcam_wrapper.vhd`

세 모듈을 하나로 묶는 래퍼:

```
AXI Stream Slave ---> [axi_stream_to_rgb_stream]
                              |
                              v
                        [cnn_top]
                              |
                              v
                     [cnn_result_axilite] ---> AXI-Lite Slave
```

---

## 6. 고정소수점 연산 이해하기

FPGA에는 부동소수점(float) 연산기가 없습니다. 대신 **고정소수점**을 사용합니다.

### 기본 개념

```
Floating point: 0.75 = 0.75  (float, 32bit)
Fixed point:    0.75 = 96/128  (integer 96, scale 128)

This project:
  Weight scale: 2^7 = 128 -> weight value 128 means real 1.0
  Value scale: varies per layer (controlled by Out_Offset)
```

### Offset 파라미터의 의미

```
Layer 1: Out_Offset = 3 -> divide output by 2^3 = 8
Layer 2: Out_Offset = 3 -> divide output by 2^3 = 8
Layer 3: Out_Offset = 5 -> divide output by 2^5 = 32
FC:      Out_Offset = 6 -> divide output by 2^6 = 64
```

왜 점점 커지나?
- 레이어가 깊어질수록 곱셈이 누적되어 값이 커짐
- Offset을 늘려서 10bit 범위(0~1023) 안에 유지

### MAC 연산 예시

```
Input:  500 (10bit, scale 2^3=8 -> real 62.5)
Weight: 64  (8bit, scale 2^7=128 -> real 0.5)
Offset: 1

Computation:
  500 * 64 = 32,000
  + rounding bias = 32,000 + 32 = 32,032
  >> (8-1-1) = >> 6 = 32,032 / 64 = 500

Result: 500 (real: 62.5 * 0.5 = 31.25, matches with scale)
```

---

## 7. 타이밍과 리소스 트레이드오프

FPGA 설계의 핵심 결정: **빠르게 vs 작게**

```
Fast (parallel):
  Compute Conv1's 4 filters simultaneously
  -> needs 4 DSPs, done in 1 clock
  -> large area but fast

Small (time-sharing -- this project's approach):
  Compute Conv1's 4 filters sequentially (Calc_Cycles=4)
  -> needs 1 DSP, done in 4 clocks
  -> small area but slower
```

**이 프로젝트의 리소스 사용량**:

```
Slice LUTs:  1,832 / 53,200  =  3.44%  (96.5% remaining!)
Block RAM:   3     / 140      =  2.14%
DSP48E1:     4     / 220      =  1.82%
```

FPGA 자원의 **2~3%만** 사용. 이 여유로:
- HDMI 오버레이 추가 가능
- 더 큰 CNN 모델 적용 가능
- 여러 CNN을 병렬로 돌릴 수도 있음

---

## 8. 자주 묻는 질문 (FAQ)

### Q: 가중치는 어떻게 학습하나요?

TensorFlow/Keras로 PC에서 학습한 후, 가중치를 8bit 정수로 양자화하여 `cnn_data_pkg.vhd`에 복사합니다. FPGA 자체에서는 학습하지 않습니다 (추론만 수행).

### Q: 왜 이미지를 448×448에서 28×28로 줄이나요?

MNIST 데이터셋이 28×28이기 때문입니다. 학습된 가중치가 28×28 입력을 기대하므로, 카메라 영상을 맞춰줘야 합니다.

### Q: ReLU가 하드웨어에서 어떻게 구현되나요?

놀랍도록 간단합니다:

```vhdl
function relu_f(i : integer; max : integer) return integer is
begin
    if i > 0 then           -- 양수면
        if i < max then
            return i;       -- 그대로 통과
        else
            return max;     -- 포화 방지 (clamp)
        end if;
    else
        return 0;           -- 음수면 0
    end if;
end function;
```

소프트웨어의 `max(0, x)`와 동일하지만, 이것이 **실제 비교기 회로**로 합성됩니다.

### Q: Block RAM은 어디에 쓰이나요?

| 용도 | 모듈 | 설명 |
|------|------|------|
| **가중치 ROM** | Convolution, NN_Layer | 1,438개 가중치 저장 |
| **Row Buffer** | Row Buffer | 3행분 픽셀 데이터 저장 |
| **SUM RAM** | Convolution, NN_Layer | 시분할 시 부분합 저장 |
| **OUT RAM** | Convolution, NN_Layer, Pooling | 활성화 출력 임시 저장 |
| **MAX RAM** | Pooling | 부분 max 저장 |

### Q: DSP48E1은 어떤 연산을 하나요?

Xilinx DSP48E1은 `A × B + C`를 **1클럭**에 수행하는 전용 곱셈-누적 블록입니다.
이 프로젝트에서는 `input × weight + partial_sum` (MAC) 연산에 사용됩니다.

### Q: 다른 숫자 인식 모델로 바꿀 수 있나요?

네. `cnn_data_pkg.vhd`의 가중치 상수만 교체하면 됩니다.
단, 네트워크 구조(레이어 수, 필터 수, 커널 크기)를 바꾸려면 `cnn_top.vhd`의 제네릭 파라미터도 수정해야 합니다.

### Q: 처리 속도는 얼마나 되나요?

카메라 프레임마다 1회 추론. 30fps 카메라 → **초당 30회 추론**.
각 추론의 지연시간은 **마이크로초(us) 단위** (GPU의 밀리초와 비교하면 1000배 빠름).

---

## 참고 자료

- [CNN VHDL Module Guide (영문)](../CNN_VHDL_MODULE_GUIDE.md) — 개발자용 상세 문서
- [CNN RTL 회로도](../cnn_schematic.pdf) — Vivado 합성 후 회로도
- [원본 VHDPlus 프로젝트](https://github.com/leonbeier/OnSemi_CNN_Ultra) — Leon Beier

---

*이 문서는 FPGA 디지털 설계 수업의 학생들을 위해 작성되었습니다.*
*최종 업데이트: 2026-03-30*
