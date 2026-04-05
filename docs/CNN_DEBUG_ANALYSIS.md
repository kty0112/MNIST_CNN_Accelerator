# CNN MNIST 실보드 디버깅 분석 보고서

> **날짜**: 2026-04-02  
> **증상**: CNN 결과가 항상 `Digit: 0, Confidence: 0% (raw: 0/1023)`  
> **환경**: Zybo Z7-20 + Pcam-5C (OV5640), HDMI 카메라 영상은 정상

---

## 1. 증상 요약

| 항목 | 상태 |
|------|------|
| HDMI 카메라 영상 | **정상** (720p@60fps) |
| UART 시리얼 통신 | **정상** (115200 baud) |
| CNN AXI-Lite Status (0x08) | `1` (응답 정상) |
| CNN Prediction (0x00) | `0` (항상) |
| CNN Probability (0x04) | `0` (항상) |

→ **카메라 파이프라인은 정상**, **CNN 추론 파이프라인이 동작하지 않음**

---

## 2. 디버깅 과정

### 2.1 비트스트림 버전 테스트

| 비트스트림 | 날짜 | 결과 |
|-----------|------|------|
| 원본 `cnn_pcam.bit` | 3/28 | Digit: 0, Confidence: 0% |
| 재빌드 v1 (원본 Pcam에서 CNN 재통합) | 3/31 | Digit: 0, Confidence: 0% |
| 재빌드 v2 (브릿지 타이밍 수정) | 4/1 | Digit: 0, Confidence: 0% |

3번의 리빌드 모두 동일한 증상 → **문제는 CNN IP 내부의 구조적 결함**

### 2.2 합성 경고 분석

CNN IP 합성 로그에서 발견된 **심각한 경고들**:

```
WARNING: [Synth 8-6014] Unused sequential element Buffer_RAM_reg was removed. (max_pooling_pre.vhd)
WARNING: [Synth 8-6014] Unused sequential element RAM_Data_In_reg was removed. (max_pooling_pre.vhd)
WARNING: [Synth 8-6014] Unused sequential element RAM_Addr_In_reg was removed. (max_pooling_pre.vhd)
WARNING: [Synth 8-3848] Net oStream_Buf[G] in module max_pooling_pre does not have driver.
WARNING: [Synth 8-3848] Net oStream_Buf[B] in module max_pooling_pre does not have driver.
```

**해석**: `max_pooling_pre` 모듈의 **RAM 전체가 합성 시 제거됨**! 448×448 → 28×28 다운스케일의 핵심인 행 방향 max 누적이 불가능.

---

## 3. 근본 원인 분석

### 원인 1 (확정): `max_pooling_pre` RAM_Enable 미구동 버그

**파일**: `src/max_pooling_pre.vhd`

```vhdl
signal RAM_Enable : std_logic := '0';  -- 초기값 '0', 이후 한번도 '1'로 안 바뀜!

-- RAM 쓰기 프로세스
process(iStream.New_Pixel)
begin
    if rising_edge(iStream.New_Pixel) then
        if RAM_Enable = '1' then                -- ← 절대 true가 안 됨!
            Buffer_RAM(RAM_Addr_In) <= ...;
        end if;
    end if;
end process;
```

**문제**: `RAM_Enable`이 선언만 되고 **어디에서도 '1'로 설정되지 않음**. VHDP → VHDL 변환 시 누락된 것으로 추정.

**영향**: 합성 도구가 "RAM에 아무것도 쓸 수 없다"고 판단 → Buffer_RAM, RAM_Data_In, RAM_Addr_In 전부 제거 → **행 방향 max pooling 불가** → 전처리 단계에서 데이터 손실

**수정 방안**: RAM 쓰기를 메인 프로세스 안에서 직접 수행하거나, RAM_Enable 신호를 적절히 구동

### 원인 2 (높음): `pixel_clk` 클럭 트리 미사용

**파일**: `src/axi_stream_to_rgb_stream.vhd`

```vhdl
signal pixel_clk : std_logic := '0';
...
pixel_clk <= not pixel_clk;          -- 플립플롭 출력을 클럭으로 사용
oStream.New_Pixel <= pixel_clk;       -- CNN 전체가 이 클럭으로 구동
```

**문제**: `pixel_clk`는 aclk 도메인의 **플립플롭 출력**인데, CNN 모듈들이 이를 `rising_edge()`/`falling_edge()`로 **클럭처럼 사용**. FPGA에서:

1. **BUFG 미삽입**: 자동 클럭 버퍼가 안 들어가서 클럭 스큐(skew)가 큼
2. **양 에지 사용**: `cnn_row_expander`와 `cnn_row_buffer`는 `falling_edge(Data_CLK)`도 사용 → 타이밍 제약 위반 가능성
3. **타이밍 분석 누락**: Vivado가 이 신호를 클럭으로 인식하지 않으면 타이밍 검증이 안 됨

**참고**: 원본 OnSemi VHDP 디자인에서는 카메라가 직접 pixel clock을 제공 → IBUF → BUFG로 정상 분배. 우리 디자인은 AXI Stream에서 내부 생성 → BUFG 없음.

### 원인 3 (중간): Convolution/Pooling 출력 시퀀싱 레지스터 제거

```
WARNING: [Synth 8-6014] Unused sequential element Delay_Cycle_reg was removed. (cnn_convolution.vhd)
WARNING: [Synth 8-6014] Unused sequential element oCycle_Cnt_reg was removed. (cnn_convolution.vhd)
WARNING: [Synth 8-6014] Unused sequential element oCycle_Cnt_reg was removed. (cnn_pooling.vhd)
WARNING: [Synth 8-6014] Unused sequential element oCycle_Cnt_reg was removed. (nn_layer.vhd)
```

**해석**: `Delay_Cycle`과 `oCycle_Cnt`는 시분할 출력을 제어하는 레지스터. 이것들이 제거되면 출력 시퀀싱이 깨짐.

**원인 추정**: `Filter_Delay=1`일 때 `natural range 0 to 0` → 상수 0 → 합성 시 제거 (정상 최적화일 수 있음). 하지만 `oCycle_Cnt`가 모든 레이어에서 제거된 것은 **출력 Valid 신호가 절대 발생하지 않음**을 의미할 수 있음.

### 원인 4 (낮음): `cnn_row_buffer` 포트 폭 불일치

```
WARNING: [Synth 8-7043] port width mismatch for port 'oRow': port width = 1, actual width = 5
WARNING: [Synth 8-7043] port width mismatch for port 'oColumn': port width = 1, actual width = 5
```

**해석**: `cnn_pooling`에서 `cnn_row_buffer`를 인스턴스할 때, `oRow`와 `oColumn` 포트의 비트 폭이 불일치. VHDL의 `buffer` 방향 포트와 `natural range` 타입 변환에서 발생한 문제로 보임.

---

## 4. 수정 계획

### Phase 1: `max_pooling_pre` RAM 버그 수정 (최우선)

```vhdl
-- 변경 전: 별도 프로세스에서 RAM_Enable 체크 (RAM_Enable이 항상 '0')
process(iStream.New_Pixel)
begin
    if rising_edge(iStream.New_Pixel) then
        if RAM_Enable = '1' then
            Buffer_RAM(RAM_Addr_In) <= RAM_Data_In(RAM_Bits-1 downto 0);
        end if;
    end if;
end process;

-- 변경 후: 메인 프로세스에서 조건부 직접 쓰기
-- (중간 행 완료 시 RAM에 저장)
if max_Col_Cnt = Filter_Columns-1 and
   iStream_Buf.Row mod Filter_Rows /= Filter_Rows-1 then
    Buffer_RAM(iStream_Buf.Column / Filter_Columns) <= max_Col_Buf_packed;
end if;
```

### Phase 2: `pixel_clk`에 BUFG 삽입

```vhdl
-- cnn_pcam_wrapper.vhd에서
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

signal pixel_clk_raw  : std_logic;
signal pixel_clk_bufg : std_logic;

BUFG_inst : BUFG port map (O => pixel_clk_bufg, I => pixel_clk_raw);
-- pixel_clk_bufg를 CNN에 전달
```

### Phase 3: `cnn_row_buffer` 포트 폭 수정

`oRow`, `oColumn` 포트의 `buffer` 방향을 `out`으로 변경하고 적절한 비트 폭 지정.

### Phase 4: Convolution/Pooling 출력 시퀀싱 검증

`oCycle_Cnt` 제거가 정상 최적화인지 로직 오류인지 확인. `Filter_Cycles > 1`인 레이어에서 출력이 정상 생성되는지 시뮬레이션으로 검증.

---

## 5. 파이프라인 데이터 흐름 디버그 포인트

```
AXI Stream (정상, HDMI 확인)
    │
    ▼
[axi_stream_to_rgb_stream]  ← pixel_clk 생성 (BUFG 없음, 원인2)
    │
    ▼
[Grayscale + Crop]
    │
    ▼
[max_pooling_pre]  ← ★ RAM 제거됨 (원인1) ★
    │                  행 방향 max 불가, 열 방향만 동작
    ▼
[rgb_to_cnn]
    │
    ▼
[Conv1] → [Pool1] → [Conv2] → [Pool2] → [Conv3] → [Pool3]
    │                           ↑ oCycle_Cnt 제거 (원인3)
    ▼
[FC Layer] → [Argmax]  ← 결과 영구 0
```

---

## 6. 검증 방법

### 시뮬레이션 (권장)
```bash
# Vivado Simulator로 cnn_top_tb 실행
cd /home/hyeonjun/Zybo-Z7-Pcam-MNIST-CNN/tb
# 28x28 숫자 "1" 패턴 입력 → Prediction이 1이 되는지 확인
```

### ILA 디버깅 (하드웨어)
Vivado ILA를 Broadcaster M01 출력에 연결하여:
1. `s_axis_tvalid` 토글 확인 (데이터가 CNN에 도착하는지)
2. `pixel_clk` 토글 확인 (CNN 클럭이 생성되는지)
3. `max_pooling_pre` 출력 확인 (전처리가 동작하는지)

---

## 7. 참고 파일

| 파일 | 설명 |
|------|------|
| `src/max_pooling_pre.vhd:38` | RAM_Enable 선언 (미구동) |
| `src/max_pooling_pre.vhd:55` | RAM write process (Buffer_RAM 제거됨) |
| `src/axi_stream_to_rgb_stream.vhd:45` | pixel_clk 생성 |
| `src/cnn_convolution.vhd:394` | Delay_Cycle (제거됨) |
| `src/cnn_pooling.vhd:228` | oCycle_Cnt (제거됨) |
| 합성 로그 | `/home/hyeonjun/cnn_pcam_rebuild/cnn_pcam.runs/system_cnn_mnist_0_0_synth_1/runme.log` |

---

*작성: 2026-04-02 — CNN 실보드 디버깅 분석*
